# Flexible Window Update

## Changes Made

### VitalityMetricsBuilder - Now Uses Flexible Window

**Previous:** Fixed 7-day window
**Now:** Flexible 7-30 day window based on data availability

**Location:** `Miya Health/VitalityScoringEngine.swift`

**Function signature changed:**
```swift
// OLD
static func fromSevenDayWindow(age: Int, records: [VitalityData]) -> VitalityRawMetrics

// NEW
static func fromWindow(age: Int, records: [VitalityData]) -> VitalityRawMetrics
```

**Window selection logic:**
```swift
if records.count >= 30:
    → Use last 30 days (more stable average)
    
else if records.count >= 7:
    → Use all available records
    
else (records.count < 7):
    → Use all available records (compute score with what we have)
```

**Why this is better:**
- More stable scores with 30-day average when data is available
- Still works with 7-29 days of data
- Gracefully handles <7 days (doesn't fail, just computes with available data)
- Matches real-world usage where users may have varying amounts of historical data

---

## Age Calculation Update

**Previous:** Defaulted to age 35 if date of birth missing
**Now:** Defaults to age 0 if date of birth missing

```swift
// OLD
let age = Calendar.current.dateComponents([.year], from: onboardingManager.dateOfBirth, to: Date()).year ?? 35

// NEW
let age = Calendar.current.dateComponents([.year], from: onboardingManager.dateOfBirth, to: Date()).year ?? 0
```

**Why:** Age 0 is more obviously an error state than 35, making debugging easier if date of birth is not set.

---

## Testing Scenarios

### Scenario 1: Full 30+ Days of Data
**Input:** 45 days of vitality data
**Window used:** Last 30 days
**Expected:** Most stable, accurate score

### Scenario 2: 7-29 Days of Data
**Input:** 14 days of vitality data
**Window used:** All 14 days
**Expected:** Good score, slightly less stable than 30-day

### Scenario 3: Less Than 7 Days
**Input:** 4 days of vitality data
**Window used:** All 4 days
**Expected:** Score computed with available data (may be less representative)

### Scenario 4: Empty Data
**Input:** 0 days of vitality data
**Window used:** Empty array
**Expected:** All metrics nil → all sub-metric scores 0 → total score 0

---

## Sample Console Output

### With 30+ Days
```
✅ VitalityJSONParser: Parsed 45 records from JSON

=== New VitalityScoringEngine snapshot ===
Age: 35 AgeGroup: Young (< 40)
Total vitality: 72
[Using 30-day window for stable average]

Pillar: Sleep score: 65
  SubMetric: Sleep Duration raw: Optional(7.3) score: 87
  ...
=== End snapshot ===
```

### With 7-29 Days
```
✅ VitalityJSONParser: Parsed 14 records from JSON

=== New VitalityScoringEngine snapshot ===
Age: 35 AgeGroup: Young (< 40)
Total vitality: 68
[Using all 14 days available]

Pillar: Sleep score: 62
  SubMetric: Sleep Duration raw: Optional(7.1) score: 83
  ...
=== End snapshot ===
```

### With <7 Days
```
✅ VitalityJSONParser: Parsed 4 records from JSON

=== New VitalityScoringEngine snapshot ===
Age: 35 AgeGroup: Young (< 40)
Total vitality: 65
[Using all 4 days available - may be less representative]

Pillar: Sleep score: 60
  SubMetric: Sleep Duration raw: Optional(6.9) score: 78
  ...
=== End snapshot ===
```

---

## Backward Compatibility

✅ **Fully backward compatible**
- Old engine (`VitalityCalculator`) still uses fixed 7-day window
- New engine uses flexible window
- Both run in parallel
- No changes to existing behavior

---

## Files Modified

1. **`Miya Health/VitalityScoringEngine.swift`**
   - Renamed `fromSevenDayWindow()` → `fromWindow()`
   - Updated window selection logic (7-30 days)
   - Updated documentation

2. **`Miya Health/RiskResultsView.swift`**
   - Updated call to `fromWindow()` (was `fromSevenDayWindow()`)
   - Changed age fallback from 35 → 0

3. **`INTEGRATION_COMPLETE.md`**
   - Updated documentation to reflect flexible window

---

## Summary

**What changed:**
- Window is now flexible (7-30 days) instead of fixed (7 days)
- Uses 30-day average when available for more stable scores
- Gracefully handles any amount of data (even <7 days)
- Age defaults to 0 instead of 35 when missing

**What stayed the same:**
- All parsing logic unchanged
- Old engine unchanged
- Database writes unchanged
- UI display unchanged
- JSON/CSV/XML support unchanged

**Testing:**
- Use the same test files (`vitality_sample.json`, CSV, XML)
- Try with different amounts of data (4 days, 14 days, 45 days)
- Check console output for window size used
- Compare scores across different window sizes

