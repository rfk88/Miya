# ROOK to Miya Vitality Mapping

**Version:** 1.0  
**Date:** December 14, 2025  
**Status:** 🔒 Locked for Implementation

---

## Overview

This document defines the canonical mapping from ROOK Health API data structures to Miya's vitality scoring system. All implementation must follow these exact rules.

**ROOK API Integration:** ROOK provides wearable data aggregation from multiple sources (Whoop, Apple Health, Fitbit, etc.) via normalized JSON endpoints.

**Miya Vitality System:** Requires 10 sub-metrics across 3 pillars (Sleep, Movement, Stress) to compute age-adjusted vitality scores (0-100).

---

## Complete Field Mapping

| Miya Field | Unit | ROOK JSON Path Candidates | Preferred Path | Transform | Fallback Rule | Notes |
|------------|------|---------------------------|----------------|-----------|---------------|-------|
| **sleepDurationHours** | hours (Double?) | `sleep_summary.sleep_duration_seconds_int` | `sleep_summary.sleep_duration_seconds_int` | `value / 3600.0` | Set `nil` if missing | Primary metric; day included in window with nil value |
| **restorativeSleepPercent** | % (Double, 0-100) | `sleep_summary.rem_sleep_duration_seconds_int`<br>`sleep_summary.deep_sleep_duration_seconds_int`<br>`sleep_summary.sleep_duration_seconds_int` | Calculate from REM + Deep | `((rem + deep) / total) * 100` | Set `nil` if any component missing | Quality indicator; nice-to-have |
| **sleepEfficiencyPercent** | % (Double, 0-100) | `sleep_summary.sleep_efficiency_1_100_score_int`<br>`sleep_summary.sleep_duration_seconds_int`<br>`sleep_summary.time_in_bed_seconds_int` | `sleep_efficiency_1_100_score_int` if available, else calculate | If score: use directly<br>Else: `(sleep_duration / time_in_bed) * 100` | Set `nil` if calculation impossible | Prefer ROOK's computed score |
| **awakePercent** | % (Double, 0-100) | `sleep_summary.time_awake_during_sleep_seconds_int`<br>`sleep_summary.time_in_bed_seconds_int`<br>`sleep_summary.sleep_duration_seconds_int` | `time_awake_during_sleep_seconds_int / time_in_bed_seconds_int` | `(awake / time_in_bed) * 100` | If `time_in_bed` missing, use `sleep_duration` as denominator | Fragmentation metric |
| **movementMinutes** | minutes (Double) | `physical_summary.active_minutes_total_int`<br>`physical_summary.moderate_vigorous_activity_minutes`<br>`activity_sessions[].duration_seconds_int` where `type = "moderate" OR "vigorous"` | `active_minutes_total_int` | Use directly | If missing, aggregate from sessions<br>If still missing, set `nil` | Can be `nil` initially |
| **steps** | count (Int?) | `physical_summary.steps_int` | `physical_summary.steps_int` | Use directly | Set `nil` if missing | Day included in window with nil value |
| **activeCalories** | kcal (Double) | `physical_summary.active_calories_kcal_double`<br>`physical_summary.active_energy_burned_kcal` | `active_calories_kcal_double` | Use directly | Set `nil` if missing<br>Do NOT use total calories as substitute | Can be `nil` initially |
| **hrvMs** | ms (Double) | `sleep_summary.hrv_sdnn_ms_double`<br>`sleep_summary.hrv_rmssd_ms_double`<br>`physical_summary.hrv_sdnn_avg_ms`<br>`physical_summary.hrv_rmssd_avg_ms` | SDNN if present, else RMSSD | Use whichever is available<br>Store which type in `hrvType` field | Set `nil` if both missing<br>Prefer sleep summary over physical | Must have EITHER HRV OR RHR |
| **restingHeartRate** | bpm (Double?) | `sleep_summary.hr_resting_bpm_int`<br>`physical_summary.hr_resting_bpm_int` | `sleep_summary.hr_resting_bpm_int` | Convert Int to Double | Fallback to physical summary<br>If both missing, set `nil` | Must have EITHER HRV OR RHR |
| **breathingRate** | breaths/min (Double) | `sleep_summary.breaths_avg_per_min_int`<br>`sleep_summary.breathing_rate_avg` | `breaths_avg_per_min_int` | Use directly (already in breaths/min) | Set `nil` if missing | Nice-to-have; can be `nil` |

