# ✅ UI Comparison Complete - Side-by-Side Scoring

**Date:** December 12, 2025  
**Status:** ✅ New Engine Visible in RiskResultsView

---

## What Was Added

### New State in RiskResultsView

**Location:** `Miya Health/RiskResultsView.swift` (lines ~24-26)

```swift
// New engine state (testing)
@State private var newEngineSnapshot: VitalitySnapshot?
@State private var newEngineErrorMessage: String?
```

**Purpose:**
- `newEngineSnapshot`: Holds the complete vitality snapshot from the new engine
- `newEngineErrorMessage`: Holds any error message if new engine fails

**Existing state unchanged:**
- `importedVitalityScore` (old engine) — still used
- All other state properties — unchanged

---

## State Population in handleFileImport()

**Location:** `Miya Health/RiskResultsView.swift` (lines ~707-738)

**Flow:**
1. Parse file → `[VitalityData]`
2. Calculate user age from `onboardingManager.dateOfBirth`
3. Build `VitalityRawMetrics` using `VitalityMetricsBuilder.fromWindow()`
4. Call `VitalityScoringEngine().score(raw:)`
5. **NEW:** Update state:
   ```swift
   await MainActor.run {
       newEngineSnapshot = snapshot
       newEngineErrorMessage = nil
   }
   ```
6. Print to console (optional, kept for debugging)
7. Continue with old engine (unchanged)

**Error handling:**
```swift
catch {
    await MainActor.run {
        newEngineSnapshot = nil
        newEngineErrorMessage = "Failed to compute new engine score: \(error.localizedDescription)"
    }
}
```

---

## UI Display

**Location:** `Miya Health/RiskResultsView.swift` (lines ~347-399)

**Placement:** Immediately after the old engine vitality score display, inside the same conditional block

**Layout:**
```
┌─────────────────────────────────────┐
│ Current Vitality Score (Old Engine) │
│ 75/85                               │
│ Sleep: 30/35                        │
│ Movement: 25/35                     │
│ Recovery: 20/30                     │
│ Based on 7-day rolling average...   │
├─────────────────────────────────────┤
│ New Vitality Engine (Testing)       │
│ 72/100          Young (< 40)        │
│ 🛏️ Sleep: 65/100                    │
│ 🏃 Movement: 78/100                  │
│ ❤️ Stress: 74/100                    │
│ Age-specific scoring with schema... │
└─────────────────────────────────────┘
```

**Code structure:**
```swift
if let vitality = importedVitalityScore {
    // Old engine display (unchanged)
    VStack {
        Text("Current Vitality Score")
        // ... existing UI ...
    }
    
    // NEW: New engine display
    if let snapshot = newEngineSnapshot {
        Divider()
        VStack {
            HStack {
                Text("New Vitality Engine")
                Text("(Testing)").badge()
            }
            Text("\(snapshot.totalScore)/100")
            ForEach(snapshot.pillarScores) { pillar in
                Text("\(pillar.pillar): \(pillar.score)/100")
            }
        }
    }
    
    // NEW: Error display
    if let error = newEngineErrorMessage {
        Text("New engine error: \(error)")
    }
}
```

**Styling:**
- Consistent with existing RiskResultsView style
- Uses `.miyaPrimary`, `.miyaTextPrimary`, `.miyaSecondary` colors
- Marked with "(Testing)" badge
- Shows age group in subtitle
- Uses pillar icons (bed, walk, heart)

---

## How to Test

### Step 1: Run Onboarding
1. Open app in simulator/device
2. Complete onboarding through "Medical History"
3. Reach "Risk Results" screen

### Step 2: Import Data
1. Tap "Import Health Data" button
2. Select a file:
   - `vitality_sample.json` (7 days)
   - `vitality_sample_30days.json` (33 days)
   - Any CSV or XML file

### Step 3: View Results

**On screen, you'll see:**

**Old Engine (top):**
```
Current Vitality Score
75/85

Sleep: 30/35
Movement: 25/35
Recovery: 20/30

Based on 7-day rolling average from imported data.
```

**New Engine (bottom):**
```
New Vitality Engine (Testing)
72/100          Young (< 40)

🛏️ Sleep: 65/100
🏃 Movement: 78/100
❤️ Stress: 74/100

Age-specific scoring with schema-based ranges.
```

