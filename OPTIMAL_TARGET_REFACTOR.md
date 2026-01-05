# ✅ Optimal Vitality Target Refactor Complete

**Date:** December 12, 2025  
**Status:** ✅ Age-Fair Goal System Implemented

---

## What Changed

### Old Methodology (Unfair)
- Optimal target varied by **both age and risk**
- Used age × risk matrix (50-85 range)
- Treated target as a **ceiling** ("max you can achieve")
- Older users had lower "maximum possible" scores
- **Problem:** Age penalty applied twice (in target AND in scoring)

### New Methodology (Fair)
- Optimal target varies by **risk only**
- Uses simple risk factor (70-90% of 100)
- Treats target as a **recommended starting goal**
- All users have same personal max (100/100)
- **Solution:** Age adjustments only in scoring engine (via age-specific ranges)

---

## Implementation

### 1. RiskCalculator.calculateOptimalTarget() - Refactored

**File:** `Miya Health/RiskCalculator.swift`

**New logic:**
```swift
static func calculateOptimalTarget(dateOfBirth: Date, riskBand: RiskBand) -> Int {
    let personalMax = 100
    let factor = riskTargetFactor(for: riskBand)
    let target = Int((Double(personalMax) * factor).rounded())
    return target
}

private static func riskTargetFactor(for band: RiskBand) -> Double {
    switch band {
    case .low:       return 0.90   // 90% of personal max
    case .moderate:  return 0.85   // 85%
    case .high:      return 0.80   // 80%
    case .veryHigh:  return 0.75   // 75%
    case .critical:  return 0.70   // 70%
    }
}
```

**Risk → Target mapping:**
- Low risk: 90/100
- Moderate risk: 85/100
- High risk: 80/100
- Very high risk: 75/100
- Critical risk: 70/100

**What was removed:**
- Age group logic for target calculation
- Age × risk matrix (moved to deprecated comment block)
- Age-based ceiling logic

**What was kept:**
- Function signature (API compatible)
- `dateOfBirth` parameter (kept for compatibility, not used)
- Return type (still returns Int 0-100)

---

### 2. RiskResultsView Explanation Text - Updated

**File:** `Miya Health/RiskResultsView.swift`

**Old text:**
> "This is your personalized optimal vitality score based on your age and risk profile."
> 
> "We use your age group (35-44) and risk band (moderate) to set a realistic target. Higher risk or older age lowers the target slightly to keep goals safe and achievable. Your optimal vitality target is 75/100."

**New text:**
> "This is your recommended vitality goal based on your cardiovascular risk. You can work toward 100/100 as your health improves."
> 
> "For you, 100/100 represents hitting or slightly exceeding the optimal health ranges for your age group (40-59). Based on your cardiovascular risk band (moderate), we recommend starting with a goal of 85/100. This is a safe, realistic target—not a ceiling. As your habits and health improve, you can work toward 100/100, which is your personal maximum."

**Key messaging changes:**
- ✅ "100/100 is your personal max" (age-adjusted via scoring)
- ✅ "Target is a starting goal, not a ceiling"
- ✅ "You can improve toward 100 as health improves"
- ✅ Age group mentioned for context, not as a limitation
- ❌ No longer implies older users have lower max scores

---

## Example Scenarios

### Scenario 1: Young, Low Risk
- **Age:** 25 years
- **Risk Band:** Low
- **Old Target:** 85/100 (from young × low matrix)
- **New Target:** 90/100 (90% of 100)
- **Difference:** +5 points (more ambitious goal)

### Scenario 2: Middle Age, Moderate Risk
- **Age:** 50 years
- **Risk Band:** Moderate
- **Old Target:** 75/100 (from middle × moderate matrix)
- **New Target:** 85/100 (85% of 100)
- **Difference:** +10 points (same risk, higher goal)

### Scenario 3: Elderly, High Risk
- **Age:** 78 years
- **Risk Band:** High
- **Old Target:** 60/100 (from elderly × high matrix)
- **New Target:** 80/100 (80% of 100)
- **Difference:** +20 points (much more ambitious)

### Scenario 4: Senior, Low Risk
- **Age:** 68 years
- **Risk Band:** Low
- **Old Target:** 75/100 (from senior × low matrix)
- **New Target:** 90/100 (90% of 100)
- **Difference:** +15 points (healthy senior gets high goal)

---

## Why This Is Better

### 1. Age Fairness
**Old:** 78-year-old with low risk gets target of 70/100 (age penalty)
**New:** 78-year-old with low risk gets target of 90/100 (same as 25-year-old with low risk)

