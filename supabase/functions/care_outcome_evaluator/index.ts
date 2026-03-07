// Care Outcome Evaluator — daily job
// Finds alert_care_state rows in 'monitoring' past follow_up_due_date,
// evaluates outcome (resolved / improving / no improvement), updates state,
// enqueues care_outcome bell when relevant.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

function metricDisplayName(metricType: string): string {
  const m = metricType?.toLowerCase() ?? "";
  if (m.includes("sleep")) return "Sleep";
  if (m.includes("step") || m.includes("movement")) return "Activity";
  if (m.includes("hrv") || m.includes("resting_hr")) return "Recovery";
  return "Health";
}

// Improvement threshold by pillar (recent_value must be this much better than pre_action_recent_value)
function improvementThresholdPercent(metricType: string): number {
  const m = metricType?.toLowerCase() ?? "";
  if (m.includes("sleep")) return 10;
  if (m.includes("step") || m.includes("movement")) return 15;
  if (m.includes("hrv") || m.includes("resting")) return 8;
  return 10;
}

// Next-step message when no improvement (by pillar and level)
function nextStepMessage(
  metricType: string,
  currentLevel: number,
  cycleCount: number,
): string {
  const metric = metricDisplayName(metricType);
  if (cycleCount >= 2) {
    return `This has been going on for a while. A direct conversation may help more than in-app tools.`;
  }
  if (currentLevel <= 7) {
    if (metric === "Sleep") return "No change yet — a direct check-in may help more than a challenge.";
    if (metric === "Activity") return "No change yet — even a short walk commitment, suggested in person, can shift momentum.";
    if (metric === "Recovery") return "Recovery hasn't improved. Rest and reducing commitments matter more than tracking right now.";
  }
  if (currentLevel >= 14) {
    return "This has been going on for 2+ weeks. Consider a more direct conversation or professional support.";
  }
  return `No change yet — consider reaching out directly.`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method === "GET") {
    return jsonResponse({ ok: true, message: "care_outcome_evaluator alive" });
  }

  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
  }

  const raw = Deno.env.get("MIYA_ADMIN_SECRET");
  if (typeof raw !== "string" || raw.trim() === "") {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }
  const provided = req.headers.get("x-miya-admin-secret") ?? "";
  if (provided !== raw.trim()) {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }

  const today = new Date();
  const todayStr = toYYYYMMDD(today);

  // Fetch all alert_care_state in monitoring past follow_up_due_date not yet evaluated
  const { data: careRows, error: careErr } = await supabase
    .from("alert_care_state")
    .select("id, alert_id, acted_by_user_id, pre_action_recent_value, cycle_count")
    .eq("care_state", "monitoring")
    .lte("follow_up_due_date", todayStr)
    .is("outcome_evaluated_at", null)
    .limit(500);

  if (careErr) {
    return jsonResponse(
      { ok: false, error: `Failed to fetch care state: ${careErr.message}` },
      500,
    );
  }

  if (!careRows || careRows.length === 0) {
    return jsonResponse({ ok: true, message: "No monitoring alerts due for evaluation", today: todayStr });
  }

  const results: Array<{ alertId: string; careState: string; notified: boolean }> = [];

  for (const care of careRows) {
    const alertId = care.alert_id as string;
    const actedByUserId = care.acted_by_user_id as string | null;
    const preAction = care.pre_action_recent_value != null ? Number(care.pre_action_recent_value) : null;
    const cycleCount = Number(care.cycle_count ?? 0);

    const { data: pasRow, error: pasErr } = await supabase
      .from("pattern_alert_state")
      .select("id, user_id, metric_type, episode_status, recent_value, current_level")
      .eq("id", alertId)
      .single();

    if (pasErr || !pasRow) {
      results.push({ alertId, careState: "error", notified: false });
      continue;
    }

    const episodeStatus = pasRow.episode_status as string;
    const recentValue = pasRow.recent_value != null ? Number(pasRow.recent_value) : null;
    const currentLevel = Number(pasRow.current_level ?? 7);
    const metricType = (pasRow.metric_type as string) ?? "";

    // Resolved by pattern engine
    if (episodeStatus === "resolved") {
      const { data: fmRow } = await supabase
        .from("family_members")
        .select("first_name")
        .eq("user_id", pasRow.user_id)
        .limit(1)
        .maybeSingle();
      const firstName = (fmRow?.first_name as string) ?? "Their";
      const metric = metricDisplayName(metricType);
      const outcomeMessage = `${firstName}'s ${metric} is back to baseline.`;

      await supabase
        .from("alert_care_state")
        .update({
          care_state: "resolved",
          outcome_message: outcomeMessage,
          outcome_evaluated_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", care.id);

      if (actedByUserId) {
        await supabase.from("notification_queue").insert({
          recipient_user_id: actedByUserId,
          member_user_id: pasRow.user_id,
          alert_state_id: alertId,
          channel: "push",
          payload: { kind: "care_outcome", alert_state_id: alertId, outcome_message: outcomeMessage },
          status: "pending",
        });
      }
      results.push({ alertId, careState: "resolved", notified: !!actedByUserId });
      continue;
    }

    // Check for improvement (recent_value better than pre_action by threshold %)
    let newState: string | null = null;
    let outcomeMessage: string | null = null;

    if (preAction != null && recentValue != null && preAction > 0) {
      const pct = ((recentValue - preAction) / preAction) * 100;
      const threshold = improvementThresholdPercent(metricType);
      if (pct >= threshold) {
        const { data: fmRow } = await supabase
          .from("family_members")
          .select("first_name")
          .eq("user_id", pasRow.user_id)
          .limit(1)
          .maybeSingle();
        const firstName = (fmRow?.first_name as string) ?? "Their";
        const metric = metricDisplayName(metricType);
        newState = "improving";
        outcomeMessage = `${firstName}'s ${metric} has been improving since you acted.`;
      }
    }

    if (newState === "improving") {
      await supabase
        .from("alert_care_state")
        .update({
          care_state: newState,
          outcome_message: outcomeMessage,
          outcome_evaluated_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", care.id);

      if (actedByUserId) {
        await supabase.from("notification_queue").insert({
          recipient_user_id: actedByUserId,
          member_user_id: pasRow.user_id,
          alert_state_id: alertId,
          channel: "push",
          payload: { kind: "care_outcome", alert_state_id: alertId, outcome_message: outcomeMessage },
          status: "pending",
        });
      }
      results.push({ alertId, careState: "improving", notified: !!actedByUserId });
      continue;
    }

    // No improvement
    outcomeMessage = nextStepMessage(metricType, currentLevel, cycleCount);

    if (cycleCount >= 2) {
      await supabase
        .from("alert_care_state")
        .update({
          care_state: "archived",
          outcome_message: outcomeMessage,
          outcome_evaluated_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", care.id);
      results.push({ alertId, careState: "archived", notified: false });
    } else {
      // Resurface: set care_state to null so alert shows as "New" again
      await supabase
        .from("alert_care_state")
        .update({
          care_state: null,
          outcome_message: outcomeMessage,
          outcome_evaluated_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", care.id);
      results.push({ alertId, careState: "resurfaced", notified: false });
    }
  }

  return jsonResponse({
    ok: true,
    today: todayStr,
    evaluated: results.length,
    results,
  });
});
