# Vitality Scoring Quick Reference

## 📊 Individual Score Calculation

### Step-by-Step Formula

```
ROOK Data → VitalityRawMetrics (10 metrics) → Score 0-100
```

#### 1. Sub-Metric Scoring (0-100 each)

Each metric gets scored based on age-specific ranges:

| Metric | Type | Age Group | Optimal Range | Acceptable Range | Poor Range |
|--------|------|-----------|---------------|------------------|------------|
| Sleep Duration | Optimal Range | 18-40 | 7-9 hrs | 6-7 or 9-10 hrs | <6 or >10 hrs |
| Sleep Duration | Optimal Range | 41-60 | 7-9 hrs | 6-7 or 9-9.5 hrs | <6 or >9.5 hrs |
| Sleep Duration | Optimal Range | 61+ | 7-8 hrs | 6-7 or 8-9 hrs | <6 or >9 hrs |
| Restorative Sleep % | Optimal Range | All | 50-70% | 40-50 or 70-80% | <40 or >80% |
| Sleep Efficiency % | Higher Better | All | 85-100% | 75-85% | <75% |
| Awake % | Lower Better | All | 0-5% | 5-15% | >15% |
| Steps | Higher Better | All | 8000+ | 5000-8000 | <5000 |
| HRV (SDNN) | Higher Better | 18-40 | 50-100ms | 30-50ms | <30ms |
| HRV (SDNN) | Higher Better | 41-60 | 40-80ms | 25-40ms | <25ms |
| HRV (SDNN) | Higher Better | 61+ | 30-60ms | 20-30ms | <20ms |
| Resting HR | Lower Better | All | 50-70 bpm | 70-85 bpm | >85 bpm |

**Scoring Rules:**
- **Optimal Range:** 80-100 points
- **Acceptable Range:** 50-80 points
- **Poor Range:** 0-50 points
- **Missing Data:** 0 points (but excluded from weight calculation)

#### 2. Pillar Aggregation

```
Pillar Score = Σ(SubMetric Score × Weight) / Σ(Weight)
               (only for available sub-metrics)
```

**Sleep Pillar (40% of total)**
- Sleep Duration: 40% within pillar
- Restorative Sleep: 30%
- Sleep Efficiency: 20%
- Awake %: 10%

**Movement Pillar (30% of total)**
- Steps: 40% within pillar
- Movement Minutes: 30%
- Active Calories: 30%

**Stress Pillar (30% of total)**
- HRV: 40% within pillar
- Resting Heart Rate: 30%
- Breathing Rate: 30%

#### 3. Total Score

```
Total Score = Σ(Pillar Score × Pillar Weight) / Σ(Pillar Weight)
              (only for pillars with data)
```

**Minimum Requirement:** At least 2 pillars must have at least 1 sub-metric

---

## 👨‍👩‍👧‍👦 Family Score Calculation

### Formula
```sql
Family Score = ROUND(AVG(member_scores))

WHERE:
  - member.vitality_score_current IS NOT NULL
  - member.vitality_score_updated_at >= NOW() - INTERVAL '3 days'
  - member.is_active = true
```

### Example

| Family Member | Score | Last Updated | Included? |
|--------------|-------|--------------|-----------|
| Dad | 78 | 2 days ago | ✅ Yes |
| Mom | 82 | 1 day ago | ✅ Yes |
| Kid | 65 | Today | ✅ Yes |
| Grandma | 71 | 5 days ago | ❌ No (stale) |
| Uncle | NULL | Never | ❌ No (no data) |

```
Family Score = (78 + 82 + 65) / 3 = 75
Members with Data: 3
Members Total: 5
```

---

## 🎯 Progress Score

Each user has a **personal optimal target** based on:
- Age
- Risk band (from QRISK3 or WHO CVD)
- Current health conditions

```
Progress Score = min(100, (Current Score / Optimal Target) × 100)
```

**Example:**
- Current Score: 72
- Optimal Target: 85
- Progress Score: (72 / 85) × 100 = 84.7 → **85** (rounded)

