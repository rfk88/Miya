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

    // Attempt to parse and upsert metrics into wearable_daily_metrics or exercise_sessions
    try {
      const body = payload as any;
      const dataStructure = body.data_structure ?? body.dataStructure ?? "unknown";
      const dataStructureLower = String(dataStructure).toLowerCase();
      const isSleepSummary = dataStructureLower.includes("sleep");
      console.log("🔵 MIYA_PARSING_START", { dataStructure, userId: body.user_id ?? body.userId });

      // ===================================================================
      // HANDLE ACTIVITY_EVENT WEBHOOKS (Exercise/Workout Sessions)
      // ===================================================================
      if (dataStructure === "activity_event") {
        console.log("🏃 MIYA_ACTIVITY_EVENT_DETECTED");
        
        const rookUserId = asString(
          body.userId ??
            body.user_id ??
            deepFindByKey(body, "user_id_string") ??
            deepFindByKey(body, "user_id")
        );
        
        // Extract activity events array
        const activityEvents = deepFindByKey(body, "activity_event");
        const eventsArray = Array.isArray(activityEvents) ? activityEvents : [activityEvents].filter(Boolean);
        
        if (!rookUserId || eventsArray.length === 0) {
          console.log("🟡 MIYA_ACTIVITY_EVENT_SKIP", { rookUserId, eventsCount: eventsArray.length });
          return jsonResponse({ ok: true, message: "activity_event received but incomplete" });
        }
        
        // Map rookUserId to Miya user_id
        const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
        let userId: string | null = null;
        
        if (uuidRegex.test(rookUserId)) {
          userId = rookUserId;
        } else {
          const { data: mapping } = await supabase
            .from("rook_user_mapping")
            .select("user_id")
            .eq("rook_user_id", rookUserId)
            .maybeSingle();
          userId = mapping?.user_id ?? null;
        }
        
        if (!userId) {
          console.log("🔴 MIYA_ACTIVITY_EVENT_NO_USER_MAPPING", { rookUserId });
          return jsonResponse({ ok: true, message: "activity_event received but user not mapped" });
        }
        
        // Process each activity event
        const exerciseRecords = [];
        
        for (const event of eventsArray) {
          const metadata = event.metadata ?? {};
          const activity = event.activity ?? {};
          const calories = event.calories ?? {};
          const distance = event.distance ?? {};
          const heartRate = event.heart_rate ?? {};
          
          // Extract core activity data
          const activityStartTime = asString(activity.activity_start_datetime_string);
          const activityEndTime = asString(activity.activity_end_datetime_string);
          const activityTypeName = asString(activity.activity_type_name_string);
          
          if (!activityStartTime || !activityEndTime || !activityTypeName) {
            console.log("🟡 MIYA_ACTIVITY_EVENT_INCOMPLETE", { 
              start: activityStartTime, 
              end: activityEndTime, 
              type: activityTypeName 
            });
            continue;
          }
          
          // Determine metric_date from start time
          const metricDate = toISODateYYYYMMDD(activityStartTime);
          if (!metricDate) {
            console.log("🟡 MIYA_ACTIVITY_EVENT_INVALID_DATE", { activityStartTime });
            continue;
          }
          
          // Extract source
          const sourcesArr = metadata.sources_of_data_array ?? [];
          const sourceRaw = Array.isArray(sourcesArr) ? asString(sourcesArr[0]) : null;
          const source = normalizeSource(sourceRaw);
          
          // Build exercise session record
          const exerciseRecord: Record<string, unknown> = {
            user_id: userId,
            rook_user_id: rookUserId,
            metric_date: metricDate,
            activity_start_time: activityStartTime,
            activity_end_time: activityEndTime,
            activity_type_name: activityTypeName,
            activity_duration_seconds: asNumber(activity.activity_duration_seconds_int),
            active_seconds: asNumber(activity.active_seconds_int),
            rest_seconds: asNumber(activity.rest_seconds_int),
            low_intensity_seconds: asNumber(activity.low_intensity_seconds_int),
            moderate_intensity_seconds: asNumber(activity.moderate_intensity_seconds_int),
            vigorous_intensity_seconds: asNumber(activity.vigorous_intensity_seconds_int),
            inactivity_seconds: asNumber(activity.inactivity_seconds_int),
            calories_burned_kcal: asNumber(calories.calories_expenditure_kcal_float),
            calories_active_kcal: asNumber(calories.calories_net_active_kcal_float),
            distance_meters: asNumber(distance.traveled_distance_meters_float) ?? asNumber(distance.walked_distance_meters_float),
            steps: asNumber(distance.steps_int),
            hr_avg_bpm: asNumber(heartRate.hr_avg_bpm_int) ?? asNumber(deepFindByKey(event, "hr_avg_bpm_int")),
            hr_max_bpm: asNumber(heartRate.hr_max_bpm_int) ?? asNumber(deepFindByKey(event, "hr_max_bpm_int")),
            hr_min_bpm: asNumber(heartRate.hr_min_bpm_int) ?? asNumber(deepFindByKey(event, "hr_min_bpm_int")),
            source_of_data: source,
            was_under_physical_activity: metadata.was_the_user_under_physical_activity_bool ?? true,
            raw_webhook_data: event,
          };
          
          exerciseRecords.push(exerciseRecord);
        }
        
        // Upsert exercise sessions
        if (exerciseRecords.length > 0) {
          const { error: insertError } = await supabase
            .from("exercise_sessions")
            .upsert(exerciseRecords, {
              onConflict: "user_id,activity_start_time,activity_end_time",
              ignoreDuplicates: false,
            });
          
          if (insertError) {
            console.error("🔴 MIYA_EXERCISE_SESSION_INSERT_ERROR", insertError);
            return jsonResponse({ ok: false, error: insertError.message });
          }
          
          console.log("🟢 MIYA_EXERCISE_SESSIONS_STORED", { 
            userId, 
            count: exerciseRecords.length,
            types: exerciseRecords.map(r => r.activity_type_name) 
          });
        }
        
        return jsonResponse({ 
          ok: true, 
          message: "activity_event processed", 
          exercisesStored: exerciseRecords.length 
        });
      }
      
      // ===================================================================
      // HANDLE DAILY SUMMARY WEBHOOKS (Sleep, Physical, etc.)
      // ===================================================================

      // ROOK payloads are often nested; extract key fields defensively.
      const rookUserId = asString(
        body.userId ??
          body.user_id ??
          body.clientUserId ??
          body.client_user_id ??
          body.client_user_id_string ??
          deepFindByKey(body, "client_user_id") ??
          deepFindByKey(body, "clientUserId") ??
          deepFindByKey(body, "client_user_id_string") ??
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
          deepFindByKey(body, "date_string") ??
          deepFindByKey(body, "dateString") ??
          deepFindByKey(body, "summary_date") ??
          deepFindByKey(body, "datetime_string") ??
          deepFindByKey(body, "datetime") ??
          deepFindByKey(body, "date_time")
      );
      const metricDate = toISODateYYYYMMDD(dateRaw);

      // ===================================================================
      // EXTRACT METRICS FROM ROOK PAYLOADS (Apple Health, Oura, Whoop, etc.)
      // ===================================================================
      
      // MOVEMENT METRICS
      // ----------------
      const steps =
        asNumber(body.steps) ??
        asNumber(body.steps_int) ??
        asNumber(deepFindByKey(body, "accumulated_steps_int")) ??
        asNumber(deepFindByKey(body, "steps_int")) ??
        asNumber(deepFindByKey(body, "steps"));
      
      const activeSteps =
        asNumber(deepFindByKey(body, "active_steps_int")) ??
        asNumber(deepFindByKey(body, "activeSteps"));
      
      // CRITICAL: active_seconds_int is the movement minutes data!
      const activeSeconds =
        asNumber(deepFindByKey(body, "active_seconds_int")) ??
        asNumber(deepFindByKey(body, "activeSeconds")) ??
        asNumber(deepFindByKey(body, "activity_duration_seconds_int"));
      const movementMinutes = activeSeconds != null ? Math.round(activeSeconds / 60) : null;
      
      const floorsClimbed =
        asNumber(deepFindByKey(body, "floors_climbed_float")) ??
        asNumber(deepFindByKey(body, "floorsClimbed"));
      
      const distanceMeters =
        asNumber(deepFindByKey(body, "traveled_distance_meters_float")) ??
        asNumber(deepFindByKey(body, "walked_distance_meters_float")) ??
        asNumber(deepFindByKey(body, "traveledDistance"));

      // SLEEP METRICS
      // -------------
      const sleepSeconds =
        asNumber(body.sleep_duration_seconds_int) ??
        asNumber(deepFindByKey(body, "sleep_duration_seconds_int")) ??
        asNumber(body.sleepDurationSeconds) ??
        asNumber(deepFindByKey(body, "sleepDurationSeconds"));
      const sleepMinutes = sleepSeconds != null ? Math.round(sleepSeconds / 60) : null;
      
      const deepSleepSeconds =
        asNumber(deepFindByKey(body, "deep_sleep_duration_seconds_int")) ??
        asNumber(deepFindByKey(body, "deepSleepDuration"));
      const deepSleepMinutes = deepSleepSeconds != null ? Math.round(deepSleepSeconds / 60) : null;
      
      const remSleepSeconds =
        asNumber(deepFindByKey(body, "rem_sleep_duration_seconds_int")) ??
        asNumber(deepFindByKey(body, "remSleepDuration"));
      const remSleepMinutes = remSleepSeconds != null ? Math.round(remSleepSeconds / 60) : null;
      
      const lightSleepSeconds =
        asNumber(deepFindByKey(body, "light_sleep_duration_seconds_int")) ??
        asNumber(deepFindByKey(body, "lightSleepDuration"));
      const lightSleepMinutes = lightSleepSeconds != null ? Math.round(lightSleepSeconds / 60) : null;
      
      const awakeSeconds =
        asNumber(deepFindByKey(body, "time_awake_during_sleep_seconds_int")) ??
        asNumber(deepFindByKey(body, "awakeTime"));
      const awakeMinutes = awakeSeconds != null ? Math.round(awakeSeconds / 60) : null;
      
      const timeInBedSeconds =
        asNumber(deepFindByKey(body, "time_in_bed_seconds_int")) ??
        asNumber(deepFindByKey(body, "timeInBed"));
      
      // Calculate sleep efficiency: (sleep_duration / time_in_bed) * 100
      const sleepEfficiencyPct =
        sleepSeconds != null && timeInBedSeconds != null && timeInBedSeconds > 0
          ? Math.round((sleepSeconds / timeInBedSeconds) * 100)
          : null;
      
      const timeToFallAsleepSeconds =
        asNumber(deepFindByKey(body, "time_to_fall_asleep_seconds_int")) ??
        asNumber(deepFindByKey(body, "sleepLatency"));
      const timeToFallAsleepMinutes = timeToFallAsleepSeconds != null ? Math.round(timeToFallAsleepSeconds / 60) : null;

      // HEART METRICS
      // -------------
      const hrvMs =
        isSleepSummary
          ? (asNumber(body.hrv_ms) ??
              asNumber(body.hrv) ??
              asNumber(deepFindByKey(body, "hrv_avg_sdnn_float")) ??
              asNumber(deepFindByKey(body, "hrv_sdnn_ms_double")) ??
              asNumber(deepFindByKey(body, "hrvAvgSdnnNumber")))
          : null;
      
      const hrvRmssdMs =
        isSleepSummary
          ? (asNumber(deepFindByKey(body, "hrv_rmssd_ms_double")) ??
              asNumber(deepFindByKey(body, "hrv_avg_rmssd_float")) ??
              asNumber(deepFindByKey(body, "hrvAvgRmssdNumber")))
          : null;

      const restingHr =
        isSleepSummary
          ? (asNumber(body.resting_hr) ??
              asNumber(deepFindByKey(body, "hr_resting_bpm_int")) ??
              asNumber(deepFindByKey(body, "hrRestingBPM")) ??
              asNumber(deepFindByKey(body, "restingHeartRate")))
          : null;

      const avgHr =
        asNumber(deepFindByKey(body, "hr_avg_bpm_int")) ??
        asNumber(deepFindByKey(body, "hrAvgBPM")) ??
        asNumber(deepFindByKey(body, "averageHeartRate"));

      // RESPIRATORY METRICS
      // -------------------
      const breathsAvgPerMin =
        asNumber(deepFindByKey(body, "breaths_avg_per_min_int")) ??
        asNumber(deepFindByKey(body, "breathingRate"));
      
      const spo2AvgPct =
        asNumber(deepFindByKey(body, "saturation_avg_percentage_int")) ??
        asNumber(deepFindByKey(body, "bloodOxygenSaturation"));

      // CALORIE METRICS
      // ---------------
      // Prefer net active calories (more accurate for movement)
      const caloriesActive =
        asNumber(deepFindByKey(body, "calories_net_active_kcal_float")) ??
        asNumber(deepFindByKey(body, "active_calories_kcal_double")) ??
        asNumber(deepFindByKey(body, "activeCalories")) ??
        asNumber(deepFindByKey(body, "active_energy_burned_kcal_double"));

      const caloriesTotal =
        asNumber(deepFindByKey(body, "total_calories_kcal_double")) ??
        asNumber(deepFindByKey(body, "totalCalories")) ??
        asNumber(deepFindByKey(body, "calories_basal_metabolic_rate_kcal_float")) ??
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
        movementMinutes != null ||
        deepSleepMinutes != null ||
        remSleepMinutes != null ||
        scoreRaw != null ||
        scoreNormalized != null;

      const uuidRegex =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      
      // Determine Miya user UUID:
      // 1. If rookUserId is already a UUID, use it directly (SDK set client_user_id correctly)
      // 2. If not, look up in rook_user_mapping table
      let userId: string | null = null;
      let mappingSource: string | null = null;
      
      if (rookUserId && uuidRegex.test(rookUserId)) {
        userId = rookUserId;
        mappingSource = "direct_uuid";
        console.log("🟢 MIYA_ROOK_USER_ID_DIRECT", { rookUserId, userId });
      } else if (rookUserId) {
        // Not a UUID, try to map it
        const { data: mapping, error: mappingErr } = await supabase
          .from("rook_user_mapping")
          .select("user_id")
          .eq("rook_user_id", rookUserId)
          .maybeSingle();
        
        if (mappingErr) {
          console.error("🔴 MIYA_MAPPING_LOOKUP_ERROR", { rookUserId, error: mappingErr.message });
        } else if (mapping?.user_id) {
          userId = mapping.user_id;
          mappingSource = "mapping_table";
          console.log("🟢 MIYA_ROOK_USER_ID_MAPPED", { rookUserId, userId, source: mappingSource });
        } else {
          console.log("🟡 MIYA_ROOK_USER_ID_UNMAPPED", { rookUserId, hint: "Need to add mapping for this Rook user ID" });
        }
      }

      if (rookUserId && metricDate && anyMetric) {
        // IMPORTANT: do not overwrite existing non-null values with nulls.
        // We only include fields that we actually extracted (not null/undefined).
        const record: Record<string, unknown> = {
          rook_user_id: rookUserId,
          source,
          metric_date: metricDate,
          raw_payload: payload,
          ...(userId ? { user_id: userId } : {}),
          
          // Movement metrics
          ...(steps != null ? { steps: Math.round(steps) } : {}),
          ...(activeSteps != null ? { active_steps: Math.round(activeSteps) } : {}),
          ...(movementMinutes != null ? { movement_minutes: movementMinutes } : {}),
          ...(floorsClimbed != null ? { floors_climbed: floorsClimbed } : {}),
          ...(distanceMeters != null ? { distance_meters: distanceMeters } : {}),
          
          // Sleep metrics
          ...(sleepMinutes != null ? { sleep_minutes: sleepMinutes } : {}),
          ...(deepSleepMinutes != null ? { deep_sleep_minutes: deepSleepMinutes } : {}),
          ...(remSleepMinutes != null ? { rem_sleep_minutes: remSleepMinutes } : {}),
          ...(lightSleepMinutes != null ? { light_sleep_minutes: lightSleepMinutes } : {}),
          ...(awakeMinutes != null ? { awake_minutes: awakeMinutes } : {}),
          ...(sleepEfficiencyPct != null ? { sleep_efficiency_pct: sleepEfficiencyPct } : {}),
          ...(timeToFallAsleepMinutes != null ? { time_to_fall_asleep_minutes: timeToFallAsleepMinutes } : {}),
          
          // Heart metrics
          ...(hrvMs != null ? { hrv_ms: hrvMs } : {}),
          ...(hrvRmssdMs != null ? { hrv_rmssd_ms: hrvRmssdMs } : {}),
          ...(restingHr != null ? { resting_hr: restingHr } : {}),
          ...(avgHr != null ? { avg_hr: avgHr } : {}),
          
          // Respiratory metrics
          ...(breathsAvgPerMin != null ? { breaths_avg_per_min: breathsAvgPerMin } : {}),
          ...(spo2AvgPct != null ? { spo2_avg_pct: spo2AvgPct } : {}),
          
          // Calorie metrics
          ...(caloriesActive != null ? { calories_active: caloriesActive } : {}),
          ...(caloriesTotal != null ? { calories_total: caloriesTotal } : {}),
          
          // Rook scores (if available)
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
            hasMovementMinutes: movementMinutes != null,
            hasSleepQuality: deepSleepMinutes != null || remSleepMinutes != null,
            stepsValue: steps,
            sleepMinutesValue: sleepMinutes,
            movementMinutesValue: movementMinutes,
            restingHrValue: restingHr,
            sleepEfficiencyValue: sleepEfficiencyPct,
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

