import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { scoringSchema } from "../rook/scoring/schema.ts";
import { recomputeRolling7dScoresForUser } from "../rook/scoring/recompute.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
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

  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
  }

  // Simple admin guard (service role key already grants full access; this prevents accidental exposure).
  const expected = Deno.env.get("MIYA_ADMIN_SECRET") ?? "";
  const provided = req.headers.get("x-miya-admin-secret") ?? "";
  if (!expected || provided !== expected) {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400);
  }

  const userId = typeof body.userId === "string" ? body.userId : null;
  const startDate = typeof body.startDate === "string" ? body.startDate : null;
  const endDate = typeof body.endDate === "string" ? body.endDate : null;
  if (!userId || !startDate || !endDate) {
    return jsonResponse({ ok: false, error: "Missing userId/startDate/endDate" }, 400);
  }

  const { data: profile, error: profileErr } = await supabase
    .from("user_profiles")
    .select("date_of_birth")
    .eq("user_id", userId)
    .maybeSingle();

  if (profileErr) {
    return jsonResponse({ ok: false, error: `Failed to fetch user profile: ${profileErr.message}` }, 500);
  }
  if (!profile?.date_of_birth) {
    return jsonResponse({ ok: false, error: "User profile missing date_of_birth" }, 400);
  }

  const age = computeAgeYears(profile.date_of_birth);
  if (age == null) {
    return jsonResponse({ ok: false, error: "Invalid date_of_birth" }, 400);
  }

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
      return jsonResponse({ ok: false, error: `Failed to update user snapshot: ${upErr.message}`, result }, 500);
    }
  }

  return jsonResponse({ ok: true, schemaVersion: scoringSchema.schemaVersion, result });
});


