import type { AlertLevel, MetricType, PatternType, ThresholdConfig } from "./types.ts";
import { evaluateMetricOnDate } from "./evaluate.ts";
import { levelForConsecutiveTrueDays, severityForLevel, shouldEnqueueNotification } from "./episode.ts";
import thresholdsJSON from "./thresholds.v1.json" with { type: "json" };

type DailyRow = {
  metric_date: string;
  steps: number | null;
  sleep_minutes: number | null;
  hrv_ms: number | null;
  resting_hr: number | null;
};

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

function mergeMax(a: number | null | undefined, b: number | null | undefined): number | null {
  const aa = a == null ? null : Number(a);
  const bb = b == null ? null : Number(b);
  if (aa == null && bb == null) return null;
  if (aa == null) return bb;
  if (bb == null) return aa;
  return Math.max(aa, bb);
}

function loadThresholds(): ThresholdConfig {
  return thresholdsJSON as ThresholdConfig;
}

function buildMetricSeries(metric: MetricType, mergedByDay: Map<string, DailyRow>): Array<{ date: string; value: number }> {
  const keys = Array.from(mergedByDay.keys()).sort();
  const out: Array<{ date: string; value: number }> = [];
  for (const k of keys) {
    const r = mergedByDay.get(k);
    if (!r) continue;
    const v = (() => {
      switch (metric) {
        case "steps":
          return r.steps;
        case "sleep_minutes":
          return r.sleep_minutes;
        case "hrv_ms":
          return r.hrv_ms;
        case "resting_hr":
          return r.resting_hr;
      }
    })();
    if (v == null) continue;
    out.push({ date: k, value: Number(v) });
  }
  return out;
}

async function fetchMergedDailyMetrics(supabase: any, userId: string, startDate: string, endDate: string): Promise<Map<string, DailyRow>> {
  const { data: rows, error } = await supabase
    .from("wearable_daily_metrics")
    .select("metric_date,steps,sleep_minutes,hrv_ms,resting_hr")
    .eq("user_id", userId)
    .gte("metric_date", startDate)
    .lte("metric_date", endDate)
    .order("metric_date", { ascending: true });

  if (error) throw new Error(`wearable_daily_metrics fetch failed: ${error.message}`);

  const mergedByDay = new Map<string, DailyRow>();
  for (const r0 of (rows ?? []) as any[]) {
    const dayKey = String(r0.metric_date);
    const prev = mergedByDay.get(dayKey);
    mergedByDay.set(dayKey, {
      metric_date: dayKey,
      steps: mergeMax(prev?.steps, r0.steps),
      sleep_minutes: mergeMax(prev?.sleep_minutes, r0.sleep_minutes),
      hrv_ms: mergeMax(prev?.hrv_ms, r0.hrv_ms),
      resting_hr: mergeMax(prev?.resting_hr, r0.resting_hr),
    });
  }
  return mergedByDay;
}

async function fetchFamilyAdminRecipients(supabase: any, memberUserId: string): Promise<string[]> {
  // Find family_id for member
  const { data: fm, error: fmErr } = await supabase
    .from("family_members")
    .select("family_id")
    .eq("user_id", memberUserId)
    .maybeSingle();
  if (fmErr || !fm?.family_id) return [memberUserId];

  const familyId = fm.family_id;
  const { data: admins, error: aErr } = await supabase
    .from("family_members")
    .select("user_id,role,invite_status")
    .eq("family_id", familyId)
    .in("role", ["superadmin", "admin"])
    .eq("invite_status", "accepted");
  if (aErr) return [memberUserId];

  const ids = (admins ?? []).map((r: any) => String(r.user_id)).filter((x) => x && x !== "null");
  return ids.length ? Array.from(new Set(ids)) : [memberUserId];
}

