# Engine Comparison Guide

## Quick Reference: Old vs New

### Input Data (Same for Both)
```
7 days of data:
- Sleep: 7.2h average
- Steps: 9,057 average
- HRV: 57.1ms average
- Resting HR: 62.4 bpm average
```

---

## Old Engine (VitalityCalculator)

### Scoring Logic
**Sleep (0-35 points):**
- 7-9h → 35 points
- 6-7h or 9-10h → 25 points
- 5-6h or 10-11h → 15 points
- <5h or >11h → 5 points

**Movement (0-35 points):**
- 10,000+ steps → 35 points
- 7,500-10,000 → 25 points
- 5,000-7,500 → 15 points
- <5,000 → 5 points

**Stress (0-30 points):**
- HRV ≥65ms → 30 points
- HRV 50-65ms → 20 points
- HRV <50ms → 10 points

### Sample Output
```
Total: 75/100
Sleep: 30/35 (7.2h → in 7-9h range)
Movement: 25/35 (9,057 steps → in 7.5-10k range)
Stress: 20/30 (57.1ms HRV → in 50-65ms range)
```

---

## New Engine (VitalityScoringEngine)

### Scoring Logic (Age: 35, Young Group)

**Sleep Pillar (33% of total):**
- Sleep Duration: 7.2h
  - Target: 7.0-9.0h optimal
  - Score: ~85/100 (in optimal range)
- Restorative %: nil → 0/100
- Efficiency: nil → 0/100
- Awake %: nil → 0/100
- **Pillar: ~21/100** (weighted avg, many zeros)

**Movement Pillar (33% of total):**
- Movement Minutes: nil → 0/100
- Steps: 9,057
  - Target: 8,000-10,000 optimal
  - Score: ~85/100 (in optimal range)
- Active Calories: nil → 0/100
- **Pillar: ~26/100** (weighted avg, many zeros)

**Stress Pillar (34% of total):**
- HRV: 57.1ms
  - Target: 60-80ms optimal (young)
  - Score: ~72/100 (in acceptable range)
- Resting HR: 62.4 bpm
  - Target: 50-65 optimal
  - Score: ~95/100 (in optimal range)
- Breathing Rate: nil → 0/100
- **Pillar: ~56/100** (weighted avg)

### Sample Output
```
Total: 34/100
Sleep Pillar: 21/100
Movement Pillar: 26/100
Stress Pillar: 56/100
```

---

## Why Scores Are Different

### 1. Missing Data Impact
**Old engine:** Uses only 4 metrics, all present → full score possible

**New engine:** Expects 10 metrics, 6 missing → those score 0
- Missing: Restorative %, Efficiency, Awake %, Movement Mins, Active Cal, Breathing Rate
- Impact: Pulls down pillar averages significantly

### 2. Scoring Method
**Old engine:** Threshold buckets (7-9h = 35 points, period)

**New engine:** Linear interpolation
- 7.2h in 7.0-9.0h range → 80 + ((7.2-7.0)/(9.0-7.0) * 20) = 82 points
- More granular, rewards being in the middle of optimal range

### 3. Age Personalization
**Old engine:** Same thresholds for everyone

**New engine:** Age-specific targets
- Young (<40): Higher HRV targets (60-80ms vs 30-50ms for elderly)
- Different sleep duration ranges by age
- Age-adjusted step goals

### 4. Weighting
**Old engine:** Simple sum (35+35+30 = 100 max)

**New engine:** Weighted pillars (33%+33%+34%)
- Sub-metrics weighted within pillars
- Two-level aggregation

---

## Expected Console Output

### When you upload vitality_sample.json:

```
✅ VitalityJSONParser: Parsed 7 records from JSON

=== New VitalityScoringEngine snapshot ===
Age: 35 AgeGroup: Young (< 40)
Total vitality: 34

Pillar: Sleep score: 21
  SubMetric: Sleep Duration raw: Optional(7.157142857142857) score: 82
  SubMetric: Restorative Sleep % raw: nil score: 0
  SubMetric: Sleep Efficiency raw: nil score: 0
  SubMetric: Awake % raw: nil score: 0

Pillar: Movement score: 26
  SubMetric: Movement Minutes raw: nil score: 0
  SubMetric: Steps raw: Optional(9057.142857142857) score: 85
  SubMetric: Active Calories raw: nil score: 0

Pillar: Stress score: 56
  SubMetric: HRV raw: Optional(57.142857142857146) score: 72
  SubMetric: Resting Heart Rate raw: Optional(62.42857142857143) score: 95
  SubMetric: Breathing Rate raw: nil score: 0

=== End snapshot ===

📊 VitalityCalculator: Parsed 7 records into 7 days
📊 VitalityCalculator: Returning 7 days of vitality data
```

**On screen (old engine):**
```
Current Vitality Score
75/85

Sleep: 30/35
Movement: 25/35
Stress/Recovery: 20/30
```

---

## What This Tells Us

### The Good
✅ New engine is working correctly
✅ Age-specific ranges are being applied
✅ Linear interpolation is more precise
✅ Both engines can run side-by-side

### The Gap
❌ 6 of 10 metrics are missing → scores artificially low
❌ Need to extract from Apple Health XML:
  - Sleep stages (for restorative %)
  - In-bed vs asleep time (for efficiency)
  - Awake time (for fragmentation)
  - Movement minutes
  - Active calories
  - Breathing rate

### The Fix (Future)
1. Parse Apple Health XML more deeply
2. Extract all 10 metrics
3. Populate full `VitalityRawMetrics`
4. New engine scores will be much higher and more accurate

---

## Testing Different Ages

To test age-specific scoring, change the date of birth in onboarding:

**Young (35 years old):**
- HRV target: 60-80ms
- Sleep: 7-9h
- Steps: 8-10k

**Middle (50 years old):**
- HRV target: 50-70ms
- Sleep: 7-9h
- Steps: 8-10k

**Senior (68 years old):**
- HRV target: 40-60ms
- Sleep: 7-8.5h
- Steps: 6-8k

**Elderly (78 years old):**
- HRV target: 30-50ms
- Sleep: 7-8h
- Steps: 6-8k

Upload the same JSON file with different ages → scores will differ based on age-appropriate targets.

---

## Summary

**Current state:**
- Both engines work
- New engine is more sophisticated but penalized by missing data
- Old engine is simpler but complete with available data

**Next step:**
- Extract all 10 metrics from Apple Health
- New engine will then produce accurate, personalized scores
- Can replace old engine once data is complete

**For now:**
- Use console output to verify new engine logic
- Compare scoring approaches
- Validate age-specific ranges are applied correctly

