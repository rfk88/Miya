# Clinical Prompt Update - Complete Implementation Summary

## Overview

Replaced the basic AI insight prompt with a comprehensive **clinical family health advisor** prompt that provides structured, actionable insights in 4 key sections.

---

## Changes Made

### 1. **Database Schema Update**

**New Migration:** `supabase/migrations/20260111000000_update_pattern_alert_ai_insights_schema.sql`

Added new columns to `pattern_alert_ai_insights`:
- `clinical_interpretation` (text) - Clinical explanation of the trend
- `data_connections` (text) - How other metrics relate to this alert
- `possible_causes` (jsonb) - Array of realistic explanations
- `action_steps` (jsonb) - Array of specific, actionable recommendations

**Note:** Old columns (`summary`, `contributors`, `actions`) are kept for backwards compatibility.

---

### 2. **Edge Function Update** (`supabase/functions/miya_insight/index.ts`)

#### **A. New Response Type**

```typescript
type InsightResponse = {
  headline: string;
  clinical_interpretation: string;  // NEW
  data_connections: string;         // NEW
  possible_causes: string[];        // NEW (replaces contributors)
  action_steps: string[];           // NEW (replaces actions)
  message_suggestions?: { label: string; text: string }[];
  confidence?: "low" | "medium" | "high";
  confidence_reason?: string;
  evidence: Record<string, unknown>;
};
```

#### **B. Updated Prompt Structure**

The AI now follows this clinical format:

**1. CLINICAL INTERPRETATION (2-3 sentences)**
- What this level of change suggests
- Is this concerning or normal variation?
- Considers timeframe (acute vs. gradual)

**2. DATA CONNECTIONS (2-3 sentences)**
- How other metrics relate (sleep, HRV, resting HR, etc.)
- Uses ABSOLUTE values (e.g., "Sleep increased from 6.2 to 7.7 hours")
- States whether metrics are improving, stable, or worsening

**3. POSSIBLE CAUSES (3-5 bullet points)**
- Physical: injury, pain, illness, recovery
- Mental: depression, anxiety, burnout
- Circumstantial: routine change, work demands
- Environmental: seasonal changes, family situation

**4. ACTION STEPS (3-4 numbered items)**
1. Immediate check-in with family member
2. Specific symptoms to watch for
3. Concrete supportive actions
4. When to escalate to medical consultation

#### **C. Tone Guidelines**

- Concerned but not alarmist
- Family-to-family, not doctor-to-patient
- "May indicate" not "definitely means"
- Empower action without creating anxiety
- Avoids medical jargon

#### **D. Data Requirements**

The prompt enforces:
- Always use absolute values (not just percentages)
- Include timeframes (from level: "over 7 days", "over 3 weeks")
- Show baseline comparison periods
- Report current status of ALL available metrics

#### **E. Prompt Version**

Updated from `v2` to `v3` to trigger fresh AI generation with new structure.

---

### 3. **iOS UI Update** (`Miya Health/DashboardView.swift`)

#### **A. New State Variables**

```swift
@State private var aiInsightClinicalInterpretation: String?
@State private var aiInsightDataConnections: String?
@State private var aiInsightPossibleCauses: [String] = []
@State private var aiInsightActionSteps: [String] = []
```

#### **B. Redesigned UI Layout**

**Premium structured display with color-coded sections:**

```
┌─────────────────────────────────────────┐
│  BASELINE → CURRENT → OPTIMAL           │
│  (metrics card with large numbers)      │
└─────────────────────────────────────────┘

━━━ HEADLINE (18pt bold) ━━━

┌─────────────────────────────────────────┐
│  CLINICAL INTERPRETATION                 │
│  (blue background, rounded font)         │
│  What this trend means clinically        │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  WHAT THE DATA SHOWS                     │
│  (purple background, rounded font)       │
│  How other metrics connect               │
└─────────────────────────────────────────┘

● POSSIBLE CAUSES
  • Physical factors
  • Mental factors
  • Circumstantial factors
  • Environmental factors

┌─────────────────────────────────────────┐
│  WHAT TO DO NOW                          │
│  (green background)                      │
│  ① Immediate check-in                    │
│  ② Watch for symptoms                    │
│  ③ Supportive actions                    │
│  ④ When to escalate                      │
└─────────────────────────────────────────┘

ℹ️ Confidence: high — Data shows...
```

**Design Features:**
- **Color-coded sections** for visual hierarchy
- **Numbered action steps** with circular badges
- **Bullet points** with colored circles
- **Background cards** to separate sections
- **Rounded typography** for readability
- **Uppercase section headers** with tracking

---

