# ROOK Integration Quick Reference

**For full details, see:** [ROOK_TO_MIYA_MAPPING.md](./ROOK_TO_MIYA_MAPPING.md)

---

## 🔒 Critical Rules

### 1. HRV: Do NOT Convert
```swift
// ✅ CORRECT: Store whichever value exists, track type
if let sdnn = rook.sleep_summary.hrv_sdnn_ms_double {
    raw.hrvMs = sdnn
    raw.hrvType = "sdnn"
} else if let rmssd = rook.sleep_summary.hrv_rmssd_ms_double {
    raw.hrvMs = rmssd
    raw.hrvType = "rmssd"
}

// ❌ WRONG: Do not convert RMSSD to SDNN
// raw.hrvMs = rmssd * 1.3  // NO!
```

### 2. Active Calories: Do NOT Use Total
```swift
// ✅ CORRECT: Only active calories
raw.activeCalories = rook.physical_summary.active_calories_kcal_double

// ❌ WRONG: Do not substitute total calories
// raw.activeCalories = rook.physical_summary.total_calories_kcal_double  // NO!
```

### 3. Missing Data: Use nil, Not Zero
```swift
// ✅ CORRECT: Preserve nil when data missing
if let steps = rook.physical_summary.steps_int {
    raw.steps = steps
} else {
    raw.steps = nil  // Scoring engine handles this
}

// ❌ WRONG: Do not substitute zero
// raw.steps = rook.physical_summary.steps_int ?? 0  // NO!
```

---

## 📊 Field Mapping Cheat Sheet

| Miya Field | ROOK Path | Transform | Required? |
|------------|-----------|-----------|-----------|
| sleepDurationHours | `sleep_summary.sleep_duration_seconds_int` | `/ 3600` | ✅ Yes |
| steps | `physical_summary.steps_int` | direct | ✅ Yes |
| hrvMs | `sleep_summary.hrv_sdnn_ms_double` (or rmssd) | direct + track type | ⚠️ HRV OR RHR |
| restingHeartRate | `sleep_summary.hr_resting_bpm_int` | direct | ⚠️ HRV OR RHR |
| restorativeSleepPercent | `(rem + deep) / total * 100` | calculate | 🟢 Nice |
| sleepEfficiencyPercent | `sleep_efficiency_1_100_score_int` or calculate | direct or calc | 🟢 Nice |
| awakePercent | `time_awake / time_in_bed * 100` | calculate | 🟢 Nice |
| breathingRate | `sleep_summary.breaths_avg_per_min_int` | direct | 🟢 Nice |
| movementMinutes | `physical_summary.active_minutes_total_int` | direct or aggregate | 🔵 Optional |
| activeCalories | `physical_summary.active_calories_kcal_double` | direct | 🔵 Optional |

**Legend:**
- ✅ **Required:** Must have for scoring
- ⚠️ **Either/Or:** Need at least one
- 🟢 **Nice-to-have:** Improves scoring accuracy
- 🔵 **Optional:** Can be nil initially

---

## 🧮 Calculation Formulas

### Restorative Sleep %
```swift
let rem = rook.sleep_summary.rem_sleep_duration_seconds_int
let deep = rook.sleep_summary.deep_sleep_duration_seconds_int
let total = rook.sleep_summary.sleep_duration_seconds_int

restorativeSleep = ((rem + deep) / total) * 100
```

### Sleep Efficiency %
```swift
// Prefer ROOK's score if available
if let score = rook.sleep_summary.sleep_efficiency_1_100_score_int {
    efficiency = score
} else {
    // Calculate from duration / time in bed
    efficiency = (sleep_duration / time_in_bed) * 100
}
```

### Awake %
```swift
// Prefer time_in_bed as denominator
let awake = rook.sleep_summary.time_awake_during_sleep_seconds_int
let denominator = rook.sleep_summary.time_in_bed_seconds_int 
                  ?? rook.sleep_summary.sleep_duration_seconds_int

awakePercent = (awake / denominator) * 100
```

