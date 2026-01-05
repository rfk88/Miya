# Vitality Scoring Schema

## Overview

The vitality scoring schema is the **single source of truth** for how Miya Health calculates vitality scores. It defines the structure, weights, benchmarks, and scoring methodology for all health metrics.

---

## 📁 Files Added

### `ScoringSchema.swift`
- **Location**: `Miya Health/ScoringSchema.swift`
- **Purpose**: Defines the complete scoring structure
- **Contains**:
  - Enums for pillars, sub-metrics, and scoring directions
  - Structs for definitions and benchmarks
  - The complete schema with all data
  - Validation helpers
  - Convenience extensions

### `Miya_HealthApp.swift` (Modified)
- Added schema validation on app launch (debug builds only)
- Ensures schema integrity every time you run in simulator/debug

---

## 🏗️ Schema Structure

### Top Level: Vitality Score (0-100)

```
Vitality Score = 0-100
├── Sleep Pillar (33%)
├── Movement Pillar (33%)
└── Stress Pillar (34%)
```

### Pillars & Sub-Metrics

#### Sleep Pillar (33% of Vitality)
- **Sleep Duration** (40% of Sleep)
  - Unit: hours
  - Direction: Higher is better
  - Benchmarks: 8h excellent, 7h good, 6h fair, 5h poor
  
- **Restorative Sleep %** (30% of Sleep)
  - Unit: %
  - Direction: Optimal range
  - Benchmarks: 20-25% optimal range (REM + Deep)
  
- **Sleep Efficiency** (20% of Sleep)
  - Unit: %
  - Direction: Higher is better
  - Benchmarks: 95% excellent, 85% good, 75% fair, 65% poor
  
- **Awake %** (10% of Sleep)
  - Unit: %
  - Direction: Lower is better
  - Benchmarks: <2% excellent, 2-5% good, 5-10% fair, >15% poor

#### Movement Pillar (33% of Vitality)
- **Movement Minutes** (40% of Movement)
  - Unit: minutes
  - Direction: Higher is better
  - Benchmarks: 150min excellent, 100min good, 60min fair, 30min poor
  
- **Steps** (30% of Movement)
  - Unit: steps
  - Direction: Higher is better
  - Benchmarks: 10k excellent, 7.5k good, 5k fair, 2.5k poor
  
- **Active Calories** (30% of Movement)
  - Unit: kcal
  - Direction: Higher is better
  - Benchmarks: 600 excellent, 450 good, 300 fair, 150 poor

#### Stress Pillar (34% of Vitality)
- **HRV** (40% of Stress)
  - Unit: ms
  - Direction: Higher is better
  - Benchmarks: 65ms excellent, 50ms good, 35ms fair, 20ms poor
  
- **Resting Heart Rate** (40% of Stress)
  - Unit: bpm
  - Direction: Lower is better
  - Benchmarks: <60 excellent, 60-70 good, 70-80 fair, >90 poor
  
- **Breathing Rate** (20% of Stress)
  - Unit: breaths/min
  - Direction: Optimal range
  - Benchmarks: 12-20 breaths/min optimal

---

## 🔧 How to Use the Schema

### Accessing Pillar Information

```swift
// Get all pillars
for pillar in vitalityScoringSchema {
    print("\(pillar.id.displayName): \(pillar.weightInVitality * 100)%")
}

// Get specific pillar
if let sleepPillar = VitalityPillar.sleep.definition {
    print("Sleep pillar has \(sleepPillar.subMetrics.count) sub-metrics")
}
```

### Accessing Sub-Metric Information

```swift
// Get sub-metric definition
if let def = VitalitySubMetric.sleepDuration.definition {
    print("Sleep Duration:")
    print("  Parent: \(def.parentPillar.displayName)")
    print("  Weight: \(def.weightWithinPillar * 100)%")
    print("  Direction: \(def.scoringDirection)")
    print("  Excellent: \(def.benchmarks.excellent ?? 0) \(VitalitySubMetric.sleepDuration.unit)")
}

// Get all sub-metrics for a pillar
let sleepMetrics = VitalityPillar.sleep.subMetrics
for metric in sleepMetrics {
    print("\(metric.id.displayName): \(metric.weightWithinPillar * 100)%")
}
```

### Debugging

```swift
// Print complete schema (debug builds only)
#if DEBUG
VitalitySchemaInfo.printSchema()
#endif
```

---

## ✅ What's Working

1. **Schema is defined**: All pillars, sub-metrics, weights, and benchmarks are in place
2. **Validation runs on app launch**: Debug builds automatically validate schema integrity
3. **Type-safe access**: Use enums and extensions to access schema data
4. **Future-proof structure**: Ready for scoring engine integration