## Deployment Steps

### 1. Run Database Migration

```bash
cd /Users/ramikaawach/Desktop/Miya
supabase db push
```

Or manually run in Supabase SQL Editor:
```sql
-- From: supabase/migrations/20260111000000_update_pattern_alert_ai_insights_schema.sql
alter table public.pattern_alert_ai_insights 
  add column if not exists clinical_interpretation text,
  add column if not exists data_connections text,
  add column if not exists possible_causes jsonb,
  add column if not exists action_steps jsonb;
```

### 2. Deploy Edge Function

```bash
cd supabase
supabase functions deploy miya_insight
```

### 3. Rebuild iOS App

Rebuild in Xcode to get the new UI and state handling.

---

## Testing

1. Navigate to Dashboard → Family Notifications
2. Tap on a pattern alert (e.g., "Ahmed · Movement")
3. Scroll to "What's going on" section
4. You should see:
   - **Metrics card** at top with baseline/current/optimal
   - **Headline** in bold
   - **4 colored sections** (clinical interpretation, data connections, possible causes, action steps)
   - **Numbered action items** with green badges
   - **Confidence indicator** at bottom

---

## Example Output

**Alert:** Ahmed's steps decreased by 51% over 21 days

### Metrics Card
```
BASELINE     →     CURRENT
8,500 steps        4,165 steps
      ↓ 51% change

OPTIMAL STEPS  8,000-10,000 steps
```

### Headline
"Movement significantly below baseline"

### Clinical Interpretation (blue card)
"A 51% sustained decrease in daily movement over 3 weeks is clinically significant. This level of reduction often indicates injury, illness, lifestyle disruption, or changes in mental health. The gradual nature over 21 days suggests a persistent change rather than a temporary fluctuation."

### What the Data Shows (purple card)
"Sleep duration increased from 6.2 to 7.7 hours (24% increase), which could indicate the body is compensating for reduced activity or underlying fatigue. Heart rate variability remains stable at 45 ms, suggesting no acute cardiovascular stress. However, resting heart rate increased from 62 to 68 bpm, which may reflect deconditioning."

### Possible Causes
- Physical: Recent injury, chronic pain, illness recovery, or mobility issues
- Mental: Depression, anxiety, burnout, or loss of motivation
- Circumstantial: Major routine change, increased work demands, or travel disruption
- Environmental: Seasonal changes (winter weather), family situation changes
- Medical: Medication side effects or undiagnosed condition requiring evaluation

### What to Do Now (green card)
1. Have a conversation with Ahmed today - ask how he's feeling physically and emotionally, and if anything has changed in his life or routine
2. Look for signs of: persistent fatigue, pain, low mood, changes in appetite, social withdrawal, or difficulty with daily activities
3. If he's feeling well, encourage a short walk together to gently restart activity. If there's pain or discomfort, respect rest needs and identify barriers to movement
4. If this pattern continues beyond 2-3 weeks, worsens, or is accompanied by other concerning symptoms, schedule a medical check-up to rule out underlying conditions

---

## Key Improvements Over Previous Version

### Before (v2):
- ❌ Single "summary" paragraph
- ❌ Generic "contributors" list
- ❌ Vague "actions" list
- ❌ Percentages without context
- ❌ No clinical reasoning

### After (v3):
- ✅ **Structured 4-section format**
- ✅ **Clinical interpretation** with reasoning
- ✅ **Absolute values** (6.2 → 7.7 hours)
- ✅ **Connected data** analysis
- ✅ **Realistic causes** with categories
- ✅ **Specific action steps** with escalation guidance
- ✅ **Premium visual design** with color-coding
- ✅ **Family-friendly tone** without jargon

---

## Data Accuracy Guarantees

The prompt enforces:
- ✅ All claims must be grounded in evidence JSON
- ✅ No invented numbers, dates, or trends
- ✅ Absolute values required (hours, steps, ms, bpm)
- ✅ Supporting metrics only mentioned if data exists
- ✅ Confidence reflects data coverage quality

---

## Files Changed

1. ✅ `supabase/migrations/20260111000000_update_pattern_alert_ai_insights_schema.sql` - New migration
2. ✅ `supabase/functions/miya_insight/index.ts` - Updated prompt, schema, and caching
3. ✅ `Miya Health/DashboardView.swift` - Updated state, parsing, and UI

**Status:** ✅ Ready to deploy (no linter errors)

---

## Notes

- Old cached insights (v2) will automatically be regenerated on next view with v3 format
- The migration is additive - old columns preserved for backwards compatibility
- Message suggestions remain unchanged
- Evidence JSON structure unchanged (same data flows through)