### Movement Minutes (Fallback)
```swift
// Primary: Use ROOK's total
if let total = rook.physical_summary.active_minutes_total_int {
    movementMinutes = total
} else {
    // Fallback: Aggregate from sessions
    let seconds = sessions
        .filter { $0.type == "moderate" || $0.type == "vigorous" }
        .compactMap { $0.duration_seconds_int }
        .reduce(0, +)
    movementMinutes = seconds / 60
}
```

---

## 🎯 Minimum Coverage for Scoring

### Can Score With:
```
✅ Sleep Duration
✅ Steps
✅ At least one of: HRV or Resting Heart Rate
```

### Cannot Score Without:
```
❌ Sleep Duration (skip day)
❌ Steps (skip day)
❌ Both HRV and RHR missing (stress pillar = 0)
```

---

## 🧪 Testing Checklist

### Test Case 1: Full Coverage (Whoop)
- [ ] All 10 metrics present
- [ ] HRV is SDNN
- [ ] Breathing rate available
- [ ] Expected: Full vitality score

### Test Case 2: Minimal (Apple Health)
- [ ] Sleep duration, steps, RHR only
- [ ] HRV missing
- [ ] Expected: Partial scoring, stress uses RHR

### Test Case 3: HRV Fallback (Fitbit)
- [ ] SDNN missing
- [ ] RMSSD available
- [ ] Expected: RMSSD used, `hrvType = "rmssd"`

### Test Case 4: Movement Fallback (Apple)
- [ ] Active minutes missing
- [ ] Activity sessions available
- [ ] Expected: Aggregate from sessions

### Test Case 5: Degraded (No Sleep)
- [ ] Steps and HRV only
- [ ] Sleep data missing
- [ ] Expected: Skip day, log warning

---

## 🔗 ROOK API Endpoints

### Sleep Summary (Per Day)
```
GET /v1/summaries/sleep/{user_id}/{date}
```

**Key Fields:**
- `sleep_duration_seconds_int` → sleepDurationHours
- `hrv_sdnn_ms_double` → hrvMs
- `hr_resting_bpm_int` → restingHeartRate
- `breaths_avg_per_min_int` → breathingRate
- Sleep stage seconds for restorative %

### Physical Summary (Per Day)
```
GET /v1/summaries/physical/{user_id}/{date}
```

**Key Fields:**
- `steps_int` → steps
- `active_minutes_total_int` → movementMinutes
- `active_calories_kcal_double` → activeCalories

### Activity Events (Date Range)
```
GET /v1/events/physical/{user_id}?start_date=X&end_date=Y
```

**Key Fields:**
- `type` (moderate/vigorous)
- `duration_seconds_int` (for movement minutes fallback)

---

## 🚨 Common Pitfalls

### ❌ Don't Do This:
```swift
// 1. Converting HRV types
hrvMs = rmssd * 1.3  // NO! Store raw value

// 2. Using total calories
activeCalories = total_calories  // NO! Active only

// 3. Substituting zeros
steps = rook.steps ?? 0  // NO! Use nil

// 4. Wrong time units
sleepHours = seconds / 60  // NO! Divide by 3600

// 5. Ignoring missing denominators
efficiency = duration / 0  // NO! Check time_in_bed first
```

### ✅ Do This Instead:
```swift
// 1. Store raw HRV with type
if let sdnn = sdnn { hrvMs = sdnn; hrvType = "sdnn" }
else if let rmssd = rmssd { hrvMs = rmssd; hrvType = "rmssd" }

// 2. Active calories only, or nil
activeCalories = rook.active_calories_kcal_double

// 3. Preserve nil
steps = rook.steps_int

// 4. Correct conversion
sleepHours = Double(seconds) / 3600.0

// 5. Guard against zero division
guard timeInBed > 0 else { efficiency = nil; return }
```

---

## 📝 Implementation Template

