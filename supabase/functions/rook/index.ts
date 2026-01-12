// Minimal Rook webhook receiver
// Accepts POST, stores headers + payload into rook_webhook_events, always responds 200.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { scoringSchema } from "./scoring/schema.ts";
import { recomputeRolling7dScoresForUser } from "./scoring/recompute.ts";
import { evaluatePatternsForUser } from "./patterns/engine.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceRoleKey =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY")!;
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

function asString(v: unknown): string | null {
  return typeof v === "string" && v.trim().length > 0 ? v : null;
}

function asNumber(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim().length > 0) {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function deepFindByKey(obj: unknown, key: string, maxDepth = 8): unknown | null {
  if (!obj || typeof obj !== "object") return null;
  const queue: Array<{ v: unknown; d: number }> = [{ v: obj, d: 0 }];
  const seen = new Set<unknown>();

  while (queue.length) {
    const { v, d } = queue.shift()!;
    if (!v || typeof v !== "object") continue;
    if (seen.has(v)) continue;
    seen.add(v);

    if (d > maxDepth) continue;

    if (Array.isArray(v)) {
      for (const item of v) queue.push({ v: item, d: d + 1 });
      continue;
    }

    const rec = v as Record<string, unknown>;
    if (key in rec) return rec[key] ?? null;
    for (const k of Object.keys(rec)) queue.push({ v: rec[k], d: d + 1 });
  }
  return null;
}

function normalizeSource(raw: string | null): string {
  if (!raw) return "unknown";
  const s = raw.toLowerCase().trim();
  if (s.includes("apple")) return "apple_health";
  if (s.includes("whoop")) return "whoop";
  if (s.includes("oura")) return "oura";
  if (s.includes("fitbit")) return "fitbit";
  if (s.includes("garmin")) return "garmin";
  if (s.includes("withings")) return "withings";
  if (s.includes("polar")) return "polar";
  return s.replace(/\s+/g, "_");
}

function toISODateYYYYMMDD(rawDate: string | null): string | null {
  if (!rawDate) return null;
  // If already looks like YYYY-MM-DD, accept directly
  if (/^\d{4}-\d{2}-\d{2}$/.test(rawDate)) return rawDate;
  // Common ROOK format: "YYYY-MM-DDTHH:mm:ss...."
  if (/^\d{4}-\d{2}-\d{2}T/.test(rawDate)) return rawDate.slice(0, 10);
  const d = new Date(rawDate);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString().split("T")[0];
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });
}

function parseISODateYYYYMMDDToUTCDate(dayKey: string): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dayKey)) return null;
  const d = new Date(`${dayKey}T00:00:00Z`);
  return Number.isNaN(d.getTime()) ? null : d;
}

