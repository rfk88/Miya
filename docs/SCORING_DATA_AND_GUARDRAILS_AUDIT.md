# Scoring Data & Guardrails Audit

This document answers: **what data is pulled for Sleep, Movement, and Recovery (Stress)?** and **where are the gaps / missing guardrails?**

---

## 1. Sleep pillar

### Data pulled (sources)

| Sub-metric (schema)      | Source column(s) in `wearable_daily_metrics`     | Used in recompute? |
|--------------------------|---------------------------------------------------|--------------------|
| **Sleep Duration**       | `sleep_minutes` → converted to hours              | ✅ Yes             |
| **Restorative Sleep %**  | `deep_sleep_minutes`, `rem_sleep_minutes`, `sleep_minutes` → (deep+rem)/total | ✅ Yes (derived)   |
| **Sleep Efficiency**     | `sleep_efficiency_pct`                            | ✅ Yes             |
| **Awake %**             | `awake_minutes`, `sleep_minutes` → awake/(sleep+awake) | ✅ Yes (derived)   |

**Rook ingestion** (`supabase/functions/rook/index.ts`):  
Sleep comes from payload keys such as `sleep_duration_seconds_int`, `deep_sleep_duration_seconds_int`, `rem_sleep_duration_seconds_int`, `light_sleep_duration_seconds_int`, `time_awake_during_sleep_seconds_int`, `time_in_bed_seconds_int`, `time_to_fall_asleep_seconds_int`. Sleep efficiency is computed as `(sleep_seconds / time_in_bed_seconds) * 100` when both exist.

### Gaps and missing guardrails

1. **Sleep duration has no fallback when total is missing**  
   - `sleepDurationHours` in `recompute.ts` is **only** from `sleep_minutes`.  
   - If a source sends only stage breakdown (deep/rem/light/awake) and no total duration, we never set `sleep_minutes` and sleep duration for scoring is **null**.  
   - **Guardrail needed:** If `sleep_minutes` is null but we have `deep_sleep_minutes` + `rem_sleep_minutes` + `light_sleep_minutes` (and optionally `awake_minutes`), **derive total sleep** = deep + rem + light (and use that for duration; optionally include awake in denominator for awake%).

2. **Restorative % when deep/rem are missing**  
   - `restorativeSleepPercent` = (deep + rem) / `sleep_minutes`.  
   - If deep/rem are null but `sleep_minutes` is set, we effectively get 0% restorative (or null if logic short-circuits).  
   - Scoring **already** renormalizes weights over available sub-metrics, so we don’t double-penalize, but we still treat “no data” as 0%.  
   - **Guardrail needed:** If both deep and rem are null, treat restorative as **unavailable** (don’t score it); pillar score should use only duration, efficiency, awake % (when available). This is already the intended behavior in `score.ts` (null → skip that sub-metric); recompute must not pass a synthetic 0.

3. **Sleep efficiency**  
   - Only from `sleep_efficiency_pct`. No fallback (e.g. we don’t store `time_in_bed` in `wearable_daily_metrics`, so we can’t recompute efficiency from duration + time in bed).  
   - Acceptable as-is; optional improvement is to derive efficiency from sleep_minutes and time_in_bed if we ever store time_in_bed.

4. **Awake %**  
   - Requires both `awake_minutes` and `sleep_minutes`. No fallback.  
   - If only awake is missing, we could treat awake % as “unknown” (null) and let scoring renormalize; no code change needed if we already pass null.

---

## 2. Movement pillar

### Data pulled (sources)

| Sub-metric (schema) | Source column(s) in `wearable_daily_metrics` | Used in recompute? |
|---------------------|------------------------------------------------|--------------------|
| **Steps**           | `steps`                                        | ✅ Yes             |
| **Movement minutes**| `movement_minutes`                             | ✅ Yes             |
| **Active calories**| `calories_active`                              | ✅ Yes             |

**Rook ingestion:**  
- Steps: `steps`, `steps_int`, `accumulated_steps_int`, `active_steps_int`, etc.  
- Movement minutes: `active_seconds_int` / `activeSeconds` / `activity_duration_seconds_int` → converted to minutes.  
- Active calories: `calories_net_active_kcal_float`, `active_calories_kcal_double`, `activeCalories`, `active_energy_burned_kcal_double`.

**DB:** `wearable_daily_metrics.calories_active` exists (migration `20251221200000_add_wearable_daily_metrics.sql`). Recompute selects it and passes `activeCalories` into the scoring `raw` object; `score.ts` uses `raw.activeCalories` for the Movement pillar.

