# 🧪 Scoring Engine Smoke Test Example

## How to Run

1. Open `Miya Health/Miya_HealthApp.swift`
2. Uncomment this line:
   ```swift
   // ScoringSchemaExamples.runScoringEngineSmokeTest()
   ```
3. Build and run the app
4. Check the Xcode console output

---

## Expected Console Output

```
════════════════════════════════════════════════════════════
VITALITY SCORING ENGINE SMOKE TEST
════════════════════════════════════════════════════════════

Input:
  Age: 35 (Young (< 40))
  Sleep: 6.0h, 30.0% restorative, 85.0% efficiency, 10.0% awake
  Movement: 40.0min, 9000 steps, 450.0 kcal
  Stress: 55.0ms HRV, 62.0 bpm RHR, 15.0 breaths/min

Output:
  Total Vitality: XX/100

  Sleep Pillar: XX/100
    • Sleep Duration: 6.0 hours → XX/100
    • Restorative Sleep %: 30.0 % → XX/100
    • Sleep Efficiency: 85.0 % → XX/100
    • Awake %: 10.0 % → XX/100

  Movement Pillar: XX/100
    • Movement Minutes: 40.0 minutes → XX/100
    • Steps: 9000.0 steps → XX/100
    • Active Calories: 450.0 kcal → XX/100

  Stress Pillar: XX/100
    • HRV: 55.0 ms → XX/100
    • Resting Heart Rate: 62.0 bpm → XX/100
    • Breathing Rate: 15.0 breaths/min → XX/100

============================================================
✅ Smoke test complete
============================================================
```

---

## Expected Score Interpretation (35-year-old)

### 🛏️ Sleep Pillar

| Metric | Raw Value | Age Group Target | Expected Score Range | Reasoning |
|--------|-----------|------------------|----------------------|-----------|
| **Sleep Duration** | 6.0h | 7.0-9.0h optimal<br>6.5-7.0h acceptable | **~60/100** | Below optimal, in acceptable-low range |
| **Restorative Sleep %** | 30% | 35-45% optimal<br>30-35% acceptable | **~50/100** | At lower end of acceptable |
| **Sleep Efficiency** | 85% | 88-95% optimal<br>85-88% acceptable | **~70/100** | In acceptable range |
| **Awake %** | 10% | 1-3% optimal<br>3-5% acceptable | **~10/100** | Poor - way above acceptable |

**Sleep Pillar Score:** ~45/100 (weighted average)
- Duration (40% weight) × 60 = 24
- Restorative (30% weight) × 50 = 15
- Efficiency (20% weight) × 70 = 14
- Awake (10% weight) × 10 = 1
- **Total: 54/100**

---

### 🏃 Movement Pillar

| Metric | Raw Value | Age Group Target | Expected Score Range | Reasoning |
|--------|-----------|------------------|----------------------|-----------|
| **Movement Minutes** | 40 min | 22-43 min optimal | **~95/100** | Near top of optimal range |
| **Steps** | 9,000 | 8,000-10,000 optimal | **~85/100** | Middle of optimal range |
| **Active Calories** | 450 kcal | 300-600 optimal | **~95/100** | Upper-middle of optimal |

**Movement Pillar Score:** ~90/100 (weighted average)
- Movement Mins (40% weight) × 95 = 38
- Steps (30% weight) × 85 = 25.5
- Active Cal (30% weight) × 95 = 28.5
- **Total: 92/100**

---

### 😌 Stress Pillar

| Metric | Raw Value | Age Group Target | Expected Score Range | Reasoning |
|--------|-----------|------------------|----------------------|-----------|
| **HRV** | 55 ms | 60-80 ms optimal<br>50-60 acceptable | **~75/100** | In acceptable range, close to optimal |
| **Resting Heart Rate** | 62 bpm | 50-65 optimal | **~95/100** | In optimal range, near upper bound |
| **Breathing Rate** | 15 breaths/min | 12-18 optimal | **~85/100** | In optimal range, middle |

**Stress Pillar Score:** ~85/100 (weighted average)
- HRV (40% weight) × 75 = 30
- RHR (40% weight) × 95 = 38
- BR (20% weight) × 85 = 17
- **Total: 85/100**

---

## 🎯 Total Vitality Score

```
Total = (Sleep × 33%) + (Movement × 33%) + (Stress × 34%)
Total = (54 × 0.33) + (92 × 0.33) + (85 × 0.34)
Total = 17.82 + 30.36 + 28.9
Total = 77/100
```

---

## 💡 Insights from This Sample

### Strengths
- ✅ **Movement is excellent** (92/100) - well above targets
- ✅ **Stress management is good** (85/100) - RHR and breathing are optimal
- ✅ **Total vitality is acceptable** (77/100)

### Areas for Improvement
- ⚠️ **Sleep is poor** (54/100) - main drag on overall score
  - 🚨 **Critical:** Awake % is way too high (10% vs 3% target)
  - ⚠️ Sleep duration is below optimal (6h vs 7-9h target)
  - ⚠️ Restorative sleep % is at lower acceptable bound

### Recommendations
1. **Priority 1:** Reduce sleep fragmentation (awake %)
   - Current: 10% | Target: 1-3% | Impact: HIGH (10% pillar weight)
2. **Priority 2:** Increase sleep duration to 7-9 hours
   - Current: 6h | Target: 7-9h | Impact: HIGHEST (40% pillar weight)
3. **Priority 3:** Improve REM + Deep sleep
   - Current: 30% | Target: 35-45% | Impact: MEDIUM (30% pillar weight)

---

## 🔄 What-If Scenarios

### If sleep was fixed to targets:
```
New Sleep: Duration 7.5h, Restorative 38%, Efficiency 90%, Awake 2%
New Sleep Pillar: ~92/100 (instead of 54)
New Total Vitality: ~89/100 (instead of 77)
Gain: +12 points overall
```

### If movement decreased to sedentary:
```
New Movement: 15 min, 3000 steps, 150 kcal
New Movement Pillar: ~35/100 (instead of 92)
New Total Vitality: ~58/100 (instead of 77)
Loss: -19 points overall
```

---

## 📊 Score Distribution Guide

| Score Range | Label | Meaning |
|-------------|-------|---------|
| 90-100 | Excellent | Optimal health behaviors |
| 80-89 | Good | Above average, minor improvements possible |
| 70-79 | Fair | Acceptable, some areas need attention |
| 60-69 | Below Average | Multiple areas need improvement |
| 50-59 | Poor | Significant lifestyle changes recommended |
| 0-49 | Very Poor | Urgent health behavior intervention needed |

**Sample Score (77/100) = Fair**
- Good foundation but sleep needs immediate attention

---

## 🧮 Technical Notes

### Scoring Algorithm Applied
- **Linear interpolation** used within each range band
- **Weighted aggregation** at both pillar and total levels
- **Missing data** (nil values) scores 0
- **Rounding** applied to final integer scores

### Age-Specific Adjustments
This test uses age 35 (Young group):
- Higher HRV thresholds (60-80 vs 30-50 for elderly)
- Higher sleep duration optimal range (7-9h vs 7-8h for elderly)
- Higher step targets (8-10k vs 6-8k for seniors)

### Schema Validation
- All 10 metrics have valid ranges for 4 age groups
- Weights sum to 1.0 per pillar (validated on app launch)
- Pillar weights sum to 1.0 (Sleep 33%, Movement 33%, Stress 34%)

---

**Ready to see real output? Uncomment the smoke test and run the app! 🚀**

