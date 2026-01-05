# Optimal Target Comparison: Old vs New

## Quick Reference Table

| Age | Risk Band | Old Target | New Target | Difference | Notes |
|-----|-----------|------------|------------|------------|-------|
| 25 | Low | 85 | **90** | +5 | Young, healthy → ambitious goal |
| 25 | Moderate | 80 | **85** | +5 | Young, moderate risk |
| 25 | High | 75 | **80** | +5 | Young, high risk |
| 25 | Critical | 65 | **70** | +5 | Young, critical risk |
| 35 | Low | 85 | **90** | +5 | Still young group |
| 35 | Moderate | 80 | **85** | +5 | |
| 50 | Low | 80 | **90** | +10 | Middle age, healthy → higher goal |
| 50 | Moderate | 75 | **85** | +10 | Middle age, moderate risk |
| 50 | High | 70 | **80** | +10 | Middle age, high risk |
| 50 | Critical | 60 | **70** | +10 | Middle age, critical risk |
| 68 | Low | 75 | **90** | +15 | Senior, healthy → much higher goal |
| 68 | Moderate | 70 | **85** | +15 | Senior, moderate risk |
| 68 | High | 65 | **80** | +15 | Senior, high risk |
| 68 | Critical | 55 | **70** | +15 | Senior, critical risk |
| 78 | Low | 70 | **90** | +20 | Elderly, healthy → significantly higher |
| 78 | Moderate | 65 | **85** | +20 | Elderly, moderate risk |
| 78 | High | 60 | **80** | +20 | Elderly, high risk |
| 78 | Very High | 55 | **75** | +20 | Elderly, very high risk |
| 78 | Critical | 50 | **70** | +20 | Elderly, critical risk |

---

## Key Insights

### 1. Older Users Get Higher Goals
**Old system:** 78-year-old with low risk → target 70/100
**New system:** 78-year-old with low risk → target 90/100

**Why this is fair:**
- The scoring engine already adjusts for age (30-50ms HRV is optimal for elderly vs 60-80ms for young)
- A healthy 78-year-old should aim high *for their age*
- Age shouldn't be a penalty twice (once in scoring, once in goal)

### 2. Risk Drives Goal Conservatism
**Same age, different risk:**
- 50-year-old, low risk → 90/100
- 50-year-old, high risk → 80/100
- 50-year-old, critical risk → 70/100

**Why this makes sense:**
- Higher cardiovascular risk → more conservative goals
- Prevents overexertion in high-risk individuals
- Still encourages improvement (70 is not a ceiling)

### 3. All Users Can Aim for 100
**Old:** "Your max is 60 because you're 78 and high-risk"
**New:** "Your goal is 80 based on risk, but 100 is your personal max"

**Psychological impact:**
- Growth mindset: "I can improve toward 100"
- Not capped by age: "100 means optimal for MY age"
- Risk is temporary: "As my risk improves, my goal increases"

---

## Real-World Examples

### Example 1: Healthy Senior
**Profile:** 68 years old, low risk (exercises regularly, no conditions)
- **Old target:** 75/100 (capped by age)
- **New target:** 90/100 (ambitious but fair)
- **What 90/100 means for them:**
  - 7-8.5h sleep (age-appropriate)
  - 6-8k steps (age-appropriate)
  - 40-60ms HRV (age-appropriate)
- **Impact:** Encourages them to maintain excellent habits

### Example 2: Young, High Risk
**Profile:** 30 years old, high risk (smoker, high BP, family history)
- **Old target:** 75/100 (risk penalty)
- **New target:** 80/100 (risk penalty, but higher)
- **What 80/100 means for them:**
  - 7-9h sleep (young standards)
  - 8-10k steps (young standards)
  - 60-80ms HRV (young standards)
- **Impact:** Still conservative due to risk, but not artificially capped by age

### Example 3: Elderly, Critical Risk
**Profile:** 80 years old, critical risk (multiple conditions, prior events)
- **Old target:** 50/100 (double penalty: age + risk)
- **New target:** 70/100 (risk penalty only)
- **What 70/100 means for them:**
  - 7-8h sleep (elderly standards)
  - 6-8k steps (elderly standards)
  - 30-50ms HRV (elderly standards)
- **Impact:** More encouraging goal while still being safe

---

## Scoring Engine Integration

### How Age-Specific Scoring Works

**For a 35-year-old:**
- Sleep Duration: 7-9h optimal → 80-100 points
- HRV: 60-80ms optimal → 80-100 points
- Steps: 8-10k optimal → 80-100 points

**For a 78-year-old:**
- Sleep Duration: 7-8h optimal → 80-100 points
- HRV: 30-50ms optimal → 80-100 points
- Steps: 6-8k optimal → 80-100 points

**Both can score 90/100 by meeting their age-appropriate ranges.**

---

## Migration Impact

**Existing users:**
- Next time they view Risk Results, new target is calculated
- Old target in database is overwritten
- No data loss, just updated calculation

**New users:**
- Get new targets immediately
- See updated explanation text
- Experience age-fair system from start

**Database:**
- No schema changes needed
- Same field (`optimal_vitality_target`)
- Just different values (70-90 instead of 50-85)

---

## Summary Table

| Aspect | Old System | New System |
|--------|------------|------------|
| **Target varies by** | Age × Risk (20 values) | Risk only (5 values) |
| **Range** | 50-85 | 70-90 |
| **Age impact** | Lowers target | No impact on target |
| **Age fairness** | Unfair (double penalty) | Fair (age in scoring only) |
| **Messaging** | "Your max is X" | "Your goal is X, max is 100" |
| **Growth mindset** | Limited by age | Unlimited (100 is achievable) |
| **Risk impact** | Lowers target | Lowers target (same) |
| **Complexity** | 4 age groups × 5 risk bands | 5 risk bands |

**The new system is simpler, fairer, and more motivating! 🎉**