### Gaps and possible “active calories not showing”

1. **Pipeline is correct end-to-end**  
   - Rook writes `calories_active` when it finds one of the known keys.  
   - Recompute reads `calories_active` and passes it as `activeCalories`.  
   - Scoring uses it (and renormalizes weight if it’s missing).  

2. **Why you might not see active calories**  
   - **Payload key mismatch:** Your device/source (e.g. Apple Health, Fitbit, Oura) might use a different JSON key (e.g. `active_energy_burned`, `calories_active_kcal`, or a nested path).  
   - **Event type:** Active calories might only appear on **activity/session** events and not be aggregated into the **daily summary** that populates `wearable_daily_metrics`. So we may need to aggregate activity-event calories into the daily row.  

3. **Guardrails**  
   - Movement already benefits from “missing sub-metrics don’t penalize”: if `activeCalories` is null, scoring uses only steps and movement_minutes and renormalizes weights.  
   - **Recommendation:** Add more Rook key variants for active calories (e.g. `active_energy_burned`, `calories_active_kcal`) and/or add logging when `calories_active` is null after ingestion so you can confirm whether the gap is ingestion vs. scoring.

---

## 3. Recovery / Stress pillar

### Data pulled (sources)

| Sub-metric (schema) | Source column(s) in `wearable_daily_metrics` | Used in recompute? |
|---------------------|------------------------------------------------|--------------------|
| **HRV**             | `hrv_ms` **or** `hrv_rmssd_ms`                 | ✅ Yes             |
| **Resting heart rate** | `resting_hr`                                | ✅ Yes             |
| **Breathing rate**   | `breaths_avg_per_min`                          | ✅ Yes             |

**Guardrail in place:**  
- `hrvForScore = hrvMsFinal ?? hrvRmssdFinal` — if SDNN is missing we use RMSSD. Good.

Scoring renormalizes over available sub-metrics, so if only HRV is present we still get a stress pillar score. No additional guardrails strictly required for “if X missing use Y” beyond the HRV fallback.

---

## 4. Summary: what’s pulled vs what’s missing

| Pillar   | What’s pulled correctly                         | Gaps / missing guardrails |
|----------|--------------------------------------------------|----------------------------|
| **Sleep**   | Duration (from `sleep_minutes`), restorative % (deep+rem), efficiency, awake % | 1) No **derived total sleep** when only stages exist (deep+rem+light). 2) Don’t treat missing deep/rem as 0% restorative; keep as null so weight renormalizes. |
| **Movement**| Steps, movement_minutes, active calories (in code path) | **Active calories** may not be in your Rook payload (key names or only on activity events). Add key variants + optional logging. |
| **Recovery**| HRV (with SDNN ↔ RMSSD fallback), RHR, breathing | None critical. |

---

## 5. Recommended guardrails (implementation checklist)

1. **Sleep – derive total when only stages exist** — **DONE**  
   - In `recompute.ts`: `effectiveSleepMinutes` = `sleep_minutes` when present and > 0, else derived from deep + rem + light when that sum > 0. `sleepDurationHours`, restorative %, and awake % use this effective total.

2. **Sleep – restorative %** — **DONE**  
   - Restorative % uses effective total as denominator and returns null when deep+rem are both missing (no synthetic 0).

3. **Movement – active calories** — **DONE**  
   - Added Rook payload key variants: `active_energy_burned`, `calories_active_kcal`, `activeEnergyBurned`, `calories_active`.  
   - Added debug log `MIYA_ACTIVE_CALORIES_MISSING` when we have steps or movement_minutes but no active calories (to spot missing keys in payloads).  
   - If active calories only come from activity events, aggregation into daily summary would require a separate change.

4. **Recovery**  
   - No change required beyond existing HRV fallback.

5. **Minimum data / eligibility**  
   - Already enforced: `scoreIfPossible` requires ≥2 pillars with ≥1 available sub-metric; weights renormalize over available sub-metrics only. Keep this behavior.

---

## 6. Files to touch for guardrails

| Change | File(s) |
|--------|--------|
| Derive sleep total from stages when `sleep_minutes` missing | `supabase/functions/rook/scoring/recompute.ts` |
| Extra active-calorie keys / logging | `supabase/functions/rook/index.ts` |
| Restorative null (no synthetic 0) | `supabase/functions/rook/scoring/recompute.ts` (verify only) |

This audit reflects the current codebase; implementing the guardrails above will make scoring robust to missing totals (sleep) and improve movement data (active calories) when the source sends it under different keys or event types.
