# ROOK to Miya Data Flow

**Version:** 1.0  
**Date:** December 14, 2025

---

## Overview Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         User's Wearable                          │
│  (Whoop, Apple Watch, Fitbit, Oura, Garmin, etc.)              │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               │ Native sync (Bluetooth, WiFi)
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                         ROOK Health API                          │
│  • Aggregates data from 200+ wearables                          │
│  • Normalizes to common JSON schema                             │
│  • Handles OAuth, rate limits, retries                          │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               │ HTTPS REST API
                               │ (sleep, physical, events endpoints)
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Miya iOS App                                │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │              ROOKAPIClient.swift                        │    │
│  │  • Fetch /v1/summaries/sleep/{user}/{date}            │    │
│  │  • Fetch /v1/summaries/physical/{user}/{date}         │    │
│  │  • Fetch /v1/events/physical (for fallbacks)          │    │
│  └─────────────────────┬──────────────────────────────────┘    │
│                        │                                         │
│                        │ ROOKSleepSummary,                      │
│                        │ ROOKPhysicalSummary                    │
│                        ▼                                         │
│  ┌────────────────────────────────────────────────────────┐    │
│  │            ROOKDataAdapter.swift                        │    │
│  │  • Map ROOK JSON → VitalityRawMetrics                  │    │
│  │  • Apply transformation rules                          │    │
│  │  • Handle fallbacks (HRV types, RHR sources)           │    │
│  │  • Preserve nil (don't substitute zeros)               │    │
│  └─────────────────────┬──────────────────────────────────┘    │
│                        │                                         │
│                        │ VitalityRawMetrics                     │
│                        ▼                                         │
│  ┌────────────────────────────────────────────────────────┐    │
│  │         VitalityMetricsBuilder.fromWindow()             │    │
│  │  • Aggregate 7-30 days of data                         │    │
│  │  • Average: sleep hours, steps, HRV, RHR              │    │
│  │  • Output: Single VitalityRawMetrics for scoring      │    │
│  └─────────────────────┬──────────────────────────────────┘    │
│                        │                                         │
│                        │ VitalityRawMetrics (aggregated)        │
│                        ▼                                         │
│  ┌────────────────────────────────────────────────────────┐    │
│  │          VitalityScoringEngine.score()                  │    │
│  │  • Apply age-specific ranges                           │    │
│  │  • Score each sub-metric (0-100)                       │    │
│  │  • Weighted average → pillar scores                    │    │
│  │  • Weighted average → total vitality                   │    │
│  └─────────────────────┬──────────────────────────────────┘    │
│                        │                                         │
│                        │ VitalitySnapshot                       │
│                        ▼                                         │
│  ┌────────────────────────────────────────────────────────┐    │
│  │               RiskResultsView UI                        │    │
│  │  • Display total vitality (0-100)                      │    │
│  │  • Display pillar scores                               │    │
│  │  • Display optimal target (risk-adjusted goal)         │    │
│  │  • Show last sync timestamp                            │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Detailed Data Flow

### Step 1: ROOK API Fetch (Multi-Day)

**Input:** User ID, Date Range (e.g., last 30 days)

**API Calls:**
```
For each date in range:
  GET /v1/summaries/sleep/{user_id}/{date}
  GET /v1/summaries/physical/{user_id}/{date}
```

**Output:** Arrays of `ROOKSleepSummary` and `ROOKPhysicalSummary`

**Example Response (Sleep):**
```json
{
  "sleep_duration_seconds_int": 28800,
  "rem_sleep_duration_seconds_int": 6480,
  "deep_sleep_duration_seconds_int": 7200,
  "hrv_sdnn_ms_double": 55.3,
  "hr_resting_bpm_int": 58,
  "breaths_avg_per_min_int": 14
}
```

**Example Response (Physical):**
```json
{
  "steps_int": 9234,
  "active_minutes_total_int": 47,
  "active_calories_kcal_double": 487.3
}
```

---

### Step 2: ROOK Data Adapter (Per Day)

**Input:** `ROOKSleepSummary`, `ROOKPhysicalSummary` (for one day)

**Transformation Rules Applied:**

| Field | ROOK Source | Transform | Output |
|-------|-------------|-----------|--------|
| sleepDurationHours | `sleep_duration_seconds_int` | `÷ 3600` | 8.0 |
| restorativeSleepPercent | `(rem + deep) / total` | `× 100` | 47.5 |
| hrvMs | `hrv_sdnn_ms_double` | direct | 55.3 |
| hrvType | — | based on field used | "sdnn" |
| restingHeartRate | `hr_resting_bpm_int` | direct | 58.0 |
| breathingRate | `breaths_avg_per_min_int` | direct | 14.0 |
| steps | `steps_int` | direct | 9234 |
| movementMinutes | `active_minutes_total_int` | direct | 47.0 |
| activeCalories | `active_calories_kcal_double` | direct | 487.3 |

**Output:** One `VitalityRawMetrics` per day (partial data, some fields may be nil)

---

### Step 3: Vitality Metrics Builder (Multi-Day Aggregation)

**Input:** Array of `VitalityRawMetrics` (one per day, 7-30 days)

**Aggregation Logic:**
```
For each numeric field:
  - Filter out nil values
  - Calculate average
  - If all values nil → output nil
  - Else → output average

Window selection:
  - If 30+ days available → use last 30
  - If 7-29 days available → use all
  - If <7 days → use all, but warn user
```

**Example:**
```
Day 1: sleep=7.5h, steps=8500, hrv=52ms
Day 2: sleep=8.0h, steps=9200, hrv=55ms
Day 3: sleep=7.2h, steps=7800, hrv=nil
...
Day 30: sleep=7.8h, steps=9000, hrv=54ms

Aggregated:
  sleepDurationHours = 7.6h (average of 30 days)
  steps = 8800 (average of 30 days)
  hrvMs = 53.5ms (average of 28 days, 2 days missing)
```

**Output:** Single `VitalityRawMetrics` (age + 10 averaged metrics)

---

### Step 4: Vitality Scoring Engine

**Input:** One `VitalityRawMetrics` (aggregated)

**Scoring Logic:**

**For each sub-metric:**
1. Determine user's age group (young <40, middle 40-59, senior 60-74, elderly 75+)
2. Look up age-specific ranges from schema
3. Score raw value against ranges:
   - **Optimal range:** 80-100 points (linear interpolation)
   - **Acceptable range:** 50-80 points
   - **Poor range:** 0-50 points
4. If raw value is nil → score = 0 for that sub-metric

**For each pillar:**
- Weighted average of sub-metric scores
- Sleep = (duration×40% + restorative×30% + efficiency×20% + awake×10%)
- Movement = (minutes×40% + steps×30% + calories×30%)
- Stress = (HRV×40% + RHR×40% + breathing×20%)

**Total vitality:**
- Weighted average of pillar scores
- Total = (Sleep×33% + Movement×33% + Stress×34%)

**Example:**
```
Age: 45 (middle age group)

Sub-metric scores:
  Sleep Duration: 7.6h → 85/100 (in optimal range for middle age)
  Restorative: nil → 0/100 (missing)
  Steps: 8800 → 90/100 (optimal for middle age)
  HRV: 53.5ms → 78/100 (acceptable high for middle age)
  RHR: 58 → 88/100 (optimal for middle age)

Pillar scores:
  Sleep = (85×0.4 + 0×0.3 + 0×0.2 + 0×0.1) = 34/100 (partial data)
  Movement = (0×0.4 + 90×0.3 + 0×0.3) = 27/100 (partial data)
  Stress = (78×0.4 + 88×0.4 + 0×0.2) = 66.4/100

Total vitality = (34×0.33 + 27×0.33 + 66.4×0.34) = 42.7 ≈ 43/100
```

**Output:** `VitalitySnapshot` (total, pillar scores, sub-metric scores)

---

### Step 5: UI Display

**Input:** `VitalitySnapshot`

**Displayed in `RiskResultsView`:**

```
┌─────────────────────────────────────────────┐
│         Your Vitality Score                  │
│                                              │
│               43 / 100                       │
│                                              │
│  Your recommended goal: 85/100 (based on    │
│  moderate cardiovascular risk)              │
│                                              │
│  Breakdown by Pillar:                        │
│  😴 Sleep:     34/100                        │
│  🏃 Movement:  27/100                        │
│  💚 Stress:    66/100                        │
│                                              │
│  Last synced: 2 hours ago                    │
│  Data source: Whoop                          │
│  [ Refresh Now ]                             │
└─────────────────────────────────────────────┘
```

---

## Data Freshness & Sync Schedule

### Sync Timing
- **Initial sync:** On first wearable connection (last 30 days)
- **Automatic sync:** Daily at 6 AM local time
- **Manual sync:** User taps "Refresh Now" button
- **Background sync:** iOS background fetch (when app not open)

### Data Lag
- **Best case:** 15 minutes (device → ROOK → Miya)
- **Typical:** 1-4 hours (device sync delay)
- **Worst case:** 24 hours (user didn't sync device overnight)

**User expectation setting:**
> "Your vitality score updates daily based on data from your wearable. Last synced: 2 hours ago."

---

## Fallback Logic Flow

### HRV Fallback
```
1. Check sleep_summary.hrv_sdnn_ms_double
   ✓ Found → Use SDNN, set hrvType="sdnn"
   ✗ Not found → Continue

2. Check sleep_summary.hrv_rmssd_ms_double
   ✓ Found → Use RMSSD, set hrvType="rmssd"
   ✗ Not found → Continue

3. Check physical_summary.hrv_sdnn_avg_ms
   ✓ Found → Use SDNN, set hrvType="sdnn"
   ✗ Not found → Continue

4. Check physical_summary.hrv_rmssd_avg_ms
   ✓ Found → Use RMSSD, set hrvType="rmssd"
   ✗ Not found → hrvMs=nil, hrvType=nil
```

### Resting Heart Rate Fallback
```
1. Check sleep_summary.hr_resting_bpm_int
   ✓ Found → Use sleep RHR (most accurate)
   ✗ Not found → Continue

2. Check physical_summary.hr_resting_bpm_int
   ✓ Found → Use physical RHR (acceptable)
   ✗ Not found → restingHeartRate=nil
```

### Movement Minutes Fallback
```
1. Check physical_summary.active_minutes_total_int
   ✓ Found → Use total (pre-computed)
   ✗ Not found → Continue

2. Fetch activity_sessions for date
   ✓ Sessions found → Aggregate "moderate" + "vigorous" durations
   ✗ Not found → movementMinutes=nil
```

---

## Error Handling

### Network Errors
```
ROOK API call fails
  ↓
Retry 3 times with exponential backoff
  ↓
If still failing:
  - Show error: "Unable to sync data. Check your connection."
  - Use cached data (last successful sync)
  - Schedule retry in 1 hour
```

### Missing Data
```
Required field missing (sleep duration, steps)
  ↓
Log warning: "Day X skipped: missing sleep_duration"
  ↓
Continue with other days
  ↓
If >50% of days missing required fields:
  - Show warning: "Incomplete data. Connect device more consistently."
  - Still compute score from available days
```

### Invalid Data
```
Value out of range (e.g., sleep_duration = -100)
  ↓
Log error: "Invalid value for field X on day Y"
  ↓
Treat as nil for that day
  ↓
Continue with other days
```

---

## Performance Optimization

### Caching Strategy
```
┌──────────────────────────────────────────┐
│  Local SQLite Cache                       │
│  • Store raw ROOK JSON per day           │
│  • Store computed VitalityRawMetrics     │
│  • TTL: 24 hours                          │
│  • Size limit: 30 days × 2KB ≈ 60KB     │
└──────────────────────────────────────────┘

On sync request:
  1. Check cache for date range
  2. If cached & fresh (<24h) → use cache
  3. If expired or missing → fetch from ROOK
  4. Update cache with new data
```

### Batch API Calls
```
Don't: 30 individual calls (1 per day)
  GET /sleep/user/2025-01-01
  GET /sleep/user/2025-01-02
  ...
  GET /sleep/user/2025-01-30

Do: 1 bulk call with date range
  GET /sleep/user?start=2025-01-01&end=2025-01-30
```

### Background Sync
```
Use iOS BackgroundTasks framework:
  - Register daily refresh task
  - Execute at optimal time (device charging, WiFi)
  - Limit to 30 seconds execution time
  - Gracefully handle early termination
```

---

## Testing Data Flow

### End-to-End Test
```
1. Mock ROOK API responses (30 days of data)
2. Call ROOKAPIClient.fetchSleepSummary()
3. Call ROOKDataAdapter.mapToVitalityRawMetrics()
4. Call VitalityMetricsBuilder.fromWindow()
5. Call VitalityScoringEngine.score()
6. Assert VitalitySnapshot values
7. Check UI displays correct scores
```

### Integration Test Points
```
✓ ROOK API → ROOKSleepSummary (decoding)
✓ ROOKSleepSummary → VitalityRawMetrics (transformation)
✓ [VitalityRawMetrics] → VitalityRawMetrics (aggregation)
✓ VitalityRawMetrics → VitalitySnapshot (scoring)
✓ VitalitySnapshot → UI (display)
```

---

## Summary

**Data flows through 5 main steps:**

1. **Fetch** from ROOK API (sleep, physical summaries)
2. **Transform** via `ROOKDataAdapter` (apply mapping rules)
3. **Aggregate** via `VitalityMetricsBuilder` (7-30 day average)
4. **Score** via `VitalityScoringEngine` (age-specific ranges)
5. **Display** in `RiskResultsView` UI (total + pillar scores)

**Key principles:**
- ✅ Preserve nil (don't substitute zeros)
- ✅ Apply locked transformation rules (no RMSSD→SDNN conversion)
- ✅ Handle partial data gracefully (scoring works with missing fields)
- ✅ Cache aggressively (reduce API calls)
- ✅ Fail gracefully (network errors, missing days)

**The flow is deterministic and testable at every step! 🎯**

