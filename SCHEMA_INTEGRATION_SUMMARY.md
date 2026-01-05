# Vitality Scoring Schema - Integration Complete ✅

## What Was Implemented

### 1. Core Schema File: `ScoringSchema.swift`

**Location**: `Miya Health/ScoringSchema.swift`

**Contents**:
- ✅ 3 pillar enums (Sleep, Movement, Stress)
- ✅ 10 sub-metric enums
- ✅ Scoring direction enum (higherIsBetter, lowerIsBetter, optimalRange)
- ✅ Complete benchmark definitions for all sub-metrics
- ✅ Weight definitions matching specification:
  - Sleep: 33% (sub-metrics: 40%, 30%, 20%, 10%)
  - Movement: 33% (sub-metrics: 40%, 30%, 30%)
  - Stress: 34% (sub-metrics: 40%, 40%, 20%)
- ✅ Type-safe access via extensions
- ✅ Debug validation logic
- ✅ Convenience helpers for lookups

**Lines of code**: ~430 lines

---

### 2. App Integration: `Miya_HealthApp.swift`

**Changes**:
- ✅ Added schema validation on app launch (debug builds only)
- ✅ Validation runs automatically when you run in simulator/debugger
- ✅ Optional examples can be enabled with one line uncomment

**Console output on app launch** (debug builds):
```
🔍 Validating vitality scoring schema...
  ✅ Pillar weights sum to 1.0
  ✅ Sleep: 4 sub-metrics, weights sum to 1.0
  ✅ Movement: 3 sub-metrics, weights sum to 1.0
  ✅ Stress: 3 sub-metrics, weights sum to 1.0
✅ Vitality scoring schema validated successfully
   Total pillars: 3
   Total sub-metrics: 10
```

---

### 3. Examples & Documentation

**Files Created**:
1. `ScoringSchemaExamples.swift` - Demonstrates how to use the schema
2. `VITALITY_SCORING_SCHEMA.md` - Complete documentation
3. `SCHEMA_INTEGRATION_SUMMARY.md` - This file

**Examples Include**:
- Schema overview printer
- Sub-metric access patterns
- Weight contribution analysis
- Sample day scoring (conceptual)
- Complete metric listing

---

## How to Test

### Option 1: Quick Validation (Automatic)
1. Open `Miya Health.xcodeproj` in Xcode
2. Run in simulator (Cmd+R)
3. Check console for validation output
4. ✅ If you see "✅ Vitality scoring schema validated successfully", it's working!

### Option 2: See Examples
1. Open `Miya_HealthApp.swift`
2. Uncomment line: `// ScoringSchemaExamples.runAllExamples()`
3. Run in simulator
4. Check console for detailed schema breakdown

### Option 3: Interactive Testing
Add this to any view's `.onAppear`:
```swift
#if DEBUG
VitalitySchemaInfo.printSchema()

// Or test specific metrics:
if let def = VitalitySubMetric.sleepDuration.definition {
    print("Sleep Duration benchmarks: \(def.benchmarks)")
}
#endif
```

---

## Schema Overview

### Complete Structure

```
VITALITY SCORE (0-100)
│
├── SLEEP PILLAR (33%)
│   ├── Sleep Duration (40%) ↑
│   │   Benchmarks: 8h excellent → 5h poor
│   ├── Restorative Sleep % (30%) ⊕
│   │   Optimal: 20-25%
│   ├── Sleep Efficiency (20%) ↑
│   │   Benchmarks: 95% excellent → 65% poor
│   └── Awake % (10%) ↓
│       Benchmarks: <2% excellent → >15% poor
│
├── MOVEMENT PILLAR (33%)
│   ├── Movement Minutes (40%) ↑
│   │   Benchmarks: 150min excellent → 30min poor
│   ├── Steps (30%) ↑
│   │   Benchmarks: 10k excellent → 2.5k poor
│   └── Active Calories (30%) ↑
│       Benchmarks: 600 excellent → 150 poor
│
└── STRESS PILLAR (34%)
    ├── HRV (40%) ↑
    │   Benchmarks: 65ms excellent → 20ms poor
    ├── Resting Heart Rate (40%) ↓
    │   Benchmarks: <60 excellent → >90 poor
    └── Breathing Rate (20%) ⊕
        Optimal: 12-20 breaths/min

Legend:
↑ = Higher is better
↓ = Lower is better
⊕ = Optimal range
```

