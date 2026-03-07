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

function addDaysUTC(d: Date, delta: number): Date {
  const out = new Date(d.getTime());
  out.setUTCDate(out.getUTCDate() + delta);
  return out;
}

type ChallengeRow = {
  id: string;
  member_user_id: string;
  admin_user_id: string;
  pillar: "sleep" | "movement" | "stress" | string;
  status: string;
  start_date: string | null;
  end_date: string | null;
  days_succeeded: number;
  days_evaluated: number;
  required_success_days: number;
  last_evaluated_at: string | null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method === "GET") {
    return jsonResponse({ ok: true, message: "challenges_daily_evaluate alive" });
  }

  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
  }

  // Strict admin secret: reject when not configured (missing, non-string, or empty/whitespace).
  const raw = Deno.env.get("MIYA_ADMIN_SECRET");
  if (typeof raw !== "string" || raw.trim() === "") {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }
  const expected = raw.trim();
  const provided = req.headers.get("x-miya-admin-secret") ?? "";
  if (provided !== expected) {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }

  let body: any = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const maxChallenges = Number.isFinite(body.maxChallenges)
    ? Math.max(1, Math.floor(body.maxChallenges))
    : 500;

  const today = new Date();
  const todayStr = toYYYYMMDD(today);

  // Fetch active challenges.
  const { data: challenges, error: challengesErr } = await supabase
    .from("challenges")
    .select(
      "id, member_user_id, admin_user_id, pillar, status, start_date, end_date, days_succeeded, days_evaluated, required_success_days, last_evaluated_at",
    )
    .eq("status", "active")
    .lte("start_date", todayStr)
    .limit(maxChallenges);

  if (challengesErr) {
    return jsonResponse(
      { ok: false, error: `Failed to fetch active challenges: ${challengesErr.message}` },
      500,
    );
  }

  if (!challenges || challenges.length === 0) {
    return jsonResponse({ ok: true, message: "No active challenges to evaluate", today: todayStr });
  }

  const results: Array<{ challengeId: string; updated: boolean; status: string }> = [];

  for (const row of challenges as ChallengeRow[]) {
    try {
      // Avoid double-evaluating the same day if the job is retried.
      if (row.last_evaluated_at && row.last_evaluated_at.slice(0, 10) === todayStr) {
        results.push({ challengeId: row.id, updated: false, status: row.status });
        continue;
      }

      const endDate = row.end_date ?? toYYYYMMDD(addDaysUTC(new Date(row.start_date ?? todayStr), 6));

      // Fetch today's vitality pillar score for the member.
      const { data: vitalityRows, error: vitalityErr } = await supabase
        .from("vitality_scores")
        .select(
          "vitality_sleep_pillar_score, vitality_movement_pillar_score, vitality_stress_pillar_score",
        )
        .eq("user_id", row.member_user_id)
        .eq("score_date", todayStr)
        .limit(1);

      if (vitalityErr) {
        console.error("Error fetching vitality_scores", vitalityErr);
      }

      let daysSucceeded = row.days_succeeded;
      let daysEvaluated = row.days_evaluated;

      let evaluatedToday = false;

      if (vitalityRows && vitalityRows.length > 0) {
        const vs = vitalityRows[0] as {
          vitality_sleep_pillar_score: number | null;
          vitality_movement_pillar_score: number | null;
          vitality_stress_pillar_score: number | null;
        };

        let pillarScore: number | null = null;
        switch (row.pillar) {
          case "sleep":
            pillarScore = vs.vitality_sleep_pillar_score ?? null;
            break;
          case "movement":
            pillarScore = vs.vitality_movement_pillar_score ?? null;
            break;
          case "stress":
            pillarScore = vs.vitality_stress_pillar_score ?? null;
            break;
          default:
            pillarScore = null;
        }

        if (pillarScore !== null) {
          // IMPORTANT: This threshold should mirror the \"not attention\" logic
          // used in the trend engine. For now we treat scores >= 50 (\"Stable\")
          // as a successful day (see pillar status mapping in the iOS app).
          const isSuccess = pillarScore >= 50;
          daysEvaluated += 1;
          evaluatedToday = true;
          if (isSuccess) {
            daysSucceeded += 1;
          }
        }
      }

      // Determine if the challenge window has finished.
      const windowDone =
        todayStr > endDate || daysEvaluated >= 7;

      let newStatus = row.status;
      if (windowDone) {
        if (daysSucceeded >= row.required_success_days) {
          newStatus = "completed_success";
        } else {
          newStatus = "completed_failed";
        }
      }

      const { error: updateErr } = await supabase
        .from("challenges")
        .update({
          days_succeeded: daysSucceeded,
          days_evaluated: daysEvaluated,
          last_evaluated_at: todayStr,
          status: newStatus,
          updated_at: new Date().toISOString(),
        })
        .eq("id", row.id);

      if (updateErr) {
        console.error("Error updating challenge", row.id, updateErr.message);
        results.push({ challengeId: row.id, updated: false, status: row.status });
        continue;
      }

      // Enqueue daily progress notifications only if we actually evaluated today.
      if (evaluatedToday) {
        const remainingDays = Math.max(
          0,
          Math.ceil(
            (Date.parse(endDate) - Date.parse(todayStr)) / (24 * 60 * 60 * 1000),
          ),
        );
        const successesNeeded = Math.max(
          0,
          row.required_success_days - daysSucceeded,
        );

        const memberPayload = {
          kind: "challenge_daily_member",
          challenge_id: row.id,
          pillar: row.pillar,
          status: newStatus,
          days_succeeded: daysSucceeded,
          days_evaluated: daysEvaluated,
          remaining_days: remainingDays,
          successes_needed: successesNeeded,
        };

        const adminPayload = {
          kind: "challenge_daily_admin",
          challenge_id: row.id,
          member_user_id: row.member_user_id,
          pillar: row.pillar,
          status: newStatus,
          days_succeeded: daysSucceeded,
          days_evaluated: daysEvaluated,
        };

        const rowsToInsert: any[] = [
          {
            recipient_user_id: row.member_user_id,
            member_user_id: row.member_user_id,
            alert_state_id: null,
            channel: "push",
            payload: memberPayload,
            status: "pending",
          },
          {
            recipient_user_id: row.admin_user_id,
            member_user_id: row.member_user_id,
            alert_state_id: null,
            channel: "push",
            payload: adminPayload,
            status: "pending",
          },
        ];

        const { error: qErr } = await supabase.from("notification_queue").insert(rowsToInsert);
        if (qErr) {
          console.error("Error enqueuing challenge daily notifications", row.id, qErr.message);
        }
      }

      // Enqueue completion notifications when status transitions.
      if (row.status === "active" && (newStatus === "completed_success" || newStatus === "completed_failed")) {
        const memberCompletionPayload = {
          kind: "challenge_completed_member",
          challenge_id: row.id,
          pillar: row.pillar,
          status: newStatus,
          days_succeeded: daysSucceeded,
          days_evaluated: daysEvaluated,
        };

        const adminCompletionPayload = {
          kind: "challenge_completed_admin",
          challenge_id: row.id,
          member_user_id: row.member_user_id,
          pillar: row.pillar,
          status: newStatus,
          days_succeeded: daysSucceeded,
          days_evaluated: daysEvaluated,
        };

        const completionRows: any[] = [
          {
            recipient_user_id: row.member_user_id,
            member_user_id: row.member_user_id,
            alert_state_id: null,
            channel: "push",
            payload: memberCompletionPayload,
            status: "pending",
          },
          {
            recipient_user_id: row.admin_user_id,
            member_user_id: row.member_user_id,
            alert_state_id: null,
            channel: "push",
            payload: adminCompletionPayload,
            status: "pending",
          },
        ];

        const { error: completionErr } = await supabase.from("notification_queue").insert(completionRows);
        if (completionErr) {
          console.error("Error enqueuing challenge completion notifications", row.id, completionErr.message);
        }
      }

      results.push({ challengeId: row.id, updated: true, status: newStatus });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error("Error evaluating challenge", row.id, message);
      results.push({ challengeId: row.id, updated: false, status: row.status });
    }
  }

  return jsonResponse({
    ok: true,
    today: todayStr,
    evaluated: results.length,
    results,
  });
});