function toYYYYMMDD(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function addDaysUTC(dayKey: string, deltaDays: number): string | null {
  const d = parseISODateYYYYMMDDToUTCDate(dayKey);
  if (!d) return null;
  d.setUTCDate(d.getUTCDate() + deltaDays);
  return toYYYYMMDD(d);
}

function clampEndDateToToday(dayKey: string): string {
  const today = toYYYYMMDD(new Date());
  return dayKey > today ? today : dayKey;
}

function computeAgeYears(dobISO: string): number | null {
  const dob = new Date(dobISO);
  if (Number.isNaN(dob.getTime())) return null;
  const now = new Date();
  let age = now.getUTCFullYear() - dob.getUTCFullYear();
  const m = now.getUTCMonth() - dob.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < dob.getUTCDate())) {
    age -= 1;
  }
  return age >= 0 ? age : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method === "GET") {
    return jsonResponse({ ok: true, message: "rook webhook alive" });
  }

  if (req.method === "POST") {
    const receivedAt = new Date().toISOString();
    const rawBody = await req.text();
    let payload: Record<string, unknown> | unknown;
    try {
      payload = rawBody ? JSON.parse(rawBody) : {};
    } catch (_err) {
      payload = { parse_error: true };
    }

    const headersObj = Object.fromEntries(req.headers.entries());
    console.log("rook webhook received", {
      receivedAt,
      contentLength: rawBody?.length ?? 0,
      contentType: req.headers.get("content-type"),
      userAgent: req.headers.get("user-agent"),
    });

    const { error } = await supabase.from("rook_webhook_events").insert({
      headers: headersObj,
      payload,
      raw_body: rawBody || null,
      source: "rook",
    });

    if (error) {
      console.error("rook webhook insert error", error);
      // Still return 200 to keep Rook happy
      return jsonResponse({ ok: false, error: error.message });
    }

    console.log("rook webhook stored event", { receivedAt });

    // Attempt to parse and upsert metrics into wearable_daily_metrics
    try {
      const body = payload as any;
      const dataStructure = body.data_structure ?? body.dataStructure ?? "unknown";
      console.log("🔵 MIYA_PARSING_START", { dataStructure, userId: body.user_id ?? body.userId });

      // ROOK payloads are often nested; extract key fields defensively.
      const rookUserId = asString(
        body.userId ??
          body.user_id ??
          body.clientUserId ??
          body.client_user_id ??
          deepFindByKey(body, "user_id_string") ??
          deepFindByKey(body, "userId") ??
          deepFindByKey(body, "user_id")
      );

      const sourcesArr =
        deepFindByKey(body, "sources_of_data_array") ??
        deepFindByKey(body, "sourcesOfDataArray") ??
        null;
      const sourceRaw =
        asString(body.source ?? body.provider ?? body.device ?? body.data_source ?? body.dataSource) ??
        (Array.isArray(sourcesArr) ? asString(sourcesArr[0]) : null);
      const source = normalizeSource(sourceRaw);

      const dateRaw = asString(
        body.date ??
          body.metric_date ??
          body.startDate ??
          body.start_date ??
          body.dateTime ??
          deepFindByKey(body, "sleep_date_string") ??
          deepFindByKey(body, "datetime_string") ??
          deepFindByKey(body, "datetime") ??
          deepFindByKey(body, "date_time")
      );
      const metricDate = toISODateYYYYMMDD(dateRaw);

      // Pull metrics from either "minimal" shape or dataset/webhook nested shapes.
      const steps =
        asNumber(body.steps) ??
        asNumber(body.steps_int) ??
        asNumber(deepFindByKey(body, "accumulated_steps_int")) ??
        asNumber(deepFindByKey(body, "steps_int")) ??
        asNumber(deepFindByKey(body, "steps"));

      const sleepSeconds =
        asNumber(body.sleep_duration_seconds_int) ??
        asNumber(deepFindByKey(body, "sleep_duration_seconds_int")) ??
        asNumber(body.sleepDurationSeconds) ??
        asNumber(deepFindByKey(body, "sleepDurationSeconds"));
      const sleepMinutes = sleepSeconds != null ? Math.round(sleepSeconds / 60) : null;

      const hrvMs =
        asNumber(body.hrv_ms) ??
        asNumber(body.hrv) ??
        asNumber(deepFindByKey(body, "hrv_sdnn_ms_double")) ??
        asNumber(deepFindByKey(body, "hrv_rmssd_ms_double")) ??
        asNumber(deepFindByKey(body, "hrvAvgSdnnNumber")) ??
        asNumber(deepFindByKey(body, "hrvAvgRmssdNumber"));

      const restingHr =
        asNumber(body.resting_hr) ??
        asNumber(deepFindByKey(body, "hr_resting_bpm_int")) ??
        asNumber(deepFindByKey(body, "hrRestingBPM")) ??
        asNumber(deepFindByKey(body, "restingHeartRate"));

      const avgHr =
        asNumber(deepFindByKey(body, "hr_avg_bpm_int")) ??
        asNumber(deepFindByKey(body, "hrAvgBPM")) ??
        asNumber(deepFindByKey(body, "averageHeartRate"));

      const caloriesActive =
        asNumber(deepFindByKey(body, "active_calories_kcal_double")) ??
        asNumber(deepFindByKey(body, "activeCalories")) ??
        asNumber(deepFindByKey(body, "active_energy_burned_kcal_double"));

      const caloriesTotal =
        asNumber(deepFindByKey(body, "total_calories_kcal_double")) ??
        asNumber(deepFindByKey(body, "totalCalories")) ??
        asNumber(deepFindByKey(body, "dietary_energy_consumed_kcal_double"));

      const scoreRaw = asNumber(body.score ?? body.rookScore ?? deepFindByKey(body, "score"));
      const scoreNormalized = asNumber(body.normalizedScore ?? deepFindByKey(body, "normalizedScore"));

        // Upsert into wearable_daily_metrics keyed on (rook_user_id, metric_date, source)
        // updated_at is automatically handled by database trigger
      const anyMetric =
        steps != null ||
        sleepMinutes != null ||
        hrvMs != null ||
        restingHr != null ||
        avgHr != null ||
        caloriesActive != null ||
        caloriesTotal != null ||
        scoreRaw != null ||
        scoreNormalized != null;

      const uuidRegex =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      const userId = rookUserId && uuidRegex.test(rookUserId) ? rookUserId : null;

      if (rookUserId && metricDate && anyMetric) {
        // IMPORTANT: do not overwrite existing non-null values with nulls.
        // We only include fields that we actually extracted (not null/undefined).
        const record: Record<string, unknown> = {
          rook_user_id: rookUserId,
          source,
          metric_date: metricDate,
          raw_payload: payload,
          ...(userId ? { user_id: userId } : {}),
          ...(steps != null ? { steps: Math.round(steps) } : {}),
          ...(sleepMinutes != null ? { sleep_minutes: sleepMinutes } : {}),
          ...(hrvMs != null ? { hrv_ms: hrvMs } : {}),
          ...(restingHr != null ? { resting_hr: restingHr } : {}),
          ...(avgHr != null ? { avg_hr: avgHr } : {}),
          ...(caloriesActive != null ? { calories_active: caloriesActive } : {}),
          ...(caloriesTotal != null ? { calories_total: caloriesTotal } : {}),
          ...(scoreRaw != null ? { score_raw: scoreRaw } : {}),
          ...(scoreNormalized != null ? { score_normalized: scoreNormalized } : {}),
        };

        const { error: upsertError } = await supabase
          .from("wearable_daily_metrics")
          .upsert(record, {
            onConflict: "rook_user_id,metric_date,source",
          });

        if (upsertError) {
          console.error("🔴 MIYA_WEARABLE_UPSERT_ERROR", {
            error: upsertError.message,
            code: upsertError.code,
            details: upsertError.details,
            hint: upsertError.hint,
            record,
          });
        } else {
          console.log("🟢 MIYA_WEARABLE_UPSERT_SUCCESS", {
            rookUserId,
            metricDate,
            source,
            hasSteps: steps != null,
            hasSleep: sleepMinutes != null,
            stepsValue: steps,
            sleepMinutesValue: sleepMinutes,
            restingHrValue: restingHr,
          });

          // ===============================
          // SERVER-SIDE SCORING (rolling 7d)
          // ===============================
          // Only compute if we can map to a Miya user UUID (we treat rook_user_id as UUID).
          if (!userId) {
            console.log("🟡 MIYA_SCORE_SKIP_NO_USER_ID", { rookUserId, metricDate });
          } else {
            try {
              // Load DOB (required to compute AgeGroup).
              const { data: profile, error: profileErr } = await supabase
                .from("user_profiles")
                .select("date_of_birth")
                .eq("user_id", userId)
                .maybeSingle();

              if (profileErr) {
                console.error("🔴 MIYA_SCORE_PROFILE_FETCH_ERROR", {
                  userId,
                  error: profileErr.message,
                });
              } else if (!profile?.date_of_birth) {
                console.log("🟡 MIYA_SCORE_SKIP_NO_DOB", { userId });
              } else {
                const age = computeAgeYears(profile.date_of_birth);
                if (age == null) {
                  console.log("🟡 MIYA_SCORE_SKIP_BAD_DOB", { userId, dob: profile.date_of_birth });
                } else {
                  const endStart = metricDate;
                  const endMax = clampEndDateToToday(addDaysUTC(metricDate, 6) ?? metricDate);

                  const res = await recomputeRolling7dScoresForUser(supabase, {
                    userId,
                    age,
                    startEndDate: endStart,
                    endEndDate: endMax,
                  });

                  console.log("🔵 MIYA_SCORE_RECOMPUTE_RESULT", {
                    userId,
                    attempted: res.attemptedEndDates.length,
                    computed: res.computedEndDates.length,
                    skipped: res.skippedEndDates.length,
                    latest: res.latestComputed?.endDate ?? null,
                  });

                  if (res.latestComputed) {
                    const snap = res.latestComputed.snapshot;
                    const sleep = snap.pillarScores.find((p) => p.pillar === "sleep")?.score ?? 0;
                    const movement = snap.pillarScores.find((p) => p.pillar === "movement")?.score ?? 0;
                    const stress = snap.pillarScores.find((p) => p.pillar === "stress")?.score ?? 0;

                    const snapshotPayload: Record<string, unknown> = {
                      vitality_score_current: snap.totalScore,
                      vitality_score_source: "wearable",
                      vitality_score_updated_at: new Date().toISOString(),
                      vitality_sleep_pillar_score: sleep,
                      vitality_movement_pillar_score: movement,
                      vitality_stress_pillar_score: stress,
                      vitality_schema_version: scoringSchema.schemaVersion,
                    };

                    const { error: upErr } = await supabase.from("user_profiles").update(snapshotPayload).eq("user_id", userId);

                    if (upErr) {
                      console.error("🔴 MIYA_SCORE_PROFILE_UPDATE_ERROR", { userId, error: upErr.message });
                    } else {
                      console.log("🟢 MIYA_SCORE_PROFILE_UPDATE_SUCCESS", {
                        userId,
                        endDate: res.latestComputed.endDate,
                        total: snap.totalScore,
                      });
                    }
                  }
                }
              }
            } catch (scoreErr) {
              console.error("🔴 MIYA_SCORE_UNHANDLED_ERROR", { userId, metricDate, error: String(scoreErr) });
            }

            // ===========================================
            // SERVER-SIDE PATTERN ALERTS (baseline-driven)
            // ===========================================
            // Always evaluate in shadow mode by default (MIYA_PATTERN_SHADOW_MODE=true).
            console.log("🟡 MIYA_PATTERN_EVAL_STARTING", { userId, metricDate });
            try {
              const res = await evaluatePatternsForUser(supabase, { userId, endDate: metricDate });
              console.log("🔵 MIYA_PATTERN_EVAL_RESULT", { userId, metricDate, ...res });
            } catch (patternErr) {
              console.error("🔴 MIYA_PATTERN_EVAL_ERROR", { userId, metricDate, error: String(patternErr), stack: patternErr?.stack });
            }
          }
        }
      } else {
        console.log("🟡 MIYA_WEARABLE_SKIP", {
          hasRookUserId: !!rookUserId,
          hasMetricDate: !!metricDate,
          source,
          dateRaw,
          anyMetric,
          extractedUserId: rookUserId,
          extractedDate: dateRaw,
        });
      }
    } catch (parseError) {
      // Log but don't fail the webhook - we still want to return 200
      console.error("Error parsing metrics from Rook webhook payload", parseError);
    }

    return jsonResponse({ ok: true });
  }

  return jsonResponse({ ok: false, message: "Method not allowed" });
});