**Why:** Age-specific scoring ranges already adjust expectations. A 78-year-old hitting 90/100 means they're doing great *for their age* (e.g., 7-8h sleep, 6-8k steps, 30-50ms HRV). A 25-year-old hitting 90/100 means they're doing great *for their age* (e.g., 7-9h sleep, 8-10k steps, 60-80ms HRV).

### 2. Risk-Based Goals
**Old:** Risk and age both lowered the target (double penalty)
**New:** Only risk lowers the target (single, clear factor)

**Why:** Risk is about cardiovascular health, not physical capability. High-risk users need more conservative goals to avoid overexertion, but age is handled separately in the scoring ranges.

### 3. Growth Mindset
**Old:** "Your max is 60/100 because you're older and high-risk"
**New:** "Your goal is 80/100 based on risk, but you can work toward 100/100"

**Why:** Encourages improvement and doesn't artificially cap potential.

### 4. Consistency
**Old:** Target varied by age × risk (20 different values: 4 ages × 5 risk bands)
**New:** Target varies by risk only (5 values: 5 risk bands)

**Why:** Simpler, clearer, easier to explain and understand.

---

## Backward Compatibility

✅ **Fully backward compatible:**
- Function signature unchanged: `calculateOptimalTarget(dateOfBirth:riskBand:) -> Int`
- Database field unchanged: `optimal_vitality_target` (INTEGER)
- Call sites unchanged: All existing calls still work
- Return range: Still 0-100 (now 70-90 instead of 50-85)

**Migration:** None needed. Existing users will get new targets on next risk calculation.

---

## Database Impact

**Fields in `user_profiles`:**
- `date_of_birth` (DATE) — still stored, used for age-specific scoring
- `risk_band` (TEXT) — still stored, used for target calculation
- `optimal_vitality_target` (INTEGER) — still stored, new calculation method

**No schema changes needed.**

---

## Testing

### Before (Old Matrix)
```swift
// 35-year-old, moderate risk
let target = RiskCalculator.calculateOptimalTarget(dob, .moderate)
// Returns: 80/100 (from "young" × moderate)
```

### After (New Risk-Only)
```swift
// 35-year-old, moderate risk
let target = RiskCalculator.calculateOptimalTarget(dob, .moderate)
// Returns: 85/100 (0.85 × 100)

// 78-year-old, moderate risk
let target = RiskCalculator.calculateOptimalTarget(dob, .moderate)
// Returns: 85/100 (same as young person with same risk)
```

**Age-specific scoring still applies:**
- 35-year-old needs 60-80ms HRV for optimal score
- 78-year-old needs 30-50ms HRV for optimal score
- Both can hit 90/100 by meeting *their* age-appropriate ranges

---

## Risk Target Factors

| Risk Band | Factor | Target |
|-----------|--------|--------|
| Low | 90% | 90/100 |
| Moderate | 85% | 85/100 |
| High | 80% | 80/100 |
| Very High | 75% | 75/100 |
| Critical | 70% | 70/100 |

**Range:** 70-90 (was 50-85 with age × risk matrix)

---

## UI Changes

### RiskResultsView

**Main description (under target number):**
- **Old:** "This is your personalized optimal vitality score based on your age and risk profile."
- **New:** "This is your recommended vitality goal based on your cardiovascular risk. You can work toward 100/100 as your health improves."

**Expandable explanation:**
- **Old:** "We use your age group (35-44) and risk band (moderate) to set a realistic target. Higher risk or older age lowers the target slightly to keep goals safe and achievable. Your optimal vitality target is 75/100."
- **New:** "For you, 100/100 represents hitting or slightly exceeding the optimal health ranges for your age group (40-59). Based on your cardiovascular risk band (moderate), we recommend starting with a goal of 85/100. This is a safe, realistic target—not a ceiling. As your habits and health improve, you can work toward 100/100, which is your personal maximum."

**Key messaging:**
- ✅ 100/100 is achievable (personal max)
- ✅ Target is a starting point, not a limit
- ✅ Age mentioned for context, not as penalty
- ✅ Encourages improvement toward 100

---

## Summary

**New risk → factor mapping:**
- Low: 90%, Moderate: 85%, High: 80%, Very High: 75%, Critical: 70%

**New behavior of calculateOptimalTarget():**
- Ignores age for target calculation
- Uses only risk band to determine factor
- Returns `Int((100 × factor).rounded())`
- Range: 70-90 (instead of 50-85)

**Updated explanation text:**
- "100/100 is your personal max based on age-specific ranges"
- "The displayed target is a risk-adjusted starting goal, not a ceiling"
- "You can work toward 100 as your health improves"

**Age fairness achieved:**
- Same risk = same target (regardless of age)
- Age adjustments only in scoring engine (via age-specific metric ranges)
- No double penalty for older users

**The methodology is now fair, clear, and growth-oriented! 🎉**

