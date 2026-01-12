# Metric-Specific AI Insights - Complete Implementation

## Overview

Complete restructuring of AI insight generation with **metric-specific** and **severity-aware** prompts that include all 4 health metrics (primary + 3 supporting).

---

## Key Changes

### 1. **New Data Structure**

The Edge Function now sends a structured JSON payload with all 4 metrics:

```json
{
  "alert": {
    "metric": "steps",
    "pattern": "drop_vs_baseline",
    "pillar": "movement",
    "level": 7,
    "consecutive_days": 8
  },
  "person": {
    "name": "Ahmed"
  },
  "primary_metric": {
    "name": "steps",
    "current_value": 4493,
    "baseline_value": 9261,
    "percent_change": -51.4,
    "absolute_change": -4768
  },
  "supporting_metrics": [
    {
      "name": "sleep_minutes",
      "current_value": 462,
      "baseline_value": 372,
      "percent_change": 24.2,
      "absolute_change": 90
    },
    {
      "name": "hrv_ms",
      "current_value": 45,
      "baseline_value": 43,
      "percent_change": 4.7,
      "absolute_change": 2
    },
    {
      "name": "resting_hr",
      "current_value": 62,
      "baseline_value": 64,
      "percent_change": -3.1,
      "absolute_change": -2
    }
  ],
  "context": {
    "alert_start_date": "2026-01-07",
    "analysis_date": "2026-01-11"
  }
}
```

**Rules enforced:**
- ✅ Always includes all 4 metrics
- ✅ Primary metric = the one that triggered alert
- ✅ Supporting metrics = the other 3
- ✅ Both absolute values and percentage changes included
- ✅ Baseline uses up to 21 days (not just 7)

---

### 2. **Metric-Specific Clinical Interpretations**

AI now receives pre-built templates based on the specific metric:

#### **Steps (Movement)**
```
"A 51% sustained decrease in daily steps (from 9261 to 4493 steps) 
over 8 days is clinically significant. This level of reduction 
typically indicates injury, illness, lifestyle disruption, or 
changes in mental health and motivation."
```

#### **Sleep Minutes**
```
"A 15% decrease in sleep duration (from 7.2 to 6.1 hours) over 8 days 
is concerning. Chronic sleep restriction increases cardiovascular and 
metabolic health risks and often signals stress, schedule changes, or 
emerging sleep disorders."
```

#### **HRV (Stress)**
```
"A 20% drop in heart rate variability (from 55ms to 44ms) over 8 days 
indicates increased physiological stress. Lower HRV is associated with 
poor recovery, illness, overtraining, or psychological stress."
```

#### **Resting HR (Stress)**
```
"A 12% increase in resting heart rate (from 60 to 67 bpm) over 8 days 
suggests reduced cardiovascular fitness, inadequate recovery, or 
potential illness. Elevated resting heart rate is an early warning sign 
the body isn't recovering properly."
```

---

### 3. **Metric-Specific Possible Causes**

The AI receives metric-specific cause lists:

**Steps:**
- Injury, pain, or physical limitation affecting mobility
- Illness or recovery from illness
- Major routine disruption (weather, work schedule change, travel)
- Low motivation, mood changes, or depressive symptoms
- Intentional rest period or lifestyle change

**Sleep:**
- Increased stress or anxiety interfering with sleep
- Schedule changes, late-night obligations, or work demands
- Poor sleep environment (noise, light, temperature)
- Changes in caffeine, alcohol, or medication
- Possible emerging sleep disorder

**HRV:**
- Overtraining or insufficient recovery between workouts
- Increased psychological stress or anxiety
- Early signs of illness or inflammation
- Poor sleep quality affecting autonomic recovery
- Dietary changes or dehydration

**Resting HR:**
- Reduced cardiovascular fitness from inactivity
- Inadequate recovery or cumulative fatigue
- Early illness or infection developing
- Increased stress or anxiety levels
- Dehydration or changes in medication

---

### 4. **Severity-Aware Action Steps**

Actions scale with alert level:

