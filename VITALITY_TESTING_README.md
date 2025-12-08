# Vitality Score Testing Guide

## Overview

You can now test vitality score calculations using CSV data. This allows you to:
- Import your real Apple Health data
- Test with different health scenarios
- Verify scoring accuracy before wearable integrations

## Quick Start

### 1. Access Settings
- Open the Miya Health app
- Tap the **gear icon (⚙️)** in the top-right corner of the home screen
- This opens the Settings menu

### 2. Import CSV Data

**Option A: Use Your Apple Health Data**

1. Export your Apple Health data:
   - Open Health app on iPhone
   - Tap your profile picture
   - Scroll down and tap "Export All Health Data"
   - Save the `export.zip` file
   - Unzip to get `export.xml`

2. Convert to CSV:
   ```bash
   pip install apple-health-extractor
   python convert_apple_health.py export.xml
   ```
   This creates `vitality_data.csv`

3. In the app:
   - Tap "Import Vitality Data CSV"
   - Select `vitality_data.csv`
   - View your calculated vitality score

**Option B: Use Test Scenarios**

Three pre-built scenarios are included:

1. **scenario_healthy_young.csv**
   - Sleep: 7.5-8.5 hours avg
   - Steps: 9,000-12,000 avg
   - HRV: 68-75ms avg
   - Expected Score: ~85-95

2. **scenario_stressed_executive.csv**
   - Sleep: 5.5-6.5 hours avg
   - Steps: 4,000-6,000 avg
   - HRV: 44-52ms avg
   - Expected Score: ~45-55

3. **scenario_decline_alert.csv**
   - Week 1: Good health (~80)
   - Week 2: Declining (~65)
   - Week 3: Poor health (~45)
   - Tests alert triggering

To use:
- Tap "Import Vitality Data CSV" in Settings
- Select one of the scenario files
- View the calculated score

## CSV Format

```csv
date,sleep_hours,steps,hrv_ms,resting_hr
2024-12-01,7.5,10200,68,58
2024-12-02,8.0,11500,70,57
...
```

### Required Columns:
- `date`: YYYY-MM-DD format
- `sleep_hours`: Total sleep in hours (can be decimal like 7.5)
- `steps`: Daily step count
- `hrv_ms`: Heart rate variability in milliseconds
- `resting_hr`: Resting heart rate in bpm

### Notes:
- Minimum 7 consecutive days needed for calculation
- HRV and resting_hr can be empty (leave blank if unavailable)
- If HRV is missing, resting HR is used as fallback for stress component

## Scoring Methodology

### Sleep Component (0-35 points)
- 7-9 hours = 35 points (optimal)
- 6-7 or 9-10 hours = 25 points
- 5-6 or 10-11 hours = 15 points
- <5 or >11 hours = 5 points

### Movement Component (0-35 points)
- 10,000+ steps = 35 points
- 7,500-9,999 steps = 25 points
- 5,000-7,499 steps = 15 points
- <5,000 steps = 5 points

### Stress/Recovery Component (0-30 points)

**HRV-based (preferred):**
- High HRV (≥65ms) = 30 points (good recovery)
- Moderate HRV (50-64ms) = 20 points
- Low HRV (<50ms) = 10 points (poor recovery)

**Resting HR-based (fallback):**
- 50-60 bpm = 30 points
- 61-70 bpm = 25 points
- 71-80 bpm = 20 points
- 81-90 bpm = 15 points
- >90 bpm = 10 points

### Total Vitality Score
- Sum of Sleep + Movement + Stress components
- Maximum: 100 points
- Calculated as 7-day rolling average

## Creating Custom Test Scenarios

1. Copy one of the existing scenario CSV files
2. Modify the values to test different conditions:
   - Adjust sleep hours to test sleep scoring
   - Change step counts to test movement scoring
   - Alter HRV/resting HR to test stress scoring
3. Import in the app to see results

## Future Integration

This CSV import is temporary for testing. When wearable integrations are complete:
- Data will automatically sync from connected devices (Apple Watch, Whoop, etc.)
- Same calculation logic will apply
- Real-time continuous monitoring
- No manual CSV imports needed

## Troubleshooting

**"Need at least 7 days of data"**
- Ensure your CSV has at least 7 consecutive days
- Check that dates are in YYYY-MM-DD format

**"No valid data found"**
- Verify CSV format matches the template
- Check for proper comma separation
- Ensure header row is present

**"Cannot access file"**
- Make sure the CSV file is accessible on your device
- Try copying to iCloud Drive or Files app first

## Support

For issues or questions, check that:
1. CSV format matches the specification above
2. At least 7 days of data are present
3. Date format is YYYY-MM-DD
4. Sleep hours and steps have valid numeric values

