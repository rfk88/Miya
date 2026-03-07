import { mergeRowsByDay } from "../shared/merge.ts";
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
  hrv_rmssd_ms: number | null;
  resting_hr: number | null;
  breaths_avg_per_min: number | null;
  spo2_avg_pct: number | null;
  calories_active: number | null;
  movement_minutes: number | null;
  deep_sleep_minutes: number | null;
  rem_sleep_minutes: number | null;
  light_sleep_minutes: number | null;
  awake_minutes: number | null;
  sleep_efficiency_pct: number | null;
  time_to_fall_asleep_minutes: number | null;
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
      .select("metric_date,steps,sleep_minutes,hrv_ms,hrv_rmssd_ms,resting_hr,breaths_avg_per_min,spo2_avg_pct,calories_active,movement_minutes,deep_sleep_minutes,rem_sleep_minutes,light_sleep_minutes,awake_minutes,sleep_efficiency_pct,time_to_fall_asleep_minutes")
      .eq("user_id", userId)
      .gte("metric_date", lookbackStart)
      .lte("metric_date", endDate)
      .order("metric_date", { ascending: true });

    if (rowsErr) {
      skippedEndDates.push({ endDate, reason: `metrics_fetch_error:${rowsErr.message}` });
      continue;
    }

    // Merge by day with mergeMax; do not use raw rows per day for scoring.
    const RECOMPUTE_NUMERIC_FIELDS = [
      "steps", "sleep_minutes", "hrv_ms", "hrv_rmssd_ms", "resting_hr",
      "breaths_avg_per_min", "spo2_avg_pct", "calories_active", "movement_minutes",
      "deep_sleep_minutes", "rem_sleep_minutes", "light_sleep_minutes", "awake_minutes",
      "sleep_efficiency_pct", "time_to_fall_asleep_minutes",
    ] as const;
    const mergedByDay = mergeRowsByDay<DailyRow>(
      (rows ?? []) as any[],
      [...RECOMPUTE_NUMERIC_FIELDS],
      "metric_date",
    );

    const allKeys = Array.from(mergedByDay.keys()).sort();
    const windowKeys = allKeys.filter((k) => k >= windowStart && k <= endDate);
    const lookbackKeysDesc = allKeys.filter((k) => k >= lookbackStart && k < windowStart).sort().reverse();

    const dailyWindow = windowKeys.map((k) => mergedByDay.get(k)!).filter(Boolean);

    const sleepMinutesUnfilled = avgIntRounded(dailyWindow.map((d) => d.sleep_minutes));
    const stepsUnfilled = avgIntRounded(dailyWindow.map((d) => d.steps));
    const caloriesActiveUnfilled = avg(dailyWindow.map((d) => d.calories_active));
    const hrvMsUnfilled = avg(dailyWindow.map((d) => d.hrv_ms));
    const hrvRmssdUnfilled = avg(dailyWindow.map((d) => d.hrv_rmssd_ms));
    const restingHrUnfilled = avg(dailyWindow.map((d) => d.resting_hr));
    const breathsAvgUnfilled = avg(dailyWindow.map((d) => d.breaths_avg_per_min));
    const spo2AvgUnfilled = avg(dailyWindow.map((d) => d.spo2_avg_pct));
    const movementMinutesUnfilled = avgIntRounded(dailyWindow.map((d) => d.movement_minutes));
    const sleepEfficiencyUnfilled = avg(dailyWindow.map((d) => d.sleep_efficiency_pct));
    const deepSleepMinutesUnfilled = avgIntRounded(dailyWindow.map((d) => d.deep_sleep_minutes));
    const remSleepMinutesUnfilled = avgIntRounded(dailyWindow.map((d) => d.rem_sleep_minutes));
    const lightSleepMinutesUnfilled = avgIntRounded(dailyWindow.map((d) => d.light_sleep_minutes));
    const awakeMinutesUnfilled = avgIntRounded(dailyWindow.map((d) => d.awake_minutes));
    const timeToFallAsleepUnfilled = avgIntRounded(dailyWindow.map((d) => d.time_to_fall_asleep_minutes));

    const sleepMinutesFinal = backfillIntIfNeeded(
      sleepMinutesUnfilled,
      lookbackKeysDesc,
      mergedByDay,
      (d) => d.sleep_minutes,
    );
    const stepsFinal = backfillIntIfNeeded(stepsUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.steps);
    const activeCalories = backfillDoubleIfNeeded(caloriesActiveUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.calories_active);
    const hrvMsFinal = backfillDoubleIfNeeded(hrvMsUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.hrv_ms);
    const hrvRmssdFinal = backfillDoubleIfNeeded(hrvRmssdUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.hrv_rmssd_ms);
    const restingHrFinal = backfillDoubleIfNeeded(restingHrUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.resting_hr);
    const breathsAvgFinal = backfillDoubleIfNeeded(breathsAvgUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.breaths_avg_per_min);
    const spo2AvgFinal = backfillDoubleIfNeeded(spo2AvgUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.spo2_avg_pct);
    const movementMinutesFinal = backfillIntIfNeeded(movementMinutesUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.movement_minutes);
    const sleepEfficiencyPercent = backfillDoubleIfNeeded(sleepEfficiencyUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.sleep_efficiency_pct);
    const deepSleepMinutesFinal = backfillIntIfNeeded(deepSleepMinutesUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.deep_sleep_minutes);
    const remSleepMinutesFinal = backfillIntIfNeeded(remSleepMinutesUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.rem_sleep_minutes);
    const lightSleepMinutesFinal = backfillIntIfNeeded(lightSleepMinutesUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.light_sleep_minutes);
    const awakeMinutesFinal = backfillIntIfNeeded(awakeMinutesUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.awake_minutes);
    const timeToFallAsleepMinutes = backfillIntIfNeeded(timeToFallAsleepUnfilled, lookbackKeysDesc, mergedByDay, (d) => d.time_to_fall_asleep_minutes);

    // Sleep guardrails: if total sleep_minutes is missing, derive from stage breakdown (deep + rem + light).
    const deep = deepSleepMinutesFinal ?? 0;
    const rem = remSleepMinutesFinal ?? 0;
    const light = lightSleepMinutesFinal ?? 0;
    const stagesSum = deep + rem + light;
    const derivedSleepMinutes =
      Number.isFinite(stagesSum) && stagesSum > 0 ? Math.round(stagesSum) : null;
    const effectiveSleepMinutes =
      sleepMinutesFinal != null && sleepMinutesFinal > 0
        ? sleepMinutesFinal
        : derivedSleepMinutes;
    const sleepDurationHours =
      effectiveSleepMinutes != null && effectiveSleepMinutes > 0
        ? effectiveSleepMinutes / 60.0
        : null;

    // Restorative %: (deep + rem) / effective total. Return null if deep and rem both missing (don't penalize).
    const restorativeSleepPercent = (() => {
      if (effectiveSleepMinutes == null || effectiveSleepMinutes <= 0) return null;
      const restorative = deep + rem;
      if (!Number.isFinite(restorative) || restorative <= 0) return null;
      return Math.round((restorative / effectiveSleepMinutes) * 100);
    })();

    // Awake %: awake / (effective sleep + awake). Use effective total when available.
    const awakePercent = (() => {
      const sleepForAwake = effectiveSleepMinutes ?? sleepMinutesFinal;
      if (awakeMinutesFinal == null || sleepForAwake == null) return null;
      const denom = sleepForAwake + awakeMinutesFinal;
      if (!Number.isFinite(denom) || denom <= 0) return null;
      return Math.round((awakeMinutesFinal / denom) * 100);
    })();
    const hrvForScore = hrvMsFinal ?? hrvRmssdFinal;

    const raw = {
      age,
      sleepDurationHours,
      restorativeSleepPercent,
      sleepEfficiencyPercent,
      awakePercent,
      movementMinutes: movementMinutesFinal,
      steps: stepsFinal,
      activeCalories,
      hrvMs: hrvForScore,
      hrvType: hrvMsFinal != null ? "sdnn" : (hrvRmssdFinal != null ? "rmssd" : null),
      restingHeartRate: restingHrFinal,
      breathingRate: breathsAvgFinal,
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


