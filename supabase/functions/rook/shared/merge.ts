/**
 * Shared merge logic for wearable_daily_metrics.
 * Merge by day with mergeMax; do not use raw rows per day for scoring or alerts.
 *
 * wearable_daily_metrics stores one row per (rook_user_id, metric_date, source).
 * Any reader that aggregates by day MUST merge per day using mergeMax (take the
 * maximum value across sources for each metric). See docs/WEARABLE_DAILY_METRICS_MERGE.md.
 */

/**
 * Null-safe max of two numeric values. Used to merge multiple sources per day.
 */
export function mergeMax(
  a: number | null | undefined,
  b: number | null | undefined,
): number | null {
  const aa = a == null ? null : Number(a);
  const bb = b == null ? null : Number(b);
  if (aa == null && bb == null) return null;
  if (aa == null) return bb;
  if (bb == null) return aa;
  return Math.max(aa, bb);
}

const DEFAULT_DAY_KEY_FIELD = "metric_date";

/**
 * Merge raw wearable_daily_metrics rows by day using mergeMax for each numeric field.
 * Returns a Map from day key (YYYY-MM-DD) to a single merged row (day key + all numeric fields merged).
 *
 * @param rows - Raw rows from wearable_daily_metrics (may have multiple rows per day from different sources)
 * @param numericFields - Field names to merge with mergeMax (e.g. steps, sleep_minutes, hrv_ms)
 * @param dayKeyField - Field that holds the date string (default "metric_date")
 */
export function mergeRowsByDay<T extends Record<string, unknown>>(
  rows: any[],
  numericFields: string[],
  dayKeyField: string = DEFAULT_DAY_KEY_FIELD,
): Map<string, T> {
  const mergedByDay = new Map<string, Record<string, unknown>>();
  for (const r0 of rows) {
    const dayKey = String(r0[dayKeyField] ?? "");
    const prev = mergedByDay.get(dayKey) as Record<string, unknown> | undefined;
    const merged: Record<string, unknown> = { [dayKeyField]: dayKey };
    for (const field of numericFields) {
      const a = prev?.[field] as number | null | undefined;
      const b = r0[field] as number | null | undefined;
      merged[field] = mergeMax(a, b);
    }
    mergedByDay.set(dayKey, merged);
  }
  return mergedByDay as Map<string, T>;
}