---

## 🚧 What's Next (Not Yet Implemented)

### Phase 2: Scoring Engine

Create `VitalityScoringEngine.swift` to:
- Transform raw metric values → 0-100 sub-metric scores using benchmarks
- Implement continuous scoring (not threshold-based)
- Support three scoring directions:
  - **higherIsBetter**: Linear interpolation (e.g., 8,752 steps → 87.52/100)
  - **lowerIsBetter**: Inverse linear interpolation (e.g., 65 bpm → 100/100, 90 bpm → 20/100)
  - **optimalRange**: Distance from optimal range (e.g., 16 breaths/min → 100/100, 25 breaths/min → 60/100)

### Phase 3: Pillar Score Aggregation

- Calculate pillar scores from weighted sub-metric scores
- Calculate total vitality score from weighted pillar scores
- Handle missing data gracefully (partial scoring)

### Phase 4: Integration with Existing System

- Replace hardcoded thresholds in `VitalityCalculator.swift`
- Use schema-based scoring instead of threshold buckets
- Maintain backward compatibility during migration

### Phase 5: Personalization

- Age-adjusted benchmarks (e.g., 65-year-old needs 7h vs. 25-year-old needs 8h)
- Risk-adjusted benchmarks (high-risk users get more achievable targets)
- Integration with `RiskCalculator` optimal vitality target

### Phase 6: UI Integration

- Show pillar breakdowns in dashboard
- Display sub-metric scores and benchmarks
- Progress indicators toward personal benchmarks
- Trend analysis over time

---

## 🔍 Validation

The schema validates itself on every debug build launch. It checks:

1. ✅ Pillar weights sum to 1.0 (33% + 33% + 34% = 100%)
2. ✅ Sub-metric weights sum to 1.0 within each pillar
3. ✅ Benchmark values make sense (excellent ≥ good for "higher is better")
4. ✅ Optimal ranges are valid (min < max)

**Console output on app launch (debug builds):**
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

## 📊 Current vs. New Methodology

### Current (VitalityCalculator.swift)
- **Threshold-based**: 7-9h sleep = 35pts, 6-7h = 25pts (discrete buckets)
- **Limited metrics**: Only sleep hours, steps, HRV/RHR
- **Fixed weights**: Sleep 35%, Movement 35%, Stress 30%
- **No sub-metrics**: Can't distinguish sleep quality, movement intensity
- **No personalization**: Same thresholds for everyone

### New (Schema-Based)
- **Continuous scoring**: 7.5h sleep gets proportional score between 7h and 8h benchmarks
- **Rich metrics**: 10 sub-metrics across 3 pillars
- **Configurable weights**: Defined in schema, easy to adjust
- **Granular breakdown**: See which sub-metrics are strong/weak
- **Personalization-ready**: Benchmarks can be adjusted per user

---

## 🎯 Design Decisions

### Why these weights?

- **Sleep 33%**: Critical for recovery and health
- **Movement 33%**: Critical for cardiovascular health
- **Stress 34%**: Critical for long-term resilience (slight edge for importance)

### Why continuous scoring?

- **More accurate**: 8,752 steps deserves more credit than 7,500 steps
- **More motivating**: Small improvements show progress
- **Clinical relevance**: Real health outcomes are continuous, not threshold-based

### Why these benchmarks?

- **Evidence-based**: WHO guidelines, clinical research, wearable data standards
- **Achievable**: Targets are aspirational but realistic for most people
- **Will be calibrated**: Future versions will validate against real user data

---

## 🛠️ Developer Notes

### Adding a new sub-metric

1. Add enum case to `VitalitySubMetric`
2. Add display name to `displayName` computed property
3. Add unit to `unit` computed property
4. Add `SubMetricDefinition` to appropriate pillar in `vitalityScoringSchema`
5. Adjust other sub-metric weights to maintain 1.0 sum
6. Run app to validate schema

### Changing weights

1. Update `weightInVitality` for pillars (must sum to ~1.0)
2. Update `weightWithinPillar` for sub-metrics (must sum to 1.0 per pillar)
3. Run app to validate schema

### Changing benchmarks

1. Update `MetricBenchmarks` in schema definition
2. No validation needed (but consider clinical evidence)

---

## 📚 References

- WHO Physical Activity Guidelines
- National Sleep Foundation sleep duration recommendations
- Heart Rate Variability research (Nunan et al., 2010)
- Apple Health metrics documentation
- Vitality Health UK scoring methodology

---

## ✨ Next Step

To implement the scoring engine, see the plan in the main project README or ask:

> "Implement Phase 2: Create the scoring engine that uses the schema to compute vitality scores"

The schema is now ready and validated! 🎉

