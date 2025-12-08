# Quick Start - Testing Vitality Scores

## 🎯 Goal
Test vitality score calculations with real or simulated health data before wearable integrations.

## 📱 In the App

1. **Open Miya Health app**
2. **Tap the gear icon (⚙️)** in top-right corner
3. **Tap "Import Vitality Data CSV"**
4. **Select a CSV file:**
   - Use pre-made scenarios (see below)
   - Or your converted Apple Health data
5. **View your vitality score!**

## 🧪 Test with Pre-Made Scenarios

Three CSV files are ready to test:

### Scenario 1: Healthy Young Adult
**File:** `scenario_healthy_young.csv`
- Sleep: 7.5-8.5h avg
- Steps: 9k-13k avg
- HRV: 68-75ms
- **Expected Score: ~90**

### Scenario 2: Stressed Executive
**File:** `scenario_stressed_executive.csv`
- Sleep: 5.5-6.5h avg
- Steps: 4k-6k avg
- HRV: 44-52ms
- **Expected Score: ~50**

### Scenario 3: Health Decline (Alert Test)
**File:** `scenario_decline_alert.csv`
- Week 1: Good (80)
- Week 2: Declining (65)
- Week 3: Poor (45)
- **Tests alert triggering**

## 💪 Use Your Real Apple Health Data

### Step 1: Export from iPhone
1. Open **Health** app
2. Tap profile picture (top-right)
3. Scroll down → **Export All Health Data**
4. Save → Airdrop to Mac or save to iCloud Drive
5. Unzip to get `export.xml`

### Step 2: Convert to CSV
```bash
# Install converter (one-time)
pip install apple-health-extractor

# Convert your data
python convert_apple_health.py export.xml
```

Output: `vitality_data.csv` with your last 90 days

### Step 3: Import to App
1. In app → Tap gear icon (⚙️)
2. Import Vitality Data CSV
3. Select `vitality_data.csv`
4. See your real vitality score!

## 📊 What You'll See

After importing:
- **Total Vitality Score** (0-100)
- **Sleep Points** (0-35) with progress bar
- **Movement Points** (0-35) with progress bar
- **Stress/Recovery Points** (0-30) with progress bar
- Based on 7-day rolling average

## 🔧 Create Custom Scenarios

1. Copy an existing scenario CSV
2. Edit values in any text editor/Excel:
   - `sleep_hours`: change to test different sleep patterns
   - `steps`: adjust for activity levels
   - `hrv_ms` or `resting_hr`: modify for stress testing
3. Save as new CSV
4. Import to test!

## ⚠️ Troubleshooting

**"Need at least 7 days"**
→ CSV must have 7+ consecutive days

**"No valid data found"**
→ Check CSV format:
```csv
date,sleep_hours,steps,hrv_ms,resting_hr
2024-12-01,7.5,10200,68,58
```

**Can't find CSV files**
→ They're in the Miya project folder

## 📁 File Locations

All in: `/Users/ramikaawach/Desktop/Miya/`

- `convert_apple_health.py` - Converter script
- `scenario_healthy_young.csv` - Test scenario 1
- `scenario_stressed_executive.csv` - Test scenario 2
- `scenario_decline_alert.csv` - Test scenario 3
- `VITALITY_TESTING_README.md` - Detailed guide

## 🚀 That's It!

You can now test vitality scoring with multiple scenarios before building the full wearable integrations.

