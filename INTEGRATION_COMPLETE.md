# ✅ VitalityScoringEngine Integration Complete

**Date:** December 12, 2025  
**Status:** ✅ Wired for Testing (Non-Destructive)

---

## What Was Built

### 1. VitalityMetricsBuilder
**Location:** `Miya Health/VitalityScoringEngine.swift` (bottom of file)

**Purpose:** Converts legacy `[VitalityData]` into `VitalityRawMetrics` for the new engine

**Function:**
```swift
VitalityMetricsBuilder.fromWindow(age: Int, records: [VitalityData]) -> VitalityRawMetrics
```

**How it works:**
- Uses flexible window (7-30 days) based on data availability:
  - If 30+ records: uses last 30 days
  - If 7-29 records: uses all available
  - If <7 records: uses all available (computes score with what we have)
- Averages `sleepHours`, `steps`, `hrvMs`, `restingHr` over the window
- Skips nil values when averaging
- Sets missing fields (restorative %, efficiency, etc.) to nil
- Returns `VitalityRawMetrics` ready for scoring

---

### 2. VitalityJSONParser
**Location:** `Miya Health/VitalityJSONParser.swift` (new file)

**Purpose:** Parse simple JSON test files into `[VitalityData]`

**Function:**
```swift
VitalityJSONParser.parse(content: String) -> [VitalityData]
```

**Expected JSON format:**
```json
[
  {
    "date": "2024-12-01",
    "sleep_hours": 7.5,
    "steps": 9200,
    "hrv_ms": 58.0,
    "resting_hr": 62
  }
]
```

**Fields:**
- `date` (String, "YYYY-MM-DD" format) — required
- `sleep_hours` (Double) — optional
- `steps` (Int) — optional
- `hrv_ms` (Double) — optional
- `resting_hr` (Int) — optional

**Error handling:**
- Invalid JSON → prints error, returns empty array
- Invalid date format → skips that record, prints warning
- Missing fields → sets to nil in `VitalityData`

---

### 3. Updated RiskResultsView.handleFileImport()
**Location:** `Miya Health/RiskResultsView.swift`

**Changes:**

#### File Importer (line ~438)
Now accepts: `.commaSeparatedText, .plainText, .xml, .json`

#### Parser Selection (line ~600-620)
```swift
if fileExtension == "xml" {
    vitalityData = VitalityCalculator.parseAppleHealthXML(content: content)
} else if fileExtension == "csv" || fileExtension == "txt" {
    vitalityData = VitalityCalculator.parseCSV(content: content)
} else if fileExtension == "json" {
    vitalityData = VitalityJSONParser.parse(content: content)
} else {
    errorMessage = "Unsupported file type: .\(fileExtension)"
}
```

#### New Engine Integration (line ~630-655)
After parsing, before old engine:
1. Calculate user age from `onboardingManager.dateOfBirth` (defaults to 0 if missing)
2. Build `VitalityRawMetrics` using `VitalityMetricsBuilder.fromWindow()` (flexible 7-30 day window)
3. Score with `VitalityScoringEngine().score(raw:)`
4. Print detailed snapshot to console

**Console output format:**
```
=== New VitalityScoringEngine snapshot ===
Age: 35 AgeGroup: Young (< 40)
Total vitality: 72
Pillar: Sleep score: 65
  SubMetric: Sleep Duration raw: Optional(7.2) score: 85
  SubMetric: Restorative Sleep % raw: nil score: 0
  SubMetric: Sleep Efficiency raw: nil score: 0
  SubMetric: Awake % raw: nil score: 0
Pillar: Movement score: 78
  SubMetric: Movement Minutes raw: nil score: 0
  SubMetric: Steps raw: Optional(9057.0) score: 85
  SubMetric: Active Calories raw: nil score: 0
Pillar: Stress score: 74
  SubMetric: HRV raw: Optional(57.1) score: 72
  SubMetric: Resting Heart Rate raw: Optional(62.4) score: 95
  SubMetric: Breathing Rate raw: nil score: 0
=== End snapshot ===
```

#### Old Engine (unchanged)
- Still calls `VitalityCalculator.calculate7DayAverage()`
- Still saves to database via `dataManager.saveVitalityScores()`
- Still updates UI with `importedVitalityScore`
- **No changes to existing behavior**

---

## How to Test

### Step 1: Prepare Test Data

**Option A: Use the sample JSON file**
- File: `vitality_sample.json` (in project root)
- Contains 7 days of realistic test data
- AirDrop to iPhone or add to Files app

**Option B: Create your own JSON**
```json
[
  {
    "date": "2024-12-01",
    "sleep_hours": 7.5,
    "steps": 9200,
    "hrv_ms": 58.0,
    "resting_hr": 62
  },
  {
    "date": "2024-12-02",
    "sleep_hours": 6.8,
    "steps": 8500,
    "hrv_ms": 55.0,
    "resting_hr": 64
  }
  // ... at least 7 days total
]
```

**Option C: Use existing CSV or XML**
- CSV format: `date,sleep_hours,steps,hrv_ms,resting_hr`
- XML: Apple Health export

