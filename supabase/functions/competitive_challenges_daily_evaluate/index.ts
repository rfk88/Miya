// Daily evaluator for BIG (competitive) challenges.
// Runs once per day. For every challenge with status='active':
//   1) Upserts daily snapshots (pillar avg OR steps total) for each participant.
//   2) Recomputes the leader (current_leader_user_id, current_leader_metric).
//   3) Sends lead-change / Saturday final-push notifications (max 2/day per recipient,
//      quiet hours enforced by process_notifications).
//   4) On/after Sunday completes the challenge: sets winner_user_id (null on draw),
//      tie_break_used=false, and logs Champions point events for non-draw outcomes.
//   5) Schedules Sunday result notifications.
//
// Scoring rules (mirrored from product plan):
//   - sleep/movement/stress: average of available daily pillar scores (missing days excluded).
//   - steps: sum of daily step counts Mon..Sun (missing days count as 0).
//   - tie-break: the user chooses between best-single-day tie-break OR rematch in the app.
//     The server NEVER auto-applies tie-break; it leaves winner_user_id NULL on draws so the
//     iOS result screen can offer a choice. The "tie_break_used" flag is set by a separate RPC
//     when the user chooses to apply it.

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

// ── Champions reward numbers (mirror BigChallengeChampionsRewards.swift) ──────
const DUEL_WINNER_POINTS = 50;
const BRAWL_PLACEMENT_POINTS: Record<number, number> = { 1: 75, 2: 40, 3: 25, 4: 10, 5: 10, 6: 10 };