---

## Missing Data Handling Strategy

**Policy:** Include all days in aggregation window, preserve nil for missing metrics.

**Rationale:**
- The scoring engine handles nil gracefully (scores 0 for that sub-metric)
- VitalityMetricsBuilder.fromWindow() averages only non-nil values
- Including days with partial data is better than excluding them entirely
- Example: Day has sleep but no steps → include day, average sleep, steps=nil

**Never substitute 0 for missing data.** Always use nil.

---

## Locked Transformation Rules

### A. HRV Standardization

**Rule:**
```
1. Primary: SDNN in ms if present
2. Secondary: RMSSD in ms if SDNN missing
3. Do NOT convert RMSSD to SDNN (no approximation formulas)
4. Store whichever value we have in `hrvMs`
5. Record which type was used in a side field: `hrvType = "sdnn" or "rmssd"`
```

**Implementation:**
```swift
// Pseudocode
if let sdnn = rook.sleep_summary.hrv_sdnn_ms_double {
    rawMetrics.hrvMs = sdnn
    rawMetrics.hrvType = "sdnn"
} else if let rmssd = rook.sleep_summary.hrv_rmssd_ms_double {
    rawMetrics.hrvMs = rmssd
    rawMetrics.hrvType = "rmssd"
} else if let sdnn = rook.physical_summary.hrv_sdnn_avg_ms {
    rawMetrics.hrvMs = sdnn
    rawMetrics.hrvType = "sdnn"
} else if let rmssd = rook.physical_summary.hrv_rmssd_avg_ms {
    rawMetrics.hrvMs = rmssd
    rawMetrics.hrvType = "rmssd"
} else {
    rawMetrics.hrvMs = nil
    rawMetrics.hrvType = nil
}
```

**Rationale:**
- SDNN and RMSSD measure different aspects of HRV
- Converting between them introduces error
- Scoring engine can work with either (both indicate autonomic function)
- Tracking which type allows future refinement

---

### B. Sleep Duration

**Rule:**
```
sleepDurationHours = sleep_duration_seconds_int / 3600.0
```

**Implementation:**
```swift
if let seconds = rook.sleep_summary.sleep_duration_seconds_int {
    rawMetrics.sleepDurationHours = Double(seconds) / 3600.0
} else {
    rawMetrics.sleepDurationHours = nil
    // Skip this day from scoring (sleep duration is required)
}
```

**Rationale:**
- ROOK provides sleep duration in seconds (integer)
- Miya expects hours (double precision for accuracy)
- Simple division, no rounding until display

---

### C. Restorative Sleep Percent

**Rule:**
```
restorativeSleepPercent = ((rem_sleep_duration_seconds_int + deep_sleep_duration_seconds_int) 
                          / sleep_duration_seconds_int) * 100
```

**Implementation:**
```swift
if let rem = rook.sleep_summary.rem_sleep_duration_seconds_int,
   let deep = rook.sleep_summary.deep_sleep_duration_seconds_int,
   let total = rook.sleep_summary.sleep_duration_seconds_int,
   total > 0 {
    let restorativeSeconds = Double(rem + deep)
    rawMetrics.restorativeSleepPercent = (restorativeSeconds / Double(total)) * 100.0
} else {
    rawMetrics.restorativeSleepPercent = nil
    // Continue scoring without this metric
}
```

**Rationale:**
- REM + Deep sleep = restorative sleep phases
- Light sleep and awake time are not restorative
- Percent allows age-specific interpretation by scoring engine

---

### D. Sleep Efficiency Percent

**Rule:**
```
IF sleep_efficiency_1_100_score_int exists:
    USE that value directly (already a percent)
ELSE:
    sleepEfficiencyPercent = (sleep_duration_seconds_int / time_in_bed_seconds_int) * 100
```

**Implementation:**
```swift
if let efficiency = rook.sleep_summary.sleep_efficiency_1_100_score_int {
    rawMetrics.sleepEfficiencyPercent = Double(efficiency)
} else if let duration = rook.sleep_summary.sleep_duration_seconds_int,
          let timeInBed = rook.sleep_summary.time_in_bed_seconds_int,
          timeInBed > 0 {
    rawMetrics.sleepEfficiencyPercent = (Double(duration) / Double(timeInBed)) * 100.0
} else {
    rawMetrics.sleepEfficiencyPercent = nil
    // Continue scoring without this metric
}
```