### Step 2: Run the App

1. Open Xcode
2. Run the app in simulator or on device
3. Complete onboarding up to "Risk Results" screen
4. Tap "Import Health Data" button

### Step 3: Upload File

1. File picker opens
2. Select your JSON/CSV/XML file
3. Wait for import to complete

### Step 4: Check Console Output

**In Xcode console, you'll see:**

1. **JSON Parser output:**
   ```
   ✅ VitalityJSONParser: Parsed 7 records from JSON
   ```

2. **New engine snapshot:**
   ```
   === New VitalityScoringEngine snapshot ===
   Age: 35 AgeGroup: Young (< 40)
   Total vitality: 72
   Pillar: Sleep score: 65
     SubMetric: Sleep Duration raw: Optional(7.2) score: 85
     ...
   === End snapshot ===
   ```

3. **Old engine output (unchanged):**
   ```
   📊 VitalityCalculator: Parsed X records into Y days
   📊 VitalityCalculator: Returning Z days of vitality data
   ```

### Step 5: Compare Scores

**On screen (old engine):**
- Shows: `75/85` (current vs optimal)
- Components: Sleep 30/35, Movement 25/35, Stress 20/30

**In console (new engine):**
- Shows: `Total vitality: 72`
- Pillars: Sleep 65/100, Movement 78/100, Stress 74/100

**Why different?**
- Old engine: Hard-coded thresholds, 3 components (35+35+30)
- New engine: Age-specific ranges, 10 sub-metrics, weighted pillars (33%+33%+34%)

---

## What's Different

### Old Engine (VitalityCalculator)
- Uses 4 metrics: sleep hours, steps, HRV, resting HR
- Hard-coded thresholds (7-9h = 35 points)
- Simple threshold buckets
- No age personalization
- Output: 0-100 total (max 35+35+30)

### New Engine (VitalityScoringEngine)
- Uses 10 metrics (6 missing = nil for now)
- Schema-driven, age-specific ranges
- Linear interpolation scoring
- 4 age groups (young, middle, senior, elderly)
- Output: 0-100 total with pillar breakdown

### Current Limitations
The new engine only has 4 of 10 metrics populated:
- ✅ Sleep Duration (from `sleepHours`)
- ✅ Steps (from `steps`)
- ✅ HRV (from `hrvMs`)
- ✅ Resting Heart Rate (from `restingHr`)
- ❌ Restorative Sleep % (not in data)
- ❌ Sleep Efficiency (not in data)
- ❌ Awake % (not in data)
- ❌ Movement Minutes (not in data)
- ❌ Active Calories (not in data)
- ❌ Breathing Rate (not in data)

Missing metrics score 0, which lowers the total score.

---

## What Was NOT Changed

✅ **VitalityCalculator** — untouched, still used
✅ **Database writes** — still saves old format
✅ **UI display** — still shows old scores
✅ **Onboarding flow** — unchanged
✅ **DataManager** — unchanged
✅ **OnboardingManager** — unchanged

**This is test-only integration.** Both engines run in parallel for comparison.

---

## Next Steps (Not Done Yet)

1. **Extract missing metrics from Apple Health XML**
   - Parse sleep stages for restorative %
   - Calculate sleep efficiency from in-bed vs asleep time
   - Extract movement minutes, active calories
   - Parse breathing rate if available

2. **Replace old engine with new engine**
   - Remove `VitalityCalculator.calculate7DayAverage()` call
   - Use `VitalitySnapshot` for UI display
   - Update database schema to store pillar scores

3. **Update UI to show pillar breakdown**
   - Display Sleep/Movement/Stress pillars
   - Show sub-metric scores
   - Compare to age-specific targets

4. **Deprecate VitalityCalculator**
   - Archive old scoring logic
   - Remove hard-coded thresholds

---

## File Summary

### New Files
- `Miya Health/VitalityJSONParser.swift` — JSON parser for test data
- `vitality_sample.json` — Sample test file (7 days)
- `INTEGRATION_COMPLETE.md` — This file

### Modified Files
- `Miya Health/VitalityScoringEngine.swift` — Added `VitalityMetricsBuilder`
- `Miya Health/RiskResultsView.swift` — Added JSON support + new engine call

### Unchanged Files (as required)
- `Miya Health/VitalityCalculator.swift` — Old engine untouched
- `Miya Health/DataManager.swift` — No changes
- `Miya Health/OnboardingManager.swift` — No changes
- All other UI files — No changes

---

## Testing Checklist

- [ ] JSON file parses correctly
- [ ] CSV file still works (backward compatible)
- [ ] XML file still works (backward compatible)
- [ ] Console shows new engine snapshot
- [ ] Old engine still runs and displays on screen
- [ ] Database still saves scores
- [ ] UI still shows imported vitality
- [ ] Age is calculated correctly from date of birth
- [ ] 7-day window averages correctly
- [ ] Scores differ between old and new engines (expected)

---

**Ready to test! Upload a JSON/CSV/XML file and check the Xcode console for the new engine output. 🚀**