---

## Weight Contribution to Total Vitality

Each sub-metric's maximum contribution to the total vitality score:

### From Sleep (33% of vitality):
- Sleep Duration: **13.2%** of total vitality (33% × 40%)
- Restorative Sleep: **9.9%** of total vitality (33% × 30%)
- Sleep Efficiency: **6.6%** of total vitality (33% × 20%)
- Awake %: **3.3%** of total vitality (33% × 10%)

### From Movement (33% of vitality):
- Movement Minutes: **13.2%** of total vitality (33% × 40%)
- Steps: **9.9%** of total vitality (33% × 30%)
- Active Calories: **9.9%** of total vitality (33% × 30%)

### From Stress (34% of vitality):
- HRV: **13.6%** of total vitality (34% × 40%)
- Resting Heart Rate: **13.6%** of total vitality (34% × 40%)
- Breathing Rate: **6.8%** of total vitality (34% × 20%)

**Total: 100.0%** ✅

---

## Code Examples

### Example 1: Access Pillar Information
```swift
// Get sleep pillar
if let sleepPillar = VitalityPillar.sleep.definition {
    print("Sleep pillar weight: \(sleepPillar.weightInVitality)")
    print("Sub-metrics: \(sleepPillar.subMetrics.count)")
}

// Iterate all pillars
for pillar in vitalityScoringSchema {
    print("\(pillar.id.displayName): \(pillar.weightInVitality * 100)%")
}
```

### Example 2: Access Sub-Metric Details
```swift
// Get specific sub-metric
if let def = VitalitySubMetric.steps.definition {
    print("Steps parent: \(def.parentPillar.displayName)")
    print("Steps weight: \(def.weightWithinPillar)")
    print("Steps unit: \(VitalitySubMetric.steps.unit)")
    print("Excellent benchmark: \(def.benchmarks.excellent ?? 0)")
}

// Get all sleep sub-metrics
let sleepMetrics = VitalityPillar.sleep.subMetrics
for metric in sleepMetrics {
    print("\(metric.id.displayName) (\(metric.weightWithinPillar * 100)%)")
}
```

### Example 3: Validate Benchmark Logic (Future Scoring)
```swift
// This pattern will be used in the scoring engine (Phase 2)
func getPerformanceLevel(for metric: VitalitySubMetric, value: Double) -> String {
    guard let def = metric.definition else { return "Unknown" }
    
    switch def.scoringDirection {
    case .higherIsBetter:
        if let excellent = def.benchmarks.excellent, value >= excellent {
            return "Excellent"
        } else if let good = def.benchmarks.good, value >= good {
            return "Good"
        } else if let fair = def.benchmarks.fair, value >= fair {
            return "Fair"
        } else {
            return "Needs Improvement"
        }
    case .lowerIsBetter:
        if let excellent = def.benchmarks.excellent, value <= excellent {
            return "Excellent"
        }
        // ... similar logic
    case .optimalRange:
        if let min = def.benchmarks.optimalMin,
           let max = def.benchmarks.optimalMax,
           value >= min && value <= max {
            return "Optimal"
        }
        // ... distance from optimal
    }
    
    return "Unknown"
}

// Usage:
let sleepHours = 7.5
let performance = getPerformanceLevel(for: .sleepDuration, value: sleepHours)
print("7.5 hours of sleep is \(performance)")  // "Good"
```

---

## What Changed vs. Old System

### Old System (`VitalityCalculator.swift` - Still Active)
```swift
// Threshold-based (discrete buckets)
static func sleepPoints(hours: Double) -> Int {
    switch hours {
    case 7.0...9.0: return 35
    case 6.0..<7.0, 9.0..<10.0: return 25
    case 5.0..<6.0, 10.0..<11.0: return 15
    default: return 5
    }
}
```

