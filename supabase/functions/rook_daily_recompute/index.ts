import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { scoringSchema } from "../rook/scoring/schema.ts";
import { recomputeRolling7dScoresForUser } from "../rook/scoring/recompute.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST,OPTIONS,GET",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-miya-admin-secret",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceRoleKey =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY")!;
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function toYYYYMMDD(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function addDaysUTC(d: Date, delta: number): Date {
  const out = new Date(d.getTime());
  out.setUTCDate(out.getUTCDate() + delta);
  return out;
}

function computeAgeYears(dobISO: string): number | null {
  const dob = new Date(dobISO);
  if (Number.isNaN(dob.getTime())) return null;
  const now = new Date();
  let age = now.getUTCFullYear() - dob.getUTCFullYear();
  const m = now.getUTCMonth() - dob.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < dob.getUTCDate())) age -= 1;
  return age >= 0 ? age : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method === "GET") {
    return jsonResponse({ ok: true, message: "rook_daily_recompute alive" });
  }

  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
  }

  const expected = Deno.env.get("MIYA_ADMIN_SECRET") ?? "";
  const provided = req.headers.get("x-miya-admin-secret") ?? "";
  if (!expected || provided !== expected) {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }

  let body: any = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const daysBack = Number.isFinite(body.daysBack) ? Math.max(1, Math.floor(body.daysBack)) : 2;
  const maxUsers = Number.isFinite(body.maxUsers) ? Math.max(1, Math.floor(body.maxUsers)) : 500;

  const today = new Date();
  const endDate = toYYYYMMDD(today);
  const startDate = toYYYYMMDD(addDaysUTC(today, -(daysBack - 1)));

  // Fetch users who have wearable metrics in the recent window.
  const { data: metricRows, error: metricsErr } = await supabase
    .from("wearable_daily_metrics")
    .select("user_id")
    .not("user_id", "is", null)
    .gte("metric_date", startDate)
    .lte("metric_date", endDate)
    .limit(5000);

  if (metricsErr) {
    return jsonResponse({ ok: false, error: `Failed to fetch metrics: ${metricsErr.message}` }, 500);
  }

  const userIds = Array.from(
    new Set((metricRows ?? []).map((r: any) => r.user_id).filter(Boolean)),
  ).slice(0, maxUsers);

  if (!userIds.length) {
    return jsonResponse({ ok: true, message: "No users with recent metrics", startDate, endDate });
  }

  const { data: profiles, error: profileErr } = await supabase
    .from("user_profiles")
    .select("user_id,date_of_birth")
    .in("user_id", userIds);

  if (profileErr) {
    return jsonResponse({ ok: false, error: `Failed to fetch profiles: ${profileErr.message}` }, 500);
  }

  const dobByUser = new Map(
    (profiles ?? []).map((p: any) => [p.user_id as string, p.date_of_birth as string | null]),
  );

  const results: Array<{ userId: string; ok: boolean; error?: string }> = [];

  for (const userId of userIds) {
    const dob = dobByUser.get(userId);
    if (!dob) {
      results.push({ userId, ok: false, error: "missing_date_of_birth" });
      continue;
    }
    const age = computeAgeYears(dob);
    if (age == null) {
      results.push({ userId, ok: false, error: "invalid_date_of_birth" });
      continue;
    }

    try {
      const result = await recomputeRolling7dScoresForUser(supabase, {
        userId,
        age,
        startEndDate: startDate,
        endEndDate: endDate,
      });

      if (result.latestComputed) {
        const snap = result.latestComputed.snapshot;
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
          results.push({ userId, ok: false, error: `snapshot_update_failed:${upErr.message}` });
          continue;
        }
      }

      results.push({ userId, ok: true });
    } catch (err) {
      const message = err instanceof Error ? err.message : "unknown_error";
      results.push({ userId, ok: false, error: message });
    }
  }

  return jsonResponse({
    ok: true,
    startDate,
    endDate,
    usersConsidered: userIds.length,
    successes: results.filter((r) => r.ok).length,
    failures: results.filter((r) => !r.ok).length,
    results,
  });
});