If current score exceeds target:
- Current Score: 92
- Optimal Target: 85
- Progress Score: **100** (capped)

---

## 📈 Scoring Examples

### Example 1: Complete Data (All Pillars)

**Raw Metrics:**
- Sleep Duration: 7.5 hrs → **90 points**
- Restorative Sleep: 55% → **85 points**
- Sleep Efficiency: 88% → **86 points**
- Awake %: 8% → **70 points**
- Steps: 9500 → **95 points**
- HRV (SDNN): 55ms → **90 points**
- Resting HR: 62 bpm → **95 points**

**Pillar Scores:**
```
Sleep = (90×0.4 + 85×0.3 + 86×0.2 + 70×0.1) / 1.0
      = (36 + 25.5 + 17.2 + 7) / 1.0
      = 85.7 → 86

Movement = 95×0.4 / 0.4  (only steps available)
         = 95

Stress = (90×0.4 + 95×0.3) / 0.7
       = (36 + 28.5) / 0.7
       = 92.1 → 92
```

**Total Score:**
```
Total = (86×0.4 + 95×0.3 + 92×0.3) / 1.0
      = (34.4 + 28.5 + 27.6) / 1.0
      = 90.5 → 91
```

### Example 2: Partial Data (Missing Movement Pillar)

**Raw Metrics:**
- Sleep Duration: 6.5 hrs → **70 points**
- Restorative Sleep: 45% → **65 points**
- HRV: 40ms → **75 points**
- Resting HR: 75 bpm → **70 points**

**Pillar Scores:**
```
Sleep = (70×0.4 + 65×0.3) / 0.7
      = (28 + 19.5) / 0.7
      = 67.9 → 68

Movement = 0 (no data, excluded)

Stress = (75×0.4 + 70×0.3) / 0.7
       = (30 + 21) / 0.7
       = 72.9 → 73
```

**Total Score:**
```
Total = (68×0.4 + 73×0.3) / 0.7  (Movement excluded)
      = (27.2 + 21.9) / 0.7
      = 70.1 → 70
```

### Example 3: Insufficient Data (Only 1 Pillar)

**Raw Metrics:**
- Sleep Duration: 7 hrs → **85 points**
- All other metrics: NULL

**Result:** Score not computed (need at least 2 pillars)

---

## 🔄 Data Freshness Rules

### Individual Score Freshness
- Scores are computed from a **7-30 day rolling window**
- Missing metrics can be **backfilled from previous 7 days** (last-known-value)
- Each sync updates `vitality_score_updated_at`

### Family Score Freshness
- Only includes members updated within **last 3 days**
- Stale scores (>3 days old) are excluded from family average
- This prevents old data from skewing the family score

### Dashboard Refresh
- **Pull-to-refresh:** Recomputes everything
- **Weekly schedule:** Sundays only (or first-time users)
- **Real-time:** When webhook receives new Rook data

---

## 🎨 Dashboard Display Logic

### Vitality Ring Colors
```
Score ≥ 70: Green
Score 50-69: Yellow
Score < 50: Red
```

### Family State Labels
```
Score < 50: "Rebuilding"
Score 50-70: "Steady"
Score > 70: "Strong"
```

### Member Insights
**Support Members** (need help):
- Progress Score < 75% of target
- Message: Neutral, supportive language

**Celebrate Members** (doing well):
- Progress Score ≥ 90% of target
- Message: Encouraging, positive language

---

## 📁 Key Files

| Function | File |
|----------|------|
| Individual scoring | `VitalityScoringEngine.swift` |
| ROOK → Miya mapping | `ROOKDayToMiyaAdapter.swift` |
| Window aggregation | `ROOKWindowAggregator.swift` |
| Family insights | `FamilyVitalitySnapshot.swift` |
| Dashboard UI | `DashboardView.swift` |
| Family score RPC | `get_family_vitality(family_id)` SQL function |
| Webhook handler | `supabase/functions/rook/index.ts` |

---

**Last Updated:** Jan 24, 2026