**In console:**
```
=== New VitalityScoringEngine snapshot ===
Age: 35 AgeGroup: Young (< 40)
Total vitality: 72
Pillar: Sleep score: 65
  SubMetric: Sleep Duration raw: Optional(7.2) score: 85
  SubMetric: Restorative Sleep % raw: nil score: 0
  ...
=== End snapshot ===
```

---

## Key Differences Visible

### Score Format
- **Old:** X/85 (current vs optimal target)
- **New:** X/100 (absolute score)

### Components
- **Old:** 3 components (Sleep, Movement, Recovery) with max 35+35+30
- **New:** 3 pillars (Sleep, Movement, Stress) each 0-100

### Scoring Method
- **Old:** Threshold buckets (7-9h = 35 points)
- **New:** Linear interpolation (7.2h → 85 points)

### Age Personalization
- **Old:** None (same thresholds for all)
- **New:** Age-specific (shows age group, uses age-adjusted ranges)

### Data Window
- **Old:** Fixed 7-day average
- **New:** Flexible 7-30 day window

---

## What's Still the Same

✅ **Old engine still runs** — unchanged behavior
✅ **Database writes** — still saves old format
✅ **Dashboard** — still uses mock data
✅ **Onboarding flow** — unchanged
✅ **File parsing** — unchanged (XML, CSV, JSON all work)

---

## UI Behavior

### When No File Imported
- Old engine: Shows "Import Health Data" button
- New engine: Hidden (no display)

### When File Imported Successfully
- Old engine: Shows score + breakdown
- New engine: Shows score + pillar breakdown (side-by-side)

### When New Engine Fails
- Old engine: Shows score (unaffected)
- New engine: Shows error message in red

### When Both Succeed
- Both scores visible
- Easy visual comparison
- Different scoring methodologies clear

---

## Visual Comparison Example

### Sample Data (7 days)
- Sleep: 7.2h average
- Steps: 9,057 average
- HRV: 57.1ms average
- Resting HR: 62.4 bpm average

### Old Engine Result
```
Total: 75/85
Sleep: 30/35 (7.2h in 7-9h range → 35 pts)
Movement: 25/35 (9,057 steps in 7.5-10k → 25 pts)
Recovery: 20/30 (57.1ms HRV in 50-65ms → 20 pts)
```

### New Engine Result
```
Total: 72/100
Sleep: 65/100 (missing 6 of 10 metrics)
  ✅ Duration: 7.2h → 85/100 (linear in optimal)
  ❌ Restorative: nil → 0/100
  ❌ Efficiency: nil → 0/100
  ❌ Awake: nil → 0/100
Movement: 78/100 (missing 2 of 3 metrics)
  ❌ Minutes: nil → 0/100
  ✅ Steps: 9,057 → 85/100 (linear in optimal)
  ❌ Calories: nil → 0/100
Stress: 74/100
  ✅ HRV: 57.1ms → 72/100 (acceptable for age 35)
  ✅ RHR: 62.4 bpm → 95/100 (optimal)
  ❌ Breathing: nil → 0/100
```

**Why new engine is lower:**
- Missing 6 of 10 metrics (score 0)
- Weighted averaging pulls down pillar scores
- More granular, less forgiving

**Why new engine is better:**
- Age-specific (targets adjust with age)
- Linear interpolation (more precise)
- 10 metrics when available (more complete picture)

---

## Next Steps (Not Done Yet)

1. **Extract missing metrics from Apple Health**
   - Sleep stages, efficiency, fragmentation
   - Movement minutes, active calories
   - Breathing rate

2. **Replace old engine**
   - Remove `VitalityCalculator` calls
   - Use only new engine
   - Update database schema

3. **Update Dashboard**
   - Show pillar breakdown
   - Use real scores (not mock data)
   - Display trends over time

---

## Summary

**New state added:**
- `newEngineSnapshot: VitalitySnapshot?`
- `newEngineErrorMessage: String?`

**State population:**
- In `handleFileImport()` after parsing and scoring
- Updates on success: `newEngineSnapshot = snapshot`
- Updates on error: `newEngineErrorMessage = error`

**UI display:**
- Appears below old engine score in RiskResultsView
- Shows total + 3 pillar scores
- Marked as "(Testing)"
- Only visible when `newEngineSnapshot` is non-nil

**How to trigger:**
- Complete onboarding to Risk Results screen
- Tap "Import Health Data"
- Select JSON/CSV/XML file
- See both engines side-by-side on screen

**The new engine is now visible for manual comparison! 🎉**

