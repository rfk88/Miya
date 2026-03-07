# Wearable Daily Metrics — Merge Contract

## Table semantics

`wearable_daily_metrics` stores **one row per (rook_user_id, metric_date, source)**. Multiple sources per day (e.g. Apple Health and Oura) are intentional: each source writes its own row.

## Merge requirement

Any reader that aggregates by day for **scoring**, **alerts**, or **insights** **must** merge per day using **mergeMax**: take the **maximum** value across sources for each metric. Never sum or average raw rows per day without merging first; otherwise you double-count or mix values when a user has multiple sources.

- **mergeMax**: for each numeric field, the merged value for a day is `max(a, b)` across rows for that day, with nulls ignored (null and value → value; null and null → null).

## Shared implementation

- **Module:** `supabase/functions/rook/shared/merge.ts`
  - `mergeMax(a, b)` — null-safe max of two numbers.
  - `mergeRowsByDay(rows, numericFields, dayKeyField)` — given raw rows, returns `Map<dayKey, mergedRow>` with each numeric field merged by mergeMax.

## Consumers (must use shared merge)

1. **Scoring:** `supabase/functions/rook/scoring/recompute.ts` — rolling 7-day vitality score; uses `mergeRowsByDay` before computing pillar inputs.
2. **Pattern alerts:** `supabase/functions/rook/patterns/engine.ts` — `fetchMergedDailyMetrics` uses `mergeRowsByDay` before evaluating baseline vs recent.
3. **AI insights:** `supabase/functions/miya_insight/index.ts` — uses `mergeRowsByDay` before building the metric series for the insight prompt.

Any new code that reads from `wearable_daily_metrics` and aggregates by day must use this module (or the same mergeMax rule); do not add new ad-hoc merge logic.