**Rationale:**
- Some ROOK sources (e.g., Whoop) provide pre-computed efficiency scores
- Others provide raw seconds; we compute the ratio
- Efficiency = time asleep / time in bed (higher is better)

---

### E. Awake Percent

**Rule:**
```
awakePercent = (time_awake_during_sleep_seconds_int / time_in_bed_seconds_int) * 100

IF time_in_bed_seconds_int is missing:
    awakePercent = (time_awake_during_sleep_seconds_int / sleep_duration_seconds_int) * 100
```

**Implementation:**
```swift
if let awake = rook.sleep_summary.time_awake_during_sleep_seconds_int {
    let denominator = rook.sleep_summary.time_in_bed_seconds_int 
                      ?? rook.sleep_summary.sleep_duration_seconds_int
    if let denom = denominator, denom > 0 {
        rawMetrics.awakePercent = (Double(awake) / Double(denom)) * 100.0
    } else {
        rawMetrics.awakePercent = nil
    }
} else {
    rawMetrics.awakePercent = nil
}
```

**Rationale:**
- Awake time during sleep = fragmentation (lower is better)
- Prefer time_in_bed as denominator (total opportunity for sleep)
- Fallback to sleep_duration if time_in_bed unavailable

---

### F. Breathing Rate

**Rule:**
```
breathingRate = breaths_avg_per_min_int (already in breaths/min)
```

**Implementation:**
```swift
if let br = rook.sleep_summary.breaths_avg_per_min_int {
    rawMetrics.breathingRate = Double(br)
} else {
    rawMetrics.breathingRate = nil
    // Nice-to-have; scoring continues without it
}
```

**Rationale:**
- Measured during sleep (most stable)
- Already in correct units (breaths/min)
- Optional metric for stress pillar

---

### G. Resting Heart Rate

**Rule:**
```
restingHeartRate = hr_resting_bpm_int (already in bpm)

Prefer sleep_summary.hr_resting_bpm_int
Fallback to physical_summary.hr_resting_bpm_int
```

**Implementation:**
```swift
if let rhr = rook.sleep_summary.hr_resting_bpm_int {
    rawMetrics.restingHeartRate = Double(rhr)
} else if let rhr = rook.physical_summary.hr_resting_bpm_int {
    rawMetrics.restingHeartRate = Double(rhr)
} else {
    rawMetrics.restingHeartRate = nil
    // Must have EITHER HRV or RHR for stress scoring
}
```

**Rationale:**
- Sleep-based RHR is more accurate (resting state guaranteed)
- Daily/physical RHR is acceptable fallback
- Already in bpm, no conversion needed

---

### H. Steps

**Rule:**
```
steps = physical_summary.steps_int (daily total)
```

**Implementation:**
```swift
if let stepsCount = rook.physical_summary.steps_int {
    rawMetrics.steps = stepsCount
} else {
    rawMetrics.steps = nil
    // Skip this day from scoring (steps are required)
}
```

**Rationale:**
- Simple daily count, no aggregation needed
- ROOK normalizes across sources
- Required for Movement pillar scoring

---

### I. Movement Minutes

**Rule:**
```
movementMinutes = physical_summary.active_minutes_total_int

IF missing:
    Aggregate from activity_sessions where type = "moderate" OR "vigorous"
    movementMinutes = SUM(session.duration_seconds_int) / 60

IF still missing:
    Set nil (can score without this metric)
```

**Implementation:**
```swift
if let activeMin = rook.physical_summary.active_minutes_total_int {
    rawMetrics.movementMinutes = Double(activeMin)
} else if let sessions = rook.activity_sessions {
    let totalSeconds = sessions
        .filter { $0.type == "moderate" || $0.type == "vigorous" }
        .compactMap { $0.duration_seconds_int }
        .reduce(0, +)
    if totalSeconds > 0 {
        rawMetrics.movementMinutes = Double(totalSeconds) / 60.0
    } else {
        rawMetrics.movementMinutes = nil
    }
} else {
    rawMetrics.movementMinutes = nil
    // Can be nil; scoring uses steps + active calories if available
}
```

**Rationale:**
- Prefer ROOK's pre-computed total (already filtered by intensity)
- Session aggregation as fallback (common in Apple Health)
- Not all wearables track "active minutes" separately

---

### J. Active Calories

**Rule:**
```
activeCalories = physical_summary.active_calories_kcal_double

IF missing:
    Set nil

DO NOT use total_calories as a substitute (includes BMR)
```

