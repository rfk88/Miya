# Vitality Score Testing Implementation - Summary

## What Was Built

### 1. Python Conversion Script
**File:** `convert_apple_health.py`
- Converts Apple Health XML export to vitality CSV format
- Extracts: sleep duration, steps, HRV, resting heart rate
- Aggregates data by day
- Usage: `python convert_apple_health.py export.xml`

### 2. Test Scenario CSVs (3 files)
**Files:**
- `scenario_healthy_young.csv` - High performer (Vitality ~85-95)
- `scenario_stressed_executive.csv` - Struggling (Vitality ~45-55)
- `scenario_decline_alert.csv` - Declining health over 3 weeks (tests alerts)

Each contains 21 days of realistic test data with different health patterns.

### 3. VitalityCalculator.swift
**Features:**
- Sleep component scoring (0-35 points)
- Movement component scoring (0-35 points)
- Stress/recovery scoring (0-30 points) with HRV preferred, resting HR fallback
- 7-day rolling average calculation
- CSV parsing functionality

**Methodology:** Implements exact WHO/AHA-based scoring system as specified.

### 4. SettingsView.swift
**Features:**
- Accessible via gear icon (⚙️) on home screen
- "Import Vitality Data CSV" button
- File picker for CSV import
- Real-time vitality score display after import
- Component breakdown (sleep/movement/stress points)
- Progress bars for visual feedback
- Clear test data option

### 5. ContentView.swift Updates
**Changes:**
- Added gear icon button to LandingView header
- Wired up settings sheet presentation
- Maintains all existing functionality

## How to Use

### Option 1: Your Real Apple Health Data

1. Export from iPhone Health app → get `export.xml`
2. Run: `pip install apple-health-extractor`
3. Run: `python convert_apple_health.py export.xml`
4. In app: Tap gear icon → Import Vitality Data CSV → Select `vitality_data.csv`
5. View your actual vitality score

### Option 2: Test Scenarios

1. In app: Tap gear icon → Import Vitality Data CSV
2. Select one of: `scenario_healthy_young.csv`, `scenario_stressed_executive.csv`, or `scenario_decline_alert.csv`
3. View calculated score for that scenario
4. Repeat with different scenarios to test various health profiles

## What You Can Test

1. **Scoring Accuracy**
   - Verify sleep/movement/stress components calculate correctly
   - Ensure 7-day rolling average works as expected
   - Confirm total score caps at 100

2. **Different Health Profiles**
   - Healthy young adult (high vitality)
   - Stressed/sleep-deprived person (low vitality)
   - Declining health trajectory (for alert testing)

3. **CSV Import Flow**
   - File picker integration
   - Parsing logic
   - Error handling (not enough data, invalid format, etc.)

4. **UI/UX**
   - Settings access via gear icon
   - Score display with component breakdown
   - Visual progress bars

## Next Steps (When Ready)

### To Add Results Screen in Onboarding:
1. Create `RiskResultsView` showing:
   - WHO Risk Band (from RiskCalculator)
   - Risk Points total
   - BMI + category
   - **Optimal Vitality Target** (from age + risk band)
   - **Current Vitality Score** (placeholder until wearables)
   - Assessment text + next steps

2. Wire navigation: MedicalHistory → RiskResults → (existing flow continues)

3. Call `dataManager.saveRiskAssessment()` when entering results screen

### For Real Wearable Integration:
- Replace CSV import with HealthKit API calls (iOS)
- Add Whoop, Fitbit, Garmin API integrations
- Same `VitalityCalculator` logic works for real data
- Store in `vitality_scores` table: (user_id, date, score, sleep_pts, movement_pts, stress_pts)
- Update score daily as new wearable data arrives

## Files Modified/Created

### New Files:
- `convert_apple_health.py` - XML to CSV converter
- `scenario_healthy_young.csv` - Test data
- `scenario_stressed_executive.csv` - Test data
- `scenario_decline_alert.csv` - Test data
- `Miya Health/VitalityCalculator.swift` - Scoring logic
- `Miya Health/SettingsView.swift` - Settings UI with import
- `VITALITY_TESTING_README.md` - User guide
- `IMPLEMENTATION_SUMMARY.md` - This file

### Modified Files:
- `Miya Health/ContentView.swift` - Added gear icon + settings sheet

## Testing Checklist

- [ ] Gear icon appears on home screen
- [ ] Tapping gear opens settings
- [ ] Import CSV button works
- [ ] File picker appears
- [ ] Selecting valid CSV imports successfully
- [ ] Score displays with correct calculations
- [ ] Component breakdown shows correct point allocation
- [ ] Progress bars render correctly
- [ ] Clear data button works
- [ ] Error handling for invalid CSV
- [ ] Error handling for <7 days data
- [ ] All 3 test scenarios import successfully
- [ ] Real Apple Health data imports (if available)

## Notes

- Settings view is accessible to everyone (not hidden/debug-only) as requested
- Gear icon is immediately visible on home screen
- CSV import is user-friendly with clear instructions in footer
- All scoring matches the WHO/AHA methodology document exactly
- Clean transition path to real wearable data when ready