async function upsertActiveAlertState(params: {
  supabase: any;
  userId: string;
  metric: MetricType;
  patternType: PatternType;
  activeSince: string;
  endDate: string;
  durationDays: number;
  level: AlertLevel;
  baseline: any;
  deviationPercent: number | null;
}): Promise<{ alertStateId: string | null; lastNotifiedLevel: number | null }> {
  const { supabase, userId, metric, patternType, activeSince, endDate, durationDays, level, baseline, deviationPercent } = params;

  const { data: existing } = await supabase
    .from("pattern_alert_state")
    .select("id,active_since,last_notified_level")
    .eq("user_id", userId)
    .eq("metric_type", metric)
    .eq("pattern_type", patternType)
    .eq("episode_status", "active")
    .order("active_since", { ascending: false })
    .limit(1)
    .maybeSingle();

  // If there is an active episode with a different active_since, resolve it to avoid duplicate actives.
  if (existing?.id && String(existing.active_since) !== activeSince) {
    await supabase.from("pattern_alert_state").update({ episode_status: "resolved" }).eq("id", existing.id);
  }

  const row = {
    user_id: userId,
    metric_type: metric,
    pattern_type: patternType,
    episode_status: "active",
    active_since: activeSince,
    last_evaluated_date: endDate,
    consecutive_true_days: durationDays,
    current_level: level,
    severity: severityForLevel(level),
    baseline_start: baseline?.baselineStart ?? null,
    baseline_end: baseline?.baselineEnd ?? null,
    baseline_value: baseline?.baselineAvg ?? null,
    recent_start: baseline?.recentStart ?? null,
    recent_end: baseline?.recentEnd ?? null,
    recent_value: baseline?.recentAvg ?? null,
    deviation_percent: deviationPercent ?? null,
    computed_at: new Date().toISOString(),
  };

  const { data: up, error: upErr } = await supabase
    .from("pattern_alert_state")
    .upsert(row, { onConflict: "user_id,metric_type,pattern_type,active_since" })
    .select("id,last_notified_level")
    .maybeSingle();

  if (upErr) throw new Error(`pattern_alert_state upsert failed: ${upErr.message}`);
  return { alertStateId: up?.id ?? null, lastNotifiedLevel: up?.last_notified_level ?? existing?.last_notified_level ?? null };
}

async function resolveIfInactive(params: { supabase: any; userId: string; metric: MetricType; patternType: PatternType; endDate: string; thresholds: ThresholdConfig; series: Array<{ date: string; value: number }> }) {
  const { supabase, userId, metric, patternType, endDate, thresholds, series } = params;
  const d0 = endDate;
  const d1 = addDaysUTC(endDate, -1);
  const d2 = addDaysUTC(endDate, -2);
  if (!d1 || !d2) return;

  // Determine how many consecutive clean days are required based on the active episode's current_level.
  // Levels 3/7 recover after 2 clean days; levels 14/21 recover after 3 clean days.
  const { data: active } = await supabase
    .from("pattern_alert_state")
    .select("current_level")
    .eq("user_id", userId)
    .eq("metric_type", metric)
    .eq("pattern_type", patternType)
    .eq("episode_status", "active")
    .maybeSingle();

  if (!active) return;

  const level = Number(active.current_level ?? 3);
  const requiredCleanDays = level >= 14 ? 3 : 2;

  const daysToCheck = requiredCleanDays === 3 ? [d0, d1, d2] : [d0, d1];

  // Clean day definition:
  // - Pattern is not triggered for that day, AND
  // - Recent average is within 5% of baseline (hysteresis to prevent flip-flop).
  const allClean = daysToCheck.every((day) => {
    const { baseline, result } = evaluateMetricOnDate(metric, thresholds, series, day);
    if (result.isTrue) return false;
    if (!baseline) return false;
    const base = Number(baseline.baselineAvg);
    if (!Number.isFinite(base) || base <= 0) return false;

    const deviationPercent = (Number(baseline.recentAvg) - base) / base;
    if (!Number.isFinite(deviationPercent)) return false;

    if (patternType === "drop_vs_baseline") {
      return deviationPercent >= -0.05;
    }
    if (patternType === "rise_vs_baseline") {
      return deviationPercent <= 0.05;
    }
    return true;
  });

  if (!allClean) return;

  await supabase
    .from("pattern_alert_state")
    .update({ episode_status: "resolved", last_evaluated_date: endDate, computed_at: new Date().toISOString() })
    .eq("user_id", userId)
    .eq("metric_type", metric)
    .eq("pattern_type", patternType)
    .eq("episode_status", "active");
}