**Limitations**:
- Fixed thresholds (7.5h and 7.9h both get 35pts)
- Only 3 metrics (sleep hours, steps, HRV/RHR)
- No sub-metric granularity
- Hardcoded weights
- No personalization

### New System (Schema-Based - Ready for Implementation)
```swift
// Continuous scoring (will be implemented in Phase 2)
// Example: 7.5h → interpolate between 7h (good=75pts) and 8h (excellent=100pts)
// Result: ~94/100 instead of fixed 35pts

// Based on schema:
let sleepDef = VitalitySubMetric.sleepDuration.definition
// excellent: 8h, good: 7h, fair: 6h, poor: 5h
```

**Advantages**:
- Continuous scoring (7.5h gets proportional score)
- 10 sub-metrics across 3 pillars
- Configurable in one place
- Type-safe access
- Ready for personalization

---

## Validation Checklist

Run these checks to ensure schema is working:

### ✅ Structural Validation
- [x] Pillar weights sum to 1.0 (33% + 33% + 34%)
- [x] Sleep sub-metric weights sum to 1.0 (40% + 30% + 20% + 10%)
- [x] Movement sub-metric weights sum to 1.0 (40% + 30% + 30%)
- [x] Stress sub-metric weights sum to 1.0 (40% + 40% + 20%)

### ✅ Benchmark Validation
- [x] "Higher is better" metrics: excellent ≥ good ≥ fair ≥ poor
- [x] "Lower is better" metrics: excellent ≤ good ≤ fair ≤ poor
- [x] "Optimal range" metrics: min < max

### ✅ Code Integration
- [x] Schema file compiles without errors
- [x] No linter warnings
- [x] Extensions work correctly
- [x] Validation runs on app launch
- [x] Examples demonstrate all features

---

## Next Steps (Not Yet Implemented)

### Phase 2: Scoring Engine (Next)
**Goal**: Transform raw values → 0-100 scores using benchmarks

**Implementation Plan**:
1. Create `VitalityScoringEngine.swift`
2. Implement continuous scoring functions:
   - `scoreHigherIsBetter(value, benchmarks) → 0-100`
   - `scoreLowerIsBetter(value, benchmarks) → 0-100`
   - `scoreOptimalRange(value, benchmarks) → 0-100`
3. Implement sub-metric scoring:
   - `scoreSubMetric(metric, rawValue) → 0-100`
4. Implement pillar aggregation:
   - `scorePillar(pillar, subMetricScores) → 0-100`
5. Implement total vitality:
   - `scoreVitality(pillarScores) → 0-100`

**Testing Strategy**:
- Run parallel with old `VitalityCalculator`
- Compare outputs for same data
- Validate new scores make clinical sense

### Phase 3: Integration with Dashboard
**Goal**: Replace old calculator with new one

**Changes**:
1. Update `DashboardView` to use new scoring
2. Show pillar breakdowns (Sleep: 72/100, Movement: 85/100, etc.)
3. Show sub-metric details on tap
4. Update charts to use new scores

### Phase 4: Personalization
**Goal**: Adjust benchmarks based on age, risk profile

**Implementation**:
1. Add age adjustment functions to `MetricBenchmarks`
2. Add risk adjustment functions
3. Integrate with `RiskCalculator` optimal target
4. Show personalized vs. population benchmarks

---

## Files Modified

### Created:
1. `/Miya Health/ScoringSchema.swift` - 430 lines
2. `/Miya Health/ScoringSchemaExamples.swift` - 270 lines
3. `/VITALITY_SCORING_SCHEMA.md` - Full documentation
4. `/SCHEMA_INTEGRATION_SUMMARY.md` - This file

### Modified:
1. `/Miya Health/Miya_HealthApp.swift` - Added schema validation call

### Not Modified (Yet):
- `VitalityCalculator.swift` - Still uses old methodology
- `DashboardView.swift` - Still displays old scores
- `DataManager.swift` - No schema integration yet

---

## Clinical Evidence for Benchmarks

### Sleep Duration (7-9h optimal)
- **Source**: National Sleep Foundation, American Academy of Sleep Medicine
- **Evidence**: Adults 18-64 need 7-9h; <6h or >10h associated with health risks