#### **Level 3 (Watch - 3-6 days)**
1. Check in casually about how they've been feeling
2. Continue monitoring for another 2-3 days
3. No immediate action needed unless accompanied by other symptoms
4. Revisit if pattern persists into next week

#### **Level 7 (Attention - 7-13 days)**
1. Have a direct conversation today about how they're feeling
2. Look for specific signs: [metric-specific symptoms]
3. Take supportive action: [metric-specific recommendation]
4. If pattern continues another week, schedule check-in with healthcare provider

#### **Level 14-21 (Critical - 14+ days)**
1. **Priority conversation TODAY** - ongoing for X days
2. Assess for warning signs: [extensive metric-specific symptom list]
3. Take immediate action: [urgent metric-specific recommendation]
4. **Schedule medical consultation within 3-5 days** if no clear cause or improvement

---

### 5. **Metric-Specific Symptoms to Watch For**

**Steps:**
- Persistent fatigue, pain, low mood, lack of motivation, social withdrawal

**Sleep:**
- Daytime fatigue, irritability, difficulty concentrating, increased caffeine use

**HRV:**
- Persistent fatigue, poor workout recovery, frequent illness, high stress levels

**Resting HR:**
- Feeling unwell, persistent fatigue, difficulty with usual activities, chest discomfort

---

### 6. **Metric-Specific Supportive Actions**

**Steps:**
- Offer to take a short walk together, remove barriers to movement, adjust expectations

**Sleep:**
- Review sleep routine together, adjust evening schedule, create better sleep environment

**HRV:**
- Encourage rest days, reduce training intensity, support stress management

**Resting HR:**
- Ensure adequate hydration, encourage rest, monitor for illness symptoms

---

## Implementation Details

### Data Computation

```typescript
// Compute baseline and recent for ALL 4 metrics
const allMetrics = ["steps", "sleep_minutes", "hrv_ms", "resting_hr"];
const metricsData = allMetrics.map((m) => {
  const vals = valuesFor(m);
  const { baseline, recent } = splitBaselineRecent(vals);
  // baseline = up to 21 days before recent 3-day period
  // recent = average of most recent 3 consecutive days
  const deviation = pctChange(baseline, recent);
  const absoluteChange = recent - baseline;
  
  return {
    name: m,
    current_value: recent,
    baseline_value: baseline,
    percent_change: deviation * 100,
    absolute_change: absoluteChange,
  };
});

// Separate primary from supporting
const primaryMetric = metricsData.find((m) => m.name === metricType);
const supportingMetrics = metricsData.filter((m) => m.name !== metricType);
```

### Pillar Mapping

```typescript
const pillar = (() => {
  switch (metricType) {
    case "steps": return "movement";
    case "sleep_minutes": return "sleep";
    case "hrv_ms":
    case "resting_hr": return "stress";
  }
})();
```

### Consecutive Days Calculation

```typescript
const activeSinceDate = new Date(`${alert.active_since}T00:00:00Z`);
const evaluatedEndDate = new Date(`${evaluatedEnd}T00:00:00Z`);
const consecutiveDays = Math.floor(
  (evaluatedEndDate.getTime() - activeSinceDate.getTime()) / 86400000
) + 1;
```

---

## Prompt Version

Updated from **v3** → **v4**

- v3 = clinical format (generic)
- v4 = metric-specific + severity-aware with all 4 metrics

This triggers fresh AI generation for all alerts.

---

## Example Output

### Alert: Ahmed's steps decreased by 51% over 8 days (Level 7 - Attention)

**Evidence JSON sent to AI:**
```json
{
  "alert": {
    "metric": "steps",
    "pattern": "drop_vs_baseline",
    "pillar": "movement",
    "level": 7,
    "consecutive_days": 8
  },
  "person": { "name": "Ahmed" },
  "primary_metric": {
    "name": "steps",
    "current_value": 4493,
    "baseline_value": 9261,
    "percent_change": -51.4,
    "absolute_change": -4768
  },
  "supporting_metrics": [
    {
      "name": "sleep_minutes",
      "current_value": 462,
      "baseline_value": 372,
      "percent_change": 24.2,
      "absolute_change": 90
    },
    {
      "name": "hrv_ms",
      "current_value": 45,
      "baseline_value": 43,
      "percent_change": 4.7,
      "absolute_change": 2
    },
    {
      "name": "resting_hr",
      "current_value": 62,
      "baseline_value": 64,
      "percent_change": -3.1,
      "absolute_change": -2
    }
  ]
}
```