```swift
struct ROOKDataAdapter {
    static func mapToVitalityRawMetrics(
        age: Int,
        sleepSummary: ROOKSleepSummary?,
        physicalSummary: ROOKPhysicalSummary?
    ) -> VitalityRawMetrics {
        
        // SLEEP DURATION (required)
        let sleepHours: Double? = sleepSummary?.sleep_duration_seconds_int.map { Double($0) / 3600.0 }
        
        // RESTORATIVE SLEEP % (nice-to-have)
        let restorativePct: Double? = {
            guard let rem = sleepSummary?.rem_sleep_duration_seconds_int,
                  let deep = sleepSummary?.deep_sleep_duration_seconds_int,
                  let total = sleepSummary?.sleep_duration_seconds_int,
                  total > 0 else { return nil }
            return (Double(rem + deep) / Double(total)) * 100.0
        }()
        
        // SLEEP EFFICIENCY % (nice-to-have)
        let efficiencyPct: Double? = {
            if let score = sleepSummary?.sleep_efficiency_1_100_score_int {
                return Double(score)
            } else if let duration = sleepSummary?.sleep_duration_seconds_int,
                      let timeInBed = sleepSummary?.time_in_bed_seconds_int,
                      timeInBed > 0 {
                return (Double(duration) / Double(timeInBed)) * 100.0
            }
            return nil
        }()
        
        // AWAKE % (nice-to-have)
        let awakePct: Double? = {
            guard let awake = sleepSummary?.time_awake_during_sleep_seconds_int else { return nil }
            let denom = sleepSummary?.time_in_bed_seconds_int ?? sleepSummary?.sleep_duration_seconds_int
            guard let denominator = denom, denominator > 0 else { return nil }
            return (Double(awake) / Double(denominator)) * 100.0
        }()
        
        // HRV (required: HRV OR RHR)
        let (hrv, hrvType): (Double?, String?) = {
            if let sdnn = sleepSummary?.hrv_sdnn_ms_double {
                return (sdnn, "sdnn")
            } else if let rmssd = sleepSummary?.hrv_rmssd_ms_double {
                return (rmssd, "rmssd")
            } else if let sdnn = physicalSummary?.hrv_sdnn_avg_ms {
                return (sdnn, "sdnn")
            } else if let rmssd = physicalSummary?.hrv_rmssd_avg_ms {
                return (rmssd, "rmssd")
            }
            return (nil, nil)
        }()
        
        // RESTING HEART RATE (required: HRV OR RHR)
        let rhr: Double? = sleepSummary?.hr_resting_bpm_int.map { Double($0) }
                           ?? physicalSummary?.hr_resting_bpm_int.map { Double($0) }
        
        // BREATHING RATE (nice-to-have)
        let br: Double? = sleepSummary?.breaths_avg_per_min_int.map { Double($0) }
        
        // STEPS (required)
        let steps: Int? = physicalSummary?.steps_int
        
        // MOVEMENT MINUTES (optional)
        let movementMin: Double? = physicalSummary?.active_minutes_total_int.map { Double($0) }
        
        // ACTIVE CALORIES (optional)
        let activeCal: Double? = physicalSummary?.active_calories_kcal_double
        
        return VitalityRawMetrics(
            age: age,
            sleepDurationHours: sleepHours,
            restorativeSleepPercent: restorativePct,
            sleepEfficiencyPercent: efficiencyPct,
            awakePercent: awakePct,
            movementMinutes: movementMin,
            steps: steps,
            activeCalories: activeCal,
            hrvMs: hrv,
            hrvType: hrvType,  // NEW FIELD
            restingHeartRate: rhr,
            breathingRate: br
        )
    }
}
```

---

## 🔗 Related Docs

- **Full Mapping:** [ROOK_TO_MIYA_MAPPING.md](./ROOK_TO_MIYA_MAPPING.md)
- **Scoring Schema:** [../VITALITY_SCORING_SCHEMA.md](../VITALITY_SCORING_SCHEMA.md)
- **Age-Specific Ranges:** [../AGE_SPECIFIC_SCHEMA.md](../AGE_SPECIFIC_SCHEMA.md)
- **Scoring Engine:** [../SCORING_ENGINE_COMPLETE.md](../SCORING_ENGINE_COMPLETE.md)

**This is a quick reference only. Always check the full mapping document before implementation! 🔒**