### HRV (>50ms good, >65ms excellent)
- **Source**: Nunan et al. (2010), Task Force of ESC & NASPE (1996)
- **Evidence**: Higher HRV = better ANS function; age-dependent (decreases with age)

### Steps (10k target)
- **Source**: Tudor-Locke & Bassett (2004), WHO guidelines
- **Evidence**: 10k steps/day → health benefits; 7.5k minimum for adults

### Movement Minutes (150min/week)
- **Source**: WHO Physical Activity Guidelines (2020)
- **Evidence**: 150-300min/week moderate activity reduces disease risk

### Resting HR (<60 excellent)
- **Source**: American Heart Association
- **Evidence**: Lower RHR = better cardiovascular fitness; athletes often 40-60bpm

---

## Debug Commands

Add these anywhere in your code to inspect schema:

```swift
#if DEBUG
// Print complete schema
VitalitySchemaInfo.printSchema()

// Print specific pillar
if let sleep = VitalityPillar.sleep.definition {
    print("Sleep has \(sleep.subMetrics.count) sub-metrics")
}

// List all sub-metrics with units
for metric in VitalitySubMetric.allCases {
    print("\(metric.displayName): \(metric.unit)")
}

// Check weight contribution
for pillar in vitalityScoringSchema {
    for metric in pillar.subMetrics {
        let contribution = pillar.weightInVitality * metric.weightWithinPillar * 100
        print("\(metric.id.displayName): \(String(format: "%.1f", contribution))% of vitality")
    }
}

// Run all examples
ScoringSchemaExamples.runAllExamples()
#endif
```

---

## Success Criteria ✅

### Phase 1 (Complete)
- [x] Schema structure defined
- [x] All weights specified
- [x] All benchmarks defined
- [x] Type-safe access implemented
- [x] Validation logic implemented
- [x] Documentation written
- [x] Examples created
- [x] No compilation errors
- [x] No linter warnings

### Phase 2 (Next)
- [ ] Scoring functions implemented
- [ ] Unit tests written
- [ ] Validates against old system
- [ ] Handles missing data gracefully
- [ ] Performance acceptable (<1ms per score)

---

## Questions & Answers

### Q: Why not just use the old VitalityCalculator?
**A**: The old system is too rigid. It can't handle:
- New metrics (sleep stages, active calories, breathing rate)
- Sub-metric granularity
- Continuous scoring
- Personalization
- Easy configuration changes

### Q: Do I need to change any existing code?
**A**: Not yet! The schema is a **parallel system**. Your old calculator still works. In Phase 2-3, we'll gradually migrate to the new system.

### Q: How do I change the weights?
**A**: Edit `vitalityScoringSchema` in `ScoringSchema.swift`. The validation will catch any errors.

### Q: How do I add a new sub-metric?
**A**: 
1. Add to `VitalitySubMetric` enum
2. Add display name and unit
3. Add `SubMetricDefinition` to appropriate pillar
4. Adjust other weights to maintain 1.0 sum
5. Run app to validate

### Q: Can I personalize benchmarks per user?
**A**: Yes, in Phase 4! The structure supports it:
```swift
struct MetricBenchmarks {
    // Future: Add these
    let ageAdjustment: ((Int) -> Double)?
    let riskAdjustment: ((RiskBand) -> Double)?
}
```

---

## Support

If you see errors:
1. Check console for validation messages
2. Verify pillar weights sum to 1.0
3. Verify sub-metric weights sum to 1.0 per pillar
4. Check that benchmarks are in correct order

For questions:
- See `VITALITY_SCORING_SCHEMA.md` for detailed docs
- Run `ScoringSchemaExamples.runAllExamples()` for examples
- Check `ScoringSchema.swift` for implementation

---

## Conclusion

✅ **Phase 1 is complete!** You now have:
- A robust, validated scoring schema
- Type-safe access to all metrics
- Complete documentation
- Working examples
- Foundation for future scoring engine

The schema is **ready to use** and **ready to extend**.

Next up: **Phase 2 - Build the scoring engine!** 🚀