**Implementation:**
```swift
if let activeCal = rook.physical_summary.active_calories_kcal_double {
    rawMetrics.activeCalories = activeCal
} else {
    rawMetrics.activeCalories = nil
    // Can be nil; scoring uses steps + movement minutes if available
}
```

**Rationale:**
- Active calories = calories burned above BMR
- Total calories include basal metabolic rate (not useful for activity assessment)
- Not all wearables distinguish active vs. total calories

---

## ROOK API Structure Reference

### Sleep Summary Endpoint
**Path:** `/v1/summaries/sleep/{user_id}/{date}`

**Relevant Fields:**
```json
{
  "sleep_duration_seconds_int": 28800,
  "time_in_bed_seconds_int": 30600,
  "time_awake_during_sleep_seconds_int": 1800,
  "rem_sleep_duration_seconds_int": 6480,
  "deep_sleep_duration_seconds_int": 7200,
  "light_sleep_duration_seconds_int": 14400,
  "sleep_efficiency_1_100_score_int": 94,
  "hrv_sdnn_ms_double": 55.3,
  "hrv_rmssd_ms_double": 48.7,
  "hr_resting_bpm_int": 58,
  "breaths_avg_per_min_int": 14
}
```

### Physical Summary Endpoint
**Path:** `/v1/summaries/physical/{user_id}/{date}`

**Relevant Fields:**
```json
{
  "steps_int": 9234,
  "active_minutes_total_int": 47,
  "active_calories_kcal_double": 487.3,
  "total_calories_kcal_double": 2340.8,
  "hr_resting_bpm_int": 60,
  "hrv_sdnn_avg_ms": 52.1,
  "hrv_rmssd_avg_ms": 46.2
}
```

### Activity Sessions Array
**Path:** `/v1/events/physical/{user_id}` (filtered by date)

**Relevant Fields:**
```json
[
  {
    "type": "moderate",
    "duration_seconds_int": 1800,
    "calories_burned_kcal": 180.5
  },
  {
    "type": "vigorous",
    "duration_seconds_int": 1200,
    "calories_burned_kcal": 220.3
  }
]
```

---

## Data Quality Notes

### 1. Sleep Metrics
- **Whoop:** Excellent for HRV, sleep stages, and breathing rate
- **Apple Watch:** Good for duration and efficiency; HRV less reliable
- **Fitbit:** Good for stages; may not provide SDNN (only RMSSD)
- **Oura:** Excellent for all sleep metrics including HRV

**Quality hierarchy (sleep):** Whoop ≈ Oura > Garmin > Fitbit > Apple Watch

### 2. Movement Metrics
- **Apple Health:** Comprehensive steps and activity minutes
- **Fitbit:** Excellent step tracking, clear active minutes
- **Garmin:** Very detailed activity sessions
- **Whoop:** Limited movement data (strain score, not granular metrics)

**Quality hierarchy (movement):** Garmin > Fitbit > Apple Health > Whoop

### 3. HRV Metrics
- **SDNN preferred:** Better reflects overall autonomic function
- **RMSSD acceptable:** Common on consumer devices, correlates well
- **Whoop/Oura:** Most reliable HRV measurements
- **Apple Watch:** HRV available but less consistent

**Quality hierarchy (HRV):** Whoop ≈ Oura > Garmin > Polar > Apple Watch > Fitbit

### 4. Missing Data Handling
- **Partial days:** If user takes off device mid-day, steps/calories may be incomplete
- **Sleep gaps:** User may not wear device overnight
- **Sync delays:** ROOK data may lag 1-24 hours depending on source
- **Multi-device conflicts:** User may have multiple sources; ROOK deduplicates

---

## Coverage Expectations for Testing

### Minimum Viable Coverage for Scoring
**Required fields (must have):**
- ✅ `sleepDurationHours` (for Sleep pillar)

**Optional fields (scoring degrades gracefully):**
- `steps` (Movement pillar; if nil, Movement uses other sub-metrics or scores 0)
- `hrvMs` and `restingHeartRate` (Stress pillar; both can be nil, stress scores 0)

**Scoring behavior when minimum not met:**
- If Sleep duration missing → day included but Sleep pillar scores 0
- If Steps missing → Movement pillar uses activeCalories/movementMinutes if available, else scores 0
- If both HRV and RHR missing → Stress pillar scores 0 for that day (scoring still runs)

