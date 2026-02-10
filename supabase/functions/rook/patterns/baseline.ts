import type { BaselineComputation, DailyValue, ISODate } from "./types.ts";

function parseISODateYYYYMMDDToUTCDate(dayKey: ISODate): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dayKey)) return null;
  const d = new Date(`${dayKey}T00:00:00Z`);
  return Number.isNaN(d.getTime()) ? null : d;
}

function toYYYYMMDD(d: Date): ISODate {
  return d.toISOString().slice(0, 10);
}

function addDaysUTC(dayKey: ISODate, deltaDays: number): ISODate | null {
  const d = parseISODateYYYYMMDDToUTCDate(dayKey);
  if (!d) return null;
  d.setUTCDate(d.getUTCDate() + deltaDays);
  return toYYYYMMDD(d);
}

function avg(nums: number[]): number | null {
  if (!nums.length) return null;
  return nums.reduce((a, b) => a + b, 0) / nums.length;
}

function areConsecutiveAsc(dayKeysAsc: ISODate[]): boolean {
  if (dayKeysAsc.length <= 1) return true;
  for (let i = 1; i < dayKeysAsc.length; i++) {
    const prev = dayKeysAsc[i - 1];
    const expected = addDaysUTC(prev, 1);
    if (!expected || expected !== dayKeysAsc[i]) return false;
  }
  return true;
}

/**
 * Compute baseline vs recent for a given endDate.
 *
 * Definitions:
 * - recent: last 3 consecutive days ending at endDate (must be present)
 * - baselinePool: all days strictly before recentStart, capped to last 21 available days
 *
 * Bootstrap:
 * - require >= 7 total data points (so we can have a meaningful baseline)
 * - require baselinePool has >= 4 days
 */
export function computeBaselineForEndDate(
  values: DailyValue[],
  endDate: ISODate,
): BaselineComputation | null {
  const filtered = values
    .filter((d) => d.date <= endDate)
    .slice()
    .sort((a, b) => a.date.localeCompare(b.date));

  if (filtered.length < 7) return null;

  // Recent = last 3 entries, but must represent 3 consecutive day keys
  const recent = filtered.slice(-3);
  if (recent.length < 3) return null;
  const recentKeys = recent.map((d) => d.date);
  if (!areConsecutiveAsc(recentKeys)) return null;
  if (recentKeys[2] !== endDate) return null;

  const recentAvg = avg(recent.map((d) => d.value));
  if (recentAvg == null) return null;

  const recentStart = recentKeys[0];
  const baselinePool = filtered.filter((d) => d.date < recentStart);
  const baseline = baselinePool.slice(-21);
  if (baseline.length < 4) return null;

  const baselineAvg = avg(baseline.map((d) => d.value));
  if (baselineAvg == null) return null;

  return {
    baselineAvg,
    recentAvg,
    baselineDays: baseline.length,
    recentDays: 3,
    baselineStart: baseline[0].date,
    baselineEnd: baseline[baseline.length - 1].date,
    recentStart,
    recentEnd: endDate,
  };
}

/**
 * Detect if there's a data gap (zero values or missing days)
 * @param recentDays - Array of recent day values
 * @returns true if gap detected
 */
function hasDataGap(recentDays: Array<{ date: string; value: number | null }>): boolean {
  // Check for zero values (user didn't wear device)
  const hasZero = recentDays.some(day => day.value === 0);
  
  // Check for null/missing values
  const hasMissing = recentDays.some(day => day.value === null);
  
  return hasZero || hasMissing;
}

/**
 * Enhanced baseline computation with gap detection and minimum data check
 * Returns baseline, recent, gap detection, and minimum data validation
 * @param allDays - All available daily data points
 * @param endDate - End date for computation (YYYY-MM-DD)
 * @param metricName - Name of the metric being analyzed
 * @returns Object with baseline, recent, gap detection, and data sufficiency
 */
export function computeBaselineWithGapDetection(
  allDays: Array<{ date: string; value: number | null }>,
  endDate: string,
  metricName: string
): {
  baseline: number;
  recent: number;
  isGapDetected: boolean;
  hasMinimumData: boolean;
  totalDays: number;
} | null {
  // Check minimum 7-day requirement
  const hasMinimumData = allDays.length >= 7;
  
  // Try to compute baseline using existing function
  const result = computeBaselineForEndDate(allDays, endDate, metricName);
  
  if (!result) {
    return {
      baseline: 0,
      recent: 0,
      isGapDetected: false,
      hasMinimumData,
      totalDays: allDays.length
    };
  }
  
  // Check for data gap in recent period (last 3 days)
  const recentEnd = allDays.findIndex(d => d.date === endDate);
  if (recentEnd === -1) {
    return {
      baseline: result.baseline,
      recent: result.recent,
      isGapDetected: false,
      hasMinimumData,
      totalDays: allDays.length
    };
  }
  
  const recentDays = allDays.slice(Math.max(0, recentEnd - 2), recentEnd + 1);
  const isGapDetected = hasDataGap(recentDays);
  
  return {
    baseline: result.baseline,
    recent: result.recent,
    isGapDetected,
    hasMinimumData,
    totalDays: allDays.length
  };
}