**Expected AI Output:**

**Clinical Interpretation:**
"A 51% sustained decrease in daily steps (from 9,261 to 4,493 steps) over 8 days is clinically significant. This level of reduction typically indicates injury, illness, lifestyle disruption, or changes in mental health and motivation."

**What the Data Shows:**
"Sleep duration increased from 6.2 to 7.7 hours (24% increase), which may indicate the body is compensating for reduced activity with more rest. Heart rate variability remains relatively stable at 45ms, suggesting no acute cardiovascular stress. Resting heart rate decreased slightly to 62 bpm, consistent with increased rest periods."

**Possible Causes:**
- Injury, pain, or physical limitation affecting mobility
- Illness or recovery from illness
- Major routine disruption (weather, work schedule change, travel)
- Low motivation, mood changes, or depressive symptoms
- Intentional rest period or lifestyle change

**Recommended Actions (Level 7 - Attention):**
1. Have a direct conversation with Ahmed today about how he's feeling physically and emotionally
2. Look for specific signs: persistent fatigue, pain, low mood, lack of motivation, social withdrawal
3. Take supportive action: Offer to take a short walk together, remove barriers to movement, adjust expectations
4. If pattern continues another week, schedule a check-in with healthcare provider

---

## Deployment Steps

### 1. Run Database Migration (if not already run)

The schema already supports these fields from the previous clinical prompt update.

### 2. Deploy Edge Function

```bash
cd supabase
supabase functions deploy miya_insight
```

### 3. Test

The iOS app will automatically use the new format. No iOS changes needed since the UI already handles `clinical_interpretation`, `data_connections`, `possible_causes`, and `action_steps`.

---

## Benefits Over Previous Version

### Before (v3):
- ❌ Generic clinical interpretation
- ❌ Supporting metrics not fully utilized
- ❌ Same tone regardless of severity
- ❌ Generic possible causes
- ❌ Generic action steps

### After (v4):
- ✅ **Metric-specific clinical interpretation** with actual values
- ✅ **All 4 metrics included** (primary + 3 supporting)
- ✅ **Severity-aware urgency** (watch/attention/critical)
- ✅ **Metric-specific possible causes** based on research
- ✅ **Metric-specific action steps** with concrete recommendations
- ✅ **Metric-specific symptoms** to watch for
- ✅ **Absolute values with units** (hours, steps, ms, bpm)
- ✅ **Percentage AND absolute changes** for context

---

## Files Changed

1. ✅ `supabase/functions/miya_insight/index.ts` - Complete restructure
   - New data structure computation (all 4 metrics)
   - Metric-specific prompt templates
   - Severity-aware action steps
   - Prompt version bumped to v4

**Status:** ✅ Ready to deploy (no linter errors)

---

## Notes

- Old cached insights (v3) will automatically be regenerated with v4 format
- The iOS UI already supports the clinical format (no changes needed)
- Message suggestions remain unchanged
- Confidence calculation unchanged
- Database schema unchanged (already supports these fields)

---

## Testing Checklist

After deployment, test with:

1. ✅ Steps alert (movement) - verify step-specific interpretation
2. ✅ Sleep alert - verify sleep-specific causes and actions
3. ✅ HRV alert - verify stress/recovery language
4. ✅ Resting HR alert - verify cardiovascular fitness language
5. ✅ Level 3 alert - verify casual tone
6. ✅ Level 7 alert - verify direct conversation request
7. ✅ Level 14+ alert - verify urgent language and medical consultation mention
8. ✅ Supporting metrics - verify all 4 metrics appear with absolute values