export async function evaluatePatternsForUser(
  supabase: any,
  params: { userId: string; endDate: string },
): Promise<{ evaluatedEndDate: string; metricsAttempted: number }> {
  const shadowMode = (Deno.env.get("MIYA_PATTERN_SHADOW_MODE") ?? "true").toLowerCase() !== "false";

  const userId = params.userId;
  const endDate = clampEndDateToToday(params.endDate);

  const thresholds = loadThresholds();

  // We need enough history to evaluate episodes and baseline:
  // evaluate at endDate needs up to 24 days of values, and we may look back a bit for episode start.
  const startDate = addDaysUTC(endDate, -60) ?? endDate;
  const mergedByDay = await fetchMergedDailyMetrics(supabase, userId, startDate, endDate);

  const metrics: MetricType[] = ["sleep_minutes", "steps", "hrv_ms", "resting_hr"];
  let attempted = 0;

  for (const metric of metrics) {
    const cfg = thresholds[metric];
    if (!cfg) continue;
    const patternType = cfg.patternType;
    const series = buildMetricSeries(metric, mergedByDay);
    if (!series.length) continue;
    attempted += 1;

    const { baseline, result } = evaluateMetricOnDate(metric, thresholds, series, endDate);

    if (!result.isTrue) {
      await resolveIfInactive({ supabase, userId, metric, patternType, endDate, thresholds, series });
      continue;
    }

    // Find episode start by walking backwards while the pattern remains true; episode start is each day's recentStart (d-2).
    let episodeStart = baseline?.recentStart ?? (addDaysUTC(endDate, -2) ?? endDate);
    for (let i = 1; i <= 40; i++) {
      const day = addDaysUTC(endDate, -i);
      if (!day) break;
      const prev = evaluateMetricOnDate(metric, thresholds, series, day);
      if (!prev.result.isTrue || !prev.baseline) break;
      episodeStart = prev.baseline.recentStart;
    }

    const startD = parseISODateYYYYMMDDToUTCDate(episodeStart);
    const endD = parseISODateYYYYMMDDToUTCDate(endDate);
    const durationDays = startD && endD ? Math.max(1, Math.floor((endD.getTime() - startD.getTime()) / 86400000) + 1) : 3;

    const level = levelForConsecutiveTrueDays(durationDays);

    const { alertStateId, lastNotifiedLevel } = await upsertActiveAlertState({
      supabase,
      userId,
      metric,
      patternType,
      activeSince: episodeStart,
      endDate,
      durationDays,
      level,
      baseline,
      deviationPercent: result.deviationPercent,
    });

    const enqueue = shouldEnqueueNotification({
      shadowMode,
      newLevel: level,
      lastNotifiedLevel: lastNotifiedLevel,
    });

    if (enqueue && alertStateId) {
      const recipients = await fetchFamilyAdminRecipients(supabase, userId);
      for (const recipientUserId of recipients) {
        const payload = {
          kind: "pattern_alert",
          member_user_id: userId,
          metric_type: metric,
          pattern_type: patternType,
          level,
          active_since: episodeStart,
          evaluated_end_date: endDate,
        };

        const { error: qErr } = await supabase.from("notification_queue").insert({
          recipient_user_id: recipientUserId,
          member_user_id: userId,
          alert_state_id: alertStateId,
          channel: "push",
          payload,
          status: "pending",
        });

        if (qErr) {
          console.error("🔴 MIYA_PATTERN_QUEUE_INSERT_ERROR", { userId, recipientUserId, metric, error: qErr.message });
        }
      }

      await supabase.from("pattern_alert_state").update({ last_notified_level: level, last_notified_at: new Date().toISOString() }).eq("id", alertStateId);
    }
  }

  return { evaluatedEndDate: endDate, metricsAttempted: attempted };
}

