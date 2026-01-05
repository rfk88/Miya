# Quick Start: Age-Specific Schema

## ✅ What's Done

Age-specific vitality scoring schema is fully implemented with 10 metrics × 4 age groups = **40 complete range definitions**.

---

## 🚀 Test It Now (30 seconds)

1. Open `Miya Health.xcodeproj` in Xcode
2. Run (Cmd+R)
3. Check console:

**You should see:**
```
🔍 Validating vitality scoring schema...
  ✅ Pillar weights sum to 1.0
  ✅ Sleep: 4 sub-metrics, weights sum to 1.0
  ✅ Movement: 3 sub-metrics, weights sum to 1.0
  ✅ Stress: 3 sub-metrics, weights sum to 1.0
✅ Vitality scoring schema validated successfully
   Total pillars: 3
   Total sub-metrics: 10
   Age groups per sub-metric: 4
```

✅ **If you see "Age groups per sub-metric: 4", it's working!**

---

## 💡 Quick Usage

### Get range for a user
```swift
// User is 45 years old
let range = VitalitySubMetric.sleepDuration.range(forAge: 45)
print("Optimal sleep: \(range.optimalMin)-\(range.optimalMax)h")
// Output: "Optimal sleep: 7.0-9.0h"
```

### Compare by age
```swift
let youngHRV = VitalitySubMetric.hrv.range(forAgeGroup: .young)
let elderlyHRV = VitalitySubMetric.hrv.range(forAgeGroup: .elderly)
print("Young: \(youngHRV.optimalMin)-\(youngHRV.optimalMax)ms")
print("Elderly: \(elderlyHRV.optimalMin)-\(elderlyHRV.optimalMax)ms")
// Output: "Young: 70.0-100.0ms"
// Output: "Elderly: 40.0-70.0ms"
```

### Print detailed ranges
```swift
#if DEBUG
VitalitySchemaInfo.printAgeRanges(for: .sleepDuration)
#endif
```

---

## 📊 What Changed

### Before (single global ranges):
- Sleep Duration: "8h excellent, 7h good, 6h fair, 5h poor"
- Same thresholds for everyone

### After (age-specific ranges):
- Sleep Duration for 25yo: Optimal 7-9h
- Sleep Duration for 75yo: Optimal 7-8h
- Different targets by age group

---

## 🔍 See Examples (2 minutes)

1. Open `Miya_HealthApp.swift`
2. Uncomment this line:
   ```swift
   ScoringSchemaExamples.runAllExamples()
   ```
3. Run app
4. Check console for detailed breakdown

---

## 📚 Documentation

- **`AGE_SPECIFIC_SCHEMA.md`** - Full reference with all ranges
- **`SCHEMA_UPDATE_COMPLETE.md`** - Implementation summary
- **`QUICK_START_AGE_SCHEMA.md`** - This file

---

## 🎯 Key Points

1. **All metrics are age-specific** - 10 metrics × 4 age groups
2. **Evidence-based** - Clinical guidelines + research
3. **Schema-only** - No scoring logic changed yet
4. **Nothing broken** - Old calculator still works
5. **Validated automatically** - Runs on every debug build

---

## 🚫 What Hasn't Changed

- ❌ VitalityCalculator still uses old scoring
- ❌ Dashboard still shows old scores
- ❌ No user-facing changes

**The schema is ready but not yet active.**

---

## 📈 Example: Sleep Duration by Age

| Age | Optimal | Acceptable | Poor |
|-----|---------|------------|------|
| 25 | 7-9h | 6.5-7h, 9-9.5h | <6.5 or >9.5h |
| 45 | 7-9h | 6.5-7h, 9-9.5h | <6.5 or >9.5h |
| 65 | 7-8.5h | 6.5-7h, 8.5-9h | <6.5 or >9h |
| 80 | 7-8h | 6.5-7h, 8-8.5h | <6.5 or >8.5h |

---

## 📈 Example: HRV by Age

| Age | Optimal | Acceptable | Poor |
|-----|---------|------------|------|
| 25 | 70-100ms | 50-70ms | <50ms |
| 45 | 60-90ms | 45-60ms | <45ms |
| 65 | 50-80ms | 40-50ms | <40ms |
| 80 | 40-70ms | 30-40ms | <30ms |

---

## ✨ Summary

✅ Schema is complete and validated  
✅ All 40 range definitions populated  
✅ No linter errors  
✅ Comprehensive documentation  
✅ Ready for Phase 2 (Scoring Engine)  

**Next: Build the scoring engine to use these ranges!** 🚀

---

## 🔧 Debug Commands

Print any metric's ranges:
```swift
VitalitySchemaInfo.printAgeRanges(for: .sleepDuration)
VitalitySchemaInfo.printAgeRanges(for: .hrv)
VitalitySchemaInfo.printAgeRanges(for: .steps)
```

Print complete schema:
```swift
VitalitySchemaInfo.printSchema()
```

Run all examples:
```swift
ScoringSchemaExamples.runAllExamples()
```