### Nice-to-Have Coverage
**Improves scoring accuracy:**
- ✅ `restorativeSleepPercent` (Sleep quality indicator)
- ✅ `sleepEfficiencyPercent` (Sleep quality indicator)
- ✅ `awakePercent` (Sleep fragmentation indicator)
- ✅ `breathingRate` (Stress indicator, optimal range scoring)

**Scoring behavior when nice-to-have missing:**
- Sleep sub-metrics still score based on duration
- Breathing rate: Stress pillar uses HRV + RHR only

### Can Be Nil Initially
**Optional, not critical for V1:**
- `movementMinutes` (Movement pillar uses steps + active calories)
- `activeCalories` (Movement pillar uses steps + movement minutes)

**Scoring behavior when optional missing:**
- Movement pillar computes weighted average from available sub-metrics
- If both movement minutes and active calories missing, pillar uses steps only (100% weight)

### Testing Scenarios

#### Scenario 1: Full Coverage (Ideal)
**Device:** Whoop  
**Coverage:** All 10 metrics available  
**Expected:** Full vitality score, all pillars, all sub-metrics  

#### Scenario 2: Minimum Coverage (Viable)
**Device:** Basic fitness tracker  
**Coverage:** Sleep duration, steps, resting heart rate  
**Expected:** Vitality score with partial pillar data  
**Notes:** Sleep pillar scores on duration only; Movement on steps only; Stress on RHR only  

#### Scenario 3: Missing Stress Data (Degraded)
**Device:** Simple pedometer  
**Coverage:** Sleep duration, steps, no HRV or RHR  
**Expected:** Sleep and Movement pillars only, Stress pillar = 0  
**Notes:** Total vitality = (Sleep × 33% + Movement × 33% + 0 × 34%)  

#### Scenario 4: Missing Sleep Data (Blocked)
**Device:** Worn only during day  
**Coverage:** Steps, active calories, but no sleep data  
**Expected:** Skip day from scoring  
**Notes:** Sleep is a core pillar; can't compute vitality without it  

---

## Implementation Checklist

### Phase 1: Basic Integration
- [ ] Add ROOK SDK to iOS project
- [ ] Implement authentication flow (ROOK user provisioning)
- [ ] Create `ROOKDataAdapter` struct with mapping functions
- [ ] Add `hrvType: String?` to `VitalityRawMetrics`
- [ ] Fetch sleep summary for date range
- [ ] Fetch physical summary for date range
- [ ] Map to `VitalityRawMetrics` using rules above
- [ ] Test with Whoop sample data (full coverage)
- [ ] Test with Apple Health sample data (partial coverage)

### Phase 2: Quality & Fallbacks
- [ ] Implement fallback logic (HRV: SDNN → RMSSD)
- [ ] Implement fallback logic (RHR: sleep → physical)
- [ ] Implement fallback logic (Movement minutes: summary → sessions)
- [ ] Handle missing data gracefully (nil checks)
- [ ] Log data quality metrics per source
- [ ] Add source tracking (which wearable provided data)

### Phase 3: Multi-Day Aggregation
- [ ] Fetch 7-30 day windows from ROOK
- [ ] Use existing `VitalityMetricsBuilder.fromWindow()` logic
- [ ] Average fields per transformation rules
- [ ] Handle gaps in data (some days missing)
- [ ] Validate against known-good test data

### Phase 4: UI & Sync
- [ ] Replace CSV/JSON import with ROOK sync
- [ ] Add "Connect Wearable" flow (ROOK device linking)
- [ ] Show last sync timestamp in UI
- [ ] Add manual refresh button
- [ ] Background sync (daily at 6 AM)

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-12-14 | Initial locked mapping | Miya Team |

---

## Notes for Developers

1. **Do not deviate from these rules without updating this document first.**
2. **HRV conversion:** Do NOT implement RMSSD → SDNN approximations; store raw values and track type.
3. **Nil handling:** The scoring engine is designed to handle partial data; do not substitute zeros for missing values.
4. **Unit consistency:** Always convert to Miya's expected units before passing to `VitalityRawMetrics`.
5. **Testing:** Use real ROOK sample data from multiple sources (Whoop, Apple, Fitbit) to validate transformations.
6. **Logging:** Log which fields are missing and why for each day/user during beta testing.

**This document is the single source of truth for ROOK integration. 🔒**

