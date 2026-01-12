# AI Insight Redesign - Summary

## Changes Made

### 1. **AI Prompt Structure** (`supabase/functions/miya_insight/index.ts`)

**Updated the system prompt to guide the AI to follow a clear story arc:**

```
SUMMARY STRUCTURE (follow this story arc exactly):
1. Start with the time period (e.g., 'Over the last 21 days')
2. State the metric and baseline (e.g., 'heart rate variability (HRV) has dropped from a baseline of about X ms')
3. State current value and the change (e.g., 'to approximately Y ms, indicating a Z% decrease')
4. Add context from supporting signals if their deviation_percent_human is present
5. End with what this suggests (e.g., 'suggesting potential changes in recovery or stress levels')
```

This ensures the AI tells a coherent story: **baseline → current → change → insight**.

---

### 2. **UI Redesign** (`Miya Health/DashboardView.swift`)

Completely redesigned the `metricsDisplayView` to create a **premium, structured insight experience**:

#### **A. Metrics Card with Prominent Numbers**

- **Baseline** (left) and **Current** (right) displayed in large, bold numbers
- **Arrow indicator** showing direction of change (up/down)
- **Change percentage** badge with color coding (red for decrease, green for increase)
- **Optimal range** displayed clearly below with green accent

**Visual Hierarchy:**
```
┌─────────────────────────────────────┐
│  BASELINE        ↘️        CURRENT   │
│    55 ms                  46 ms     │
│                                     │
│        ↓ 17% change                 │
│  ─────────────────────────────────  │
│  OPTIMAL HRV       70-100 ms       │
└─────────────────────────────────────┘
```

#### **B. Structured Content Sections**

1. **Headline** - Bold, prominent (17pt, semibold)
2. **Summary** - AI-generated story with improved readability (15pt, rounded font, increased line spacing)
3. **Divider** - Visual separation
4. **Contributors** - Bullet points with circular indicators
5. **Support Actions** - Bullet points with heart icons
6. **Confidence** - Icon + text indicator at bottom

#### **C. Premium Design Elements**

- **Secondary background cards** for metrics
- **Uppercase labels** with letter tracking
- **Rounded number fonts** for metrics
- **Color-coded indicators** (red for alerts, green for positive)
- **Subtle icons** throughout (circles, hearts, confidence badges)
- **Increased spacing** for breathing room

---

### 3. **Data Flow** 

Added new state variables to capture baseline/recent/deviation from AI insight response:

```swift
@State private var aiInsightBaselineValue: Double?
@State private var aiInsightRecentValue: Double?
@State private var aiInsightDeviationPercent: Double?
```

These are extracted from the `evidence` object in the `miya_insight` Edge Function response and used to populate the metrics card.

---

## What the User Will See

### Before (Old Design)
- Wall of text
- No clear separation between sections
- Numbers buried in paragraphs
- Hard to see baseline vs current vs optimal

### After (New Design)
- **Prominent metrics card** showing baseline → current → optimal
- **Visual indicators** (arrows, badges) for quick scanning
- **Structured story** following a clear arc
- **Premium feel** with proper spacing, typography, and visual hierarchy
- **Easy to understand** at a glance

---

## Next Steps

### To Deploy Edge Function Changes:

```bash
cd supabase
supabase functions deploy miya_insight
```

### To Test:

1. Rebuild the iOS app in Xcode
2. Navigate to Dashboard → Family Notifications
3. Tap on a pattern alert (e.g., "Ahmed · Movement")
4. The "What's going on" section should now show:
   - Metrics card with baseline/current/optimal
   - Structured AI summary following the story arc
   - Clean, premium visual design

---

## Design Principles Applied

✅ **Clear storytelling** - Baseline → Current → Change → Insight  
✅ **Visual hierarchy** - Most important info (numbers) is most prominent  
✅ **Premium feel** - Rounded fonts, proper spacing, subtle shadows  
✅ **Scannable** - Icons, colors, and structure guide the eye  
✅ **Actionable** - Contributors and support actions clearly separated  

---

## Files Changed

1. `supabase/functions/miya_insight/index.ts` - Updated AI prompt
2. `Miya Health/DashboardView.swift` - Redesigned UI and added data extraction

**Status:** ✅ Ready to test (no linter errors)