// ── Notification cap (mirror BigChallengeNotificationPolicy.swift) ───────────
const MAX_COMPETITIVE_PUSHES_PER_DAY = 2;

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function toYYYYMMDD(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function addDaysUTC(dateStr: string, delta: number): string {
  const d = new Date(`${dateStr}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + delta);
  return toYYYYMMDD(d);
}

function dateRange(startStr: string, inclusiveEndStr: string): string[] {
  const out: string[] = [];
  if (!startStr || !inclusiveEndStr || inclusiveEndStr < startStr) return out;
  let cur = startStr;
  while (cur <= inclusiveEndStr) {
    out.push(cur);
    cur = addDaysUTC(cur, 1);
  }
  return out;
}

type ChallengeRow = {
  id: string;
  family_id: string;
  mode: "head_to_head" | "family_brawl";
  focus: "sleep" | "movement" | "stress" | "steps";
  status: string;
  start_date: string | null;
  end_date: string | null;
  current_leader_user_id: string | null;
  current_leader_metric: number | null;
  last_evaluated_at: string | null;
};

type ParticipantRow = {
  challenge_id: string;
  user_id: string;
  invite_status: string;
};

type SnapshotRow = {
  challenge_id: string;
  user_id: string;
  local_date: string;
  pillar_score: number | null;
  steps: number | null;
};

async function countCompetitivePushesToday(recipientUserId: string, todayStr: string): Promise<number> {
  // PostgREST supports `payload->>kind` as a column reference; we combine kinds with `.or()` to
  // stay portable across supabase-js versions where `.in()` on jsonb extractors can be brittle.
  const kinds = [
    "competitive_challenge_lead_change",
    "competitive_challenge_final_push",
    "competitive_challenge_result",
  ];
  const orFilter = kinds.map((k) => `payload->>kind.eq.${k}`).join(",");
  const { count } = await supabase
    .from("notification_queue")
    .select("id", { count: "exact", head: true })
    .eq("recipient_user_id", recipientUserId)
    .gte("created_at", `${todayStr}T00:00:00Z`)
    .lt("created_at", `${addDaysUTC(todayStr, 1)}T00:00:00Z`)
    .or(orFilter);
  return count ?? 0;
}

async function enqueuePush(payload: Record<string, unknown>, recipientUserId: string, memberUserId: string | null) {
  await supabase.from("notification_queue").insert({
    recipient_user_id: recipientUserId,
    member_user_id: memberUserId,
    alert_state_id: null,
    channel: "push",
    payload,
    status: "pending",
  });
}

async function evaluateChallenge(c: ChallengeRow, todayStr: string) {
  if (!c.start_date) return;
  const lastDayInWindow = c.end_date ?? c.start_date;
  const lastScoredDay = todayStr < lastDayInWindow ? todayStr : lastDayInWindow;
  const window = dateRange(c.start_date, lastScoredDay);
  if (window.length === 0) return;

  // 1) Participants who accepted.
  const { data: participants } = await supabase
    .from("big_competitive_participants")
    .select("challenge_id,user_id,invite_status")
    .eq("challenge_id", c.id);
  const accepted = ((participants ?? []) as ParticipantRow[]).filter((p) => p.invite_status === "accepted");
  if (accepted.length < 2) return;

  // 2) Recompute snapshots for every (participant, date in window).
  //    We re-upsert each day so corrections in source data flow through.
  for (const p of accepted) {
    const upserts: SnapshotRow[] = [];

    if (c.focus === "steps") {
      const { data: stepsRows } = await supabase
        .from("wearable_daily_metrics")
        .select("metric_date, steps")
        .eq("user_id", p.user_id)
        .gte("metric_date", c.start_date)
        .lte("metric_date", lastScoredDay);
      const byDate: Record<string, number> = {};
      for (const row of (stepsRows ?? []) as Array<{ metric_date: string; steps: number | null }>) {
        if (!row?.metric_date) continue;
        // wearable_daily_metrics may have multiple rows per (user_id, metric_date)
        // when more than one source reports; take the max as the best-supported value.
        byDate[row.metric_date] = Math.max(byDate[row.metric_date] ?? 0, Number(row.steps ?? 0));
      }
      for (const day of window) {
        upserts.push({
          challenge_id: c.id,
          user_id: p.user_id,
          local_date: day,
          pillar_score: null,
          steps: byDate[day] ?? 0, // missing day = 0 for cumulative steps.
        });
      }
    } else {
      const colName =
        c.focus === "sleep"
          ? "vitality_sleep_pillar_score"
          : c.focus === "movement"
          ? "vitality_movement_pillar_score"
          : "vitality_stress_pillar_score";
      const { data: vitalityRows } = await supabase
        .from("vitality_scores")
        .select(`score_date, ${colName}`)
        .eq("user_id", p.user_id)
        .gte("score_date", c.start_date)
        .lte("score_date", lastScoredDay);
      const byDate: Record<string, number | null> = {};
      for (const row of (vitalityRows ?? []) as Array<Record<string, unknown>>) {
        const day = row.score_date as string | null;
        if (!day) continue;
        const value = row[colName] as number | null | undefined;
        byDate[day] = value ?? null;
      }
      for (const day of window) {
        const v = byDate[day];
        upserts.push({
          challenge_id: c.id,
          user_id: p.user_id,
          local_date: day,
          pillar_score: typeof v === "number" ? v : null, // missing = exclude (we keep null; aggregator drops nulls)
          steps: null,
        });
      }
    }

    if (upserts.length > 0) {
      const { error } = await supabase
        .from("big_competitive_daily_snapshots")
        .upsert(upserts, { onConflict: "challenge_id,user_id,local_date" });
      if (error) {
        console.error("snapshot upsert error", c.id, p.user_id, error.message);
      }
    }
  }

  // 3) Aggregate per participant.
  type Agg = {
    user_id: string;
    aggregate: number; // primary metric: pillar mean OR steps total
    bestDay: number; // pillars: max(pillar_score); steps: max(steps)
    countedDays: number;
  };
  const aggs: Agg[] = [];
  for (const p of accepted) {
    const { data: snaps } = await supabase
      .from("big_competitive_daily_snapshots")
      .select("local_date,pillar_score,steps")
      .eq("challenge_id", c.id)
      .eq("user_id", p.user_id);
    let aggregate = 0;
    let bestDay = 0;
    let countedDays = 0;
    if (c.focus === "steps") {
      for (const s of (snaps ?? []) as Array<{ pillar_score: number | null; steps: number | null }>) {
        const v = Number(s.steps ?? 0);
        aggregate += v;
        if (v > bestDay) bestDay = v;
        countedDays += 1; // every day counts (0 if missing)
      }
    } else {
      let sum = 0;
      for (const s of (snaps ?? []) as Array<{ pillar_score: number | null; steps: number | null }>) {
        if (s.pillar_score == null) continue;
        const v = Number(s.pillar_score);
        sum += v;
        countedDays += 1;
        if (v > bestDay) bestDay = v;
      }
      aggregate = countedDays > 0 ? sum / countedDays : 0;
    }
    aggs.push({ user_id: p.user_id, aggregate, bestDay, countedDays });
  }

  // 4) Determine leader (highest aggregate; alphabetical tiebreaker not needed at DB level — UI handles).
  aggs.sort((a, b) => (b.aggregate - a.aggregate) || a.user_id.localeCompare(b.user_id));
  const top = aggs[0];
  const second = aggs[1];
  const previousLeaderId = c.current_leader_user_id;
  const isWindowComplete = todayStr > lastDayInWindow;
  const isSaturday = (() => {
    const d = new Date(`${todayStr}T00:00:00Z`);
    return d.getUTCDay() === 6;
  })();
  const isFinalDayOfWindow = todayStr === lastDayInWindow;

  await supabase
    .from("big_competitive_challenges")
    .update({
      current_leader_user_id: top?.user_id ?? null,
      current_leader_metric: top?.aggregate ?? null,
      last_evaluated_at: new Date().toISOString(),
    })
    .eq("id", c.id);

  // 5) Lead-change push: only mid-week and only if leader changed.
  if (!isWindowComplete && top && previousLeaderId && previousLeaderId !== top.user_id) {
    const leaderProfile = await supabase
      .from("family_members")
      .select("first_name")
      .eq("user_id", top.user_id)
      .eq("family_id", c.family_id)
      .maybeSingle();
    const leaderName = (leaderProfile.data?.first_name as string | undefined) ?? "Someone";

    for (const p of accepted) {
      const already = await countCompetitivePushesToday(p.user_id, todayStr);
      if (already >= MAX_COMPETITIVE_PUSHES_PER_DAY) continue;
      const youAhead = p.user_id === top.user_id;
      await enqueuePush(
        {
          kind: "competitive_challenge_lead_change",
          challenge_id: c.id,
          focus: c.focus,
          leader_user_id: top.user_id,
          leader_name: leaderName,
          you_ahead: youAhead,
        },
        p.user_id,
        top.user_id,
      );
    }
  }

  // 6) Saturday final-push: only when the result is still flippable.
  if (!isWindowComplete && (isSaturday || isFinalDayOfWindow) && top && second) {
    const gap = top.aggregate - second.aggregate;
    const closeEnoughToFlip =
      c.focus === "steps" ? gap < 10000 : gap < 5; // ~one big day or ~5 pillar points
    if (closeEnoughToFlip) {
      for (const p of accepted) {
        const already = await countCompetitivePushesToday(p.user_id, todayStr);
        if (already >= MAX_COMPETITIVE_PUSHES_PER_DAY) continue;
        await enqueuePush(
          {
            kind: "competitive_challenge_final_push",
            challenge_id: c.id,
            focus: c.focus,
          },
          p.user_id,
          top.user_id,
        );
      }
    }
  }

  // 7) Window complete → close, declare winner (or draw), log Champions points.
  if (isWindowComplete) {
    const draw = !!(second && top.aggregate === second.aggregate);
    const winnerId = draw ? null : top?.user_id ?? null;

    await supabase
      .from("big_competitive_challenges")
      .update({
        status: "completed",
        completed_at: new Date().toISOString(),
        winner_user_id: winnerId,
        // tie_break_used stays false here; the iOS tie-break RPC sets it to true if the user opts in.
      })
      .eq("id", c.id);

    // Champions point events: only when there is a clear winner (no draw, no tie at top).
    if (!draw && winnerId) {
      if (c.mode === "head_to_head") {
        await supabase.from("big_challenge_champion_point_events").insert({
          family_id: c.family_id,
          user_id: winnerId,
          points: DUEL_WINNER_POINTS,
          reason: "duel_winner",
          competitive_challenge_id: c.id,
          placement: 1,
        });
      } else {
        // Family brawl: rank by aggregate, ties at any tier share the higher placement.
        let placement = 0;
        let lastScore: number | null = null;
        const events: Array<Record<string, unknown>> = [];
        for (let i = 0; i < aggs.length; i++) {
          const row = aggs[i];
          if (lastScore === null || row.aggregate !== lastScore) {
            placement = i + 1;
            lastScore = row.aggregate;
          }
          const points = BRAWL_PLACEMENT_POINTS[placement];
          if (typeof points === "number" && points > 0) {
            events.push({
              family_id: c.family_id,
              user_id: row.user_id,
              points,
              reason: placement === 1 ? "brawl_first_place" : `brawl_placement_${placement}`,
              competitive_challenge_id: c.id,
              placement,
            });
          }
        }
        if (events.length > 0) {
          await supabase.from("big_challenge_champion_point_events").insert(events);
        }
      }
    }

    // Sunday result push (always; result kind is exempt from mid-week 2/day cap concerns since it ships once).
    for (const p of accepted) {
      await enqueuePush(
        {
          kind: "competitive_challenge_result",
          challenge_id: c.id,
          focus: c.focus,
          outcome: draw ? "draw" : "decided",
          you_won: !!winnerId && p.user_id === winnerId,
          winner_user_id: winnerId,
        },
        p.user_id,
        winnerId,
      );
    }
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method === "GET") {
    return jsonResponse({ ok: true, message: "competitive_challenges_daily_evaluate alive" });
  }
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
  }

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
  const max = Number.isFinite(body.maxChallenges) ? Math.max(1, Math.floor(body.maxChallenges)) : 200;

  const todayStr = toYYYYMMDD(new Date());

  const { data: rows, error } = await supabase
    .from("big_competitive_challenges")
    .select(
      "id, family_id, mode, focus, status, start_date, end_date, current_leader_user_id, current_leader_metric, last_evaluated_at",
    )
    .eq("status", "active")
    .lte("start_date", todayStr)
    .limit(max);

  if (error) {
    return jsonResponse({ ok: false, error: `Failed to fetch challenges: ${error.message}` }, 500);
  }

  const results: Array<{ id: string; ok: boolean; error?: string }> = [];
  for (const row of (rows ?? []) as ChallengeRow[]) {
    try {
      await evaluateChallenge(row, todayStr);
      results.push({ id: row.id, ok: true });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error("evaluateChallenge error", row.id, message);
      results.push({ id: row.id, ok: false, error: message });
    }
  }

  return jsonResponse({ ok: true, today: todayStr, evaluated: results.length, results });
});
