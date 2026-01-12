# Metric-Specific Prompt Quick Reference

## Clinical Interpretation Templates

### Steps (Movement Pillar)
```
"A {X}% sustained decrease in daily steps (from {baseline} to {current} steps) 
over {days} days is clinically significant. This level of reduction typically 
indicates injury, illness, lifestyle disruption, or changes in mental health 
and motivation."
```

### Sleep Minutes (Sleep Pillar)
```
"A {X}% decrease in sleep duration (from {baseline_hours} to {current_hours} hours) 
over {days} days is concerning. Chronic sleep restriction increases cardiovascular 
and metabolic health risks and often signals stress, schedule changes, or 
emerging sleep disorders."
```

### HRV (Stress Pillar)
```
"A {X}% drop in heart rate variability (from {baseline}ms to {current}ms) 
over {days} days indicates increased physiological stress. Lower HRV is 
associated with poor recovery, illness, overtraining, or psychological stress."
```

### Resting HR (Stress Pillar)
```
"A {X}% increase in resting heart rate (from {baseline} to {current} bpm) 
over {days} days suggests reduced cardiovascular fitness, inadequate recovery, 
or potential illness. Elevated resting heart rate is an early warning sign 
the body isn't recovering properly."
```

---

## Possible Causes by Metric

### Steps
1. Injury, pain, or physical limitation affecting mobility
2. Illness or recovery from illness
3. Major routine disruption (weather, work schedule change, travel)
4. Low motivation, mood changes, or depressive symptoms
5. Intentional rest period or lifestyle change

### Sleep Minutes
1. Increased stress or anxiety interfering with sleep
2. Schedule changes, late-night obligations, or work demands
3. Poor sleep environment (noise, light, temperature)
4. Changes in caffeine, alcohol, or medication
5. Possible emerging sleep disorder

### HRV
1. Overtraining or insufficient recovery between workouts
2. Increased psychological stress or anxiety
3. Early signs of illness or inflammation
4. Poor sleep quality affecting autonomic recovery
5. Dietary changes or dehydration

### Resting HR
1. Reduced cardiovascular fitness from inactivity
2. Inadequate recovery or cumulative fatigue
3. Early illness or infection developing
4. Increased stress or anxiety levels
5. Dehydration or changes in medication

---

## Symptoms to Watch For by Metric

| Metric | Symptoms |
|--------|----------|
| **Steps** | Persistent fatigue, pain, low mood, lack of motivation, social withdrawal |
| **Sleep** | Daytime fatigue, irritability, difficulty concentrating, increased caffeine use |
| **HRV** | Persistent fatigue, poor workout recovery, frequent illness, high stress levels |
| **Resting HR** | Feeling unwell, persistent fatigue, difficulty with usual activities, chest discomfort |

---

## Supportive Actions by Metric

| Metric | Action |
|--------|--------|
| **Steps** | Offer to take a short walk together, remove barriers to movement, adjust expectations |
| **Sleep** | Review sleep routine together, adjust evening schedule, create better sleep environment |
| **HRV** | Encourage rest days, reduce training intensity, support stress management |
| **Resting HR** | Ensure adequate hydration, encourage rest, monitor for illness symptoms |

---

## Action Steps by Severity Level

### Level 3 (Watch - 3-6 days)
1. Check in casually with {name} about how they've been feeling
2. Continue monitoring for another 2-3 days to see if pattern continues
3. No immediate action needed unless accompanied by other symptoms
4. Revisit if pattern persists into next week

### Level 7 (Attention - 7-13 days)
1. Have a direct conversation with {name} today about how they're feeling physically and emotionally
2. Look for specific signs: {metric_specific_symptoms}
3. Take supportive action: {metric_specific_action}
4. If pattern continues another week, schedule a check-in with healthcare provider

### Level 14-21 (Critical - 14+ days)
1. Priority conversation with {name} TODAY - this pattern has been ongoing for {consecutive_days} days
2. Assess for warning signs: {metric_specific_symptoms}, changes in appetite, sleep disturbances
3. Take immediate action: {metric_specific_action}
4. Schedule medical consultation within 3-5 days if no clear cause identified or no improvement seen

---

## Data Structure Reference

```typescript
{
  alert: {
    metric: "steps" | "sleep_minutes" | "hrv_ms" | "resting_hr",
    pattern: "drop_vs_baseline" | "rise_vs_baseline",
    pillar: "movement" | "sleep" | "stress",
    level: 3 | 7 | 14 | 21,
    consecutive_days: number
  },
  person: {
    name: string
  },
  primary_metric: {
    name: string,
    current_value: number,
    baseline_value: number,
    percent_change: number,
    absolute_change: number
  },
  supporting_metrics: [
    {
      name: string,
      current_value: number,
      baseline_value: number,
      percent_change: number,
      absolute_change: number
    }
    // ... 3 total supporting metrics
  ],
  context: {
    alert_start_date: "YYYY-MM-DD",
    analysis_date: "YYYY-MM-DD"
  }
}
```

---

## Unit Conversions

- **Steps:** Keep as is (e.g., 8500 steps)
- **Sleep:** Divide by 60 for hours (e.g., 462 min → 7.7 hours)
- **HRV:** Keep as is (e.g., 45 ms)
- **Resting HR:** Keep as is (e.g., 62 bpm)

---

## Tone Guidelines

✅ **DO:**
- Use "may indicate" or "often suggests"
- Speak family-to-family
- Match urgency to severity level
- Include absolute values with units
- Provide concrete, actionable steps

❌ **DON'T:**
- Use "definitely means" or diagnostic language
- Speak doctor-to-patient
- Use medical jargon unnecessarily
- Use only percentages without absolute values
- Provide vague recommendations

---

## Quick Test Matrix

| Metric | Pattern | Level | Expected Language |
|--------|---------|-------|-------------------|
| steps | drop | 7 | "sustained decrease... injury, illness, lifestyle disruption..." |
| sleep_minutes | drop | 7 | "Chronic sleep restriction... cardiovascular risks..." |
| hrv_ms | drop | 14 | "physiological stress... poor recovery, illness..." |
| resting_hr | rise | 3 | "elevated resting heart rate... early warning sign..." |
