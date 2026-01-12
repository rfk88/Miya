import { scoreIfPossible } from "./score.ts";
import { scoringSchema } from "./schema.ts";
import type { VitalitySnapshot } from "./types.ts";

export type RecomputeResult = {
  attemptedEndDates: string[];
  computedEndDates: string[];
  skippedEndDates: Array<{ endDate: string; reason: string }>;
  latestComputed: { endDate: string; snapshot: VitalitySnapshot } | null;
};

type DailyRow = {
  metric_date: string;
  steps: number | null;
  sleep_minutes: number | null;
  hrv_ms: number | null;
  resting_hr: number | null;
  calories_active: number | null;
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

function mergeMax(a: number | null | undefined, b: number | null | undefined): number | null {
  const aa = a == null ? null : Number(a);
  const bb = b == null ? null : Number(b);
  if (aa == null && bb == null) return null;
  if (aa == null) return bb;
  if (bb == null) return aa;
  return Math.max(aa, bb);
}

function avg(nums: Array<number | null>): number | null {
  const xs = nums.filter((x) => x != null) as number[];
  if (!xs.length) return null;
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

function avgIntRounded(nums: Array<number | null>): number | null {
  const a = avg(nums);
  return a == null ? null : Math.round(a);
}

function backfillDoubleIfNeeded(
  current: number | null,
  lookbackKeysDesc: string[],
  mergedByDay: Map<string, DailyRow>,
  getter: (d: DailyRow) => number | null,
): number | null {
  if (current != null) return current;
  for (const k of lookbackKeysDesc) {
    const day = mergedByDay.get(k);
    if (!day) continue;
    const v = getter(day);
    if (v != null) return v;
  }
  return null;
}

function backfillIntIfNeeded(
  current: number | null,
  lookbackKeysDesc: string[],
  mergedByDay: Map<string, DailyRow>,
  getter: (d: DailyRow) => number | null,
): number | null {
  if (current != null) return current;
  for (const k of lookbackKeysDesc) {
    const day = mergedByDay.get(k);
    if (!day) continue;
    const v = getter(day);
    if (v != null) return Math.round(v);
  }
  return null;
}

export async function recomputeRolling7dScoresForUser(
  supabase: any,
  params: { userId: string; age: number; startEndDate: string; endEndDate: string },
): Promise<RecomputeResult> {
  const { userId, age, startEndDate, endEndDate } = params;
  const attemptedEndDates: string[] = [];
  const computedEndDates: string[] = [];
  const skippedEndDates: Array<{ endDate: string; reason: string }> = [];
  let latestComputed: { endDate: string; snapshot: VitalitySnapshot } | null = null;

  const startD = parseISODateYYYYMMDDToUTCDate(startEndDate);
  const endD = parseISODateYYYYMMDDToUTCDate(endEndDate);
  if (!startD || !endD) {
    throw new Error(`Invalid date range start=${startEndDate} end=${endEndDate}`);
  }
  if (startEndDate > endEndDate) {
    throw new Error(`startEndDate must be <= endEndDate`);
  }

  // Iterate each end date in [startEndDate..endEndDate] (inclusive)
  for (
    let cur = new Date(startD.getTime());
    cur.getTime() <= endD.getTime();
    cur.setUTCDate(cur.getUTCDate() + 1)
  ) {
    const endDate = toYYYYMMDD(cur);
    attemptedEndDates.push(endDate);

    const windowStart = addDaysUTC(endDate, -6) ?? endDate;
    const lookbackStart = addDaysUTC(windowStart, -7) ?? windowStart;

    const { data: rows, error: rowsErr } = await supabase
      .from("wearable_daily_metrics")
      .select("metric_date,steps,sleep_minutes,hrv_ms,resting_hr,calories_active")
      .eq("user_id", userId)
      .gte("metric_date", lookbackStart)
      .lte("metric_date", endDate)
      .order("metric_date", { ascending: true });

    if (rowsErr) {
      skippedEndDates.push({ endDate, reason: `metrics_fetch_error:${rowsErr.message}` });
      continue;
    }

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
        calories_active: mergeMax(prev?.calories_active, r0.calories_active),
      });
    }

    const allKeys = Array.from(mergedByDay.keys()).sort();
    const windowKeys = allKeys.filter((k) => k >= windowStart && k <= endDate);
    const lookbackKeysDesc = allKeys.filter((k) => k >= lookbackStart && k < windowStart).sort().reverse();

    const dailyWindow = windowKeys.map((k) => mergedByDay.get(k)!).filter(Boolean);

    const sleepHoursUnfilled = (() => {
      const minutesAvg = avg(dailyWindow.map((d) => d.sleep_minutes));
      return minutesAvg == null ? null : minutesAvg / 60.0;
    })();
    const stepsUnfilled = avgIntRounded(dailyWindow.map((d) => d.steps));
    const caloriesActiveUnfilled = avg(dailyWindow.map((d) => d.calories_active));
    const hrvMsUnfilled = avg(dailyWindow.map((d) => d.hrv_ms));
    const restingHrUnfilled = avg(dailyWindow.map((d) => d.resting_hr));

    const sleepDurationHours = backfillDoubleIfNeeded(
      sleepHoursUnfilled,
      lookbackKeysDesc,
      mergedByDay,
      (d) => (d.sleep_minutes == null ? null : d.sleep_minutes / 60.0),
    );
    const stepsFinal = backfillIntIfNeeded(stepsUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.steps);
    const activeCalories = backfillDoubleIfNeeded(caloriesActiveUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.calories_active);
    const hrvMsFinal = backfillDoubleIfNeeded(hrvMsUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.hrv_ms);
    const restingHrFinal = backfillDoubleIfNeeded(restingHrUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.resting_hr);

    const raw = {
      age,
      sleepDurationHours,
      restorativeSleepPercent: null,
      sleepEfficiencyPercent: null,
      awakePercent: null,
      movementMinutes: null,
      steps: stepsFinal,
      activeCalories,
      hrvMs: hrvMsFinal,
      hrvType: null,
      restingHeartRate: restingHrFinal,
      breathingRate: null,
    };

    const snap = scoreIfPossible(raw);
    if (!snap) {
      skippedEndDates.push({ endDate, reason: "insufficient_data" });
      continue;
    }

    const sleep = snap.pillarScores.find((p) => p.pillar === "sleep")?.score ?? 0;
    const movement = snap.pillarScores.find((p) => p.pillar === "movement")?.score ?? 0;
    const stress = snap.pillarScores.find((p) => p.pillar === "stress")?.score ?? 0;

    const scoreRow = {
      user_id: userId,
      score_date: endDate,
      total_score: snap.totalScore,
      vitality_sleep_pillar_score: sleep,
      vitality_movement_pillar_score: movement,
      vitality_stress_pillar_score: stress,
      source: "wearable",
      schema_version: scoringSchema.schemaVersion,
      computed_at: new Date().toISOString(),
    };

    const { error: vsErr } = await supabase.from("vitality_scores").upsert(scoreRow, { onConflict: "user_id,score_date" });
    if (vsErr) {
      skippedEndDates.push({ endDate, reason: `vitality_upsert_error:${vsErr.message}` });
      continue;
    }

    computedEndDates.push(endDate);
    if (!latestComputed || endDate > latestComputed.endDate) {
      latestComputed = { endDate, snapshot: snap };
    }
  }

  return { attemptedEndDates, computedEndDates, skippedEndDates, latestComputed };
}


