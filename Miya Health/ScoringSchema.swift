//
//  ScoringSchema.swift
//  Miya Health
//
//  Single source of truth for vitality scoring structure
//  Defines pillars, sub-metrics, weights, age-specific benchmarks, and scoring directions
//

import Foundation

// MARK: - Enums

/// The three top-level pillars of vitality scoring
enum VitalityPillar: String, CaseIterable {
    case sleep
    case movement
    case stress
    
    var displayName: String {
        rawValue.capitalized
    }
}

/// All sub-metrics tracked across pillars
enum VitalitySubMetric: String, CaseIterable {
    // Sleep sub-metrics
    case sleepDuration
    case restorativeSleepPercent
    case sleepEfficiency
    case sleepFragmentationAwakePercent
    
    // Movement sub-metrics
    case movementMinutes
    case steps
    case activeCalories
    
    // Stress sub-metrics
    case hrv
    case restingHeartRate
    case breathingRate
    
    var displayName: String {
        switch self {
        case .sleepDuration: return "Sleep Duration"
        case .restorativeSleepPercent: return "Restorative Sleep %"
        case .sleepEfficiency: return "Sleep Efficiency"
        case .sleepFragmentationAwakePercent: return "Awake %"
        case .movementMinutes: return "Movement Minutes"
        case .steps: return "Steps"
        case .activeCalories: return "Active Calories"
        case .hrv: return "HRV"
        case .restingHeartRate: return "Resting Heart Rate"
        case .breathingRate: return "Breathing Rate"
        }
    }
    
    var unit: String {
        switch self {
        case .sleepDuration: return "hours"
        case .restorativeSleepPercent: return "%"
        case .sleepEfficiency: return "%"
        case .sleepFragmentationAwakePercent: return "%"
        case .movementMinutes: return "minutes"
        case .steps: return "steps"
        case .activeCalories: return "kcal"
        case .hrv: return "ms"
        case .restingHeartRate: return "bpm"
        case .breathingRate: return "breaths/min"
        }
    }
}

/// How a sub-metric should be interpreted for scoring
enum ScoringDirection {
    case higherIsBetter      // e.g., steps, HRV, movement minutes
    case lowerIsBetter       // e.g., resting HR, awake %
    case optimalRange        // e.g., sleep duration, breathing rate, restorative %
}

/// Age groups for age-specific benchmarks
/// Matches the age groups used in RiskCalculator
enum AgeGroup: String, CaseIterable {
    case young      // < 40
    case middle     // 40–<60
    case senior     // 60–<75
    case elderly    // ≥ 75
    
    var displayName: String {
        switch self {
        case .young: return "Under 40"
        case .middle: return "40-59"
        case .senior: return "60-74"
        case .elderly: return "75+"
        }
    }
    
    var ageRange: String {
        switch self {
        case .young: return "< 40 years"
        case .middle: return "40-59 years"
        case .senior: return "60-74 years"
        case .elderly: return "≥ 75 years"
        }
    }
    
    /// Get age group from a person's age
    static func from(age: Int) -> AgeGroup {
        switch age {
        case ..<40: return .young
        case 40..<60: return .middle
        case 60..<75: return .senior
        default: return .elderly
        }
    }
}

// MARK: - Metric Range Definition

/// Defines performance ranges for a metric
/// Can express optimal band, acceptable bands on both sides, and poor thresholds
struct MetricRange {
    // Central optimal band (the target)
    let optimalMin: Double
    let optimalMax: Double
    
    // Acceptable band on the "low" side
    // Values between acceptableLowMin and acceptableLowMax are acceptable but not optimal
    let acceptableLowMin: Double
    let acceptableLowMax: Double
    
    // Acceptable band on the "high" side
    // Values between acceptableHighMin and acceptableHighMax are acceptable but not optimal
    let acceptableHighMin: Double
    let acceptableHighMax: Double
    
    // Poor thresholds
    // Values < poorLowMax are poor (too low)
    // Values > poorHighMin are poor (too high)
    let poorLowMax: Double
    let poorHighMin: Double
    
    /// For metrics that only have one-sided bounds, use this convenience init
    /// Example: HRV (higher is better) - no "too high" concern
    init(
        optimalMin: Double,
        optimalMax: Double,
        acceptableLowMin: Double,
        acceptableLowMax: Double,
        acceptableHighMin: Double,
        acceptableHighMax: Double,
        poorLowMax: Double,
        poorHighMin: Double
    ) {
        self.optimalMin = optimalMin
        self.optimalMax = optimalMax
        self.acceptableLowMin = acceptableLowMin
        self.acceptableLowMax = acceptableLowMax
        self.acceptableHighMin = acceptableHighMin
        self.acceptableHighMax = acceptableHighMax
        self.poorLowMax = poorLowMax
        self.poorHighMin = poorHighMin
    }
}

// MARK: - Age-Specific Benchmarks

/// Container for age-specific metric ranges
/// Must contain ranges for all AgeGroup.allCases
struct AgeSpecificBenchmarks {
    let byAgeGroup: [AgeGroup: MetricRange]
    
    init(byAgeGroup: [AgeGroup: MetricRange]) {
        self.byAgeGroup = byAgeGroup
        
        #if DEBUG
        // Validation: must have ranges for all age groups
        assert(
            byAgeGroup.count == AgeGroup.allCases.count,
            "⚠️ AgeSpecificBenchmarks must contain ranges for all age groups"
        )
        for ageGroup in AgeGroup.allCases {
            assert(
                byAgeGroup[ageGroup] != nil,
                "⚠️ Missing range for age group: \(ageGroup)"
            )
        }
        #endif
    }
    
    /// Get the metric range for a specific age
    func range(forAge age: Int) -> MetricRange {
        let ageGroup = AgeGroup.from(age: age)
        return byAgeGroup[ageGroup]!
    }
    
    /// Get the metric range for a specific age group
    func range(forAgeGroup ageGroup: AgeGroup) -> MetricRange {
        return byAgeGroup[ageGroup]!
    }
}

// MARK: - Definitions

/// Defines a single sub-metric's characteristics
struct SubMetricDefinition {
    let id: VitalitySubMetric
    let parentPillar: VitalityPillar
    let weightWithinPillar: Double  // Must sum to 1.0 per pillar
    let scoringDirection: ScoringDirection
    let ageSpecificBenchmarks: AgeSpecificBenchmarks
    let description: String?
    
    init(
        id: VitalitySubMetric,
        parentPillar: VitalityPillar,
        weightWithinPillar: Double,
        scoringDirection: ScoringDirection,
        ageSpecificBenchmarks: AgeSpecificBenchmarks,
        description: String? = nil
    ) {
        self.id = id
        self.parentPillar = parentPillar
        self.weightWithinPillar = weightWithinPillar
        self.scoringDirection = scoringDirection
        self.ageSpecificBenchmarks = ageSpecificBenchmarks
        self.description = description
    }
}

/// Defines a pillar and its sub-metrics
struct PillarDefinition {
    let id: VitalityPillar
    let weightInVitality: Double  // Must sum to ~1.0 across all pillars
    let subMetrics: [SubMetricDefinition]
    
    init(
        id: VitalityPillar,
        weightInVitality: Double,
        subMetrics: [SubMetricDefinition]
    ) {
        self.id = id
        self.weightInVitality = weightInVitality
        self.subMetrics = subMetrics
        
        // Debug validation: sub-metric weights should sum to 1.0
        #if DEBUG
        let totalWeight = subMetrics.reduce(0.0) { $0 + $1.weightWithinPillar }
        assert(
            abs(totalWeight - 1.0) < 0.001,
            "⚠️ Sub-metric weights for \(id) must sum to 1.0, got \(totalWeight)"
        )
        #endif
    }
}

// MARK: - Schema Definition

/// The complete vitality scoring schema
/// Single source of truth for pillars, sub-metrics, weights, and age-specific benchmarks
let vitalityScoringSchema: [PillarDefinition] = [
    
    // MARK: Sleep Pillar (33% of Vitality)
    PillarDefinition(
        id: .sleep,
        weightInVitality: 0.33,
        subMetrics: [
            // Sleep Duration (hours per night, 7-day average)
            // Evidence: AASM/CDC recommendations by age
            SubMetricDefinition(
                id: .sleepDuration,
                parentPillar: .sleep,
                weightWithinPillar: 0.40,
                scoringDirection: .optimalRange,
                ageSpecificBenchmarks: AgeSpecificBenchmarks(byAgeGroup: [
                    .young: MetricRange(
                        optimalMin: 7.0, optimalMax: 9.0,
                        acceptableLowMin: 6.5, acceptableLowMax: 7.0,
                        acceptableHighMin: 9.0, acceptableHighMax: 9.5,
                        poorLowMax: 6.5, poorHighMin: 9.5
                    ),
                    .middle: MetricRange(
                        optimalMin: 7.0, optimalMax: 9.0,
                        acceptableLowMin: 6.5, acceptableLowMax: 7.0,
                        acceptableHighMin: 9.0, acceptableHighMax: 9.5,
                        poorLowMax: 6.5, poorHighMin: 9.5
                    ),
                    .senior: MetricRange(
                        optimalMin: 7.0, optimalMax: 8.5,
                        acceptableLowMin: 6.5, acceptableLowMax: 7.0,
                        acceptableHighMin: 8.5, acceptableHighMax: 9.0,
                        poorLowMax: 6.5, poorHighMin: 9.0
                    ),
                    .elderly: MetricRange(
                        optimalMin: 7.0, optimalMax: 8.0,
                        acceptableLowMin: 6.5, acceptableLowMax: 7.0,
                        acceptableHighMin: 8.0, acceptableHighMax: 8.5,
                        poorLowMax: 6.5, poorHighMin: 8.5
                    )
                ]),
                description: "Total hours of sleep per night. Based on AASM/CDC guidelines by age."
            ),
            
            // Restorative Sleep % (REM + Deep)
            // Heuristic targets: Deep sleep drops with age; REM decreases slowly
            SubMetricDefinition(
                id: .restorativeSleepPercent,
                parentPillar: .sleep,
                weightWithinPillar: 0.30,
                scoringDirection: .optimalRange,
                ageSpecificBenchmarks: AgeSpecificBenchmarks(byAgeGroup: [
                    .young: MetricRange(
                        optimalMin: 35.0, optimalMax: 45.0,
                        acceptableLowMin: 30.0, acceptableLowMax: 35.0,
                        acceptableHighMin: 45.0, acceptableHighMax: 50.0,
                        poorLowMax: 30.0, poorHighMin: 50.0
                    ),
                    .middle: MetricRange(
                        optimalMin: 30.0, optimalMax: 40.0,
                        acceptableLowMin: 25.0, acceptableLowMax: 30.0,
                        acceptableHighMin: 40.0, acceptableHighMax: 45.0,
                        poorLowMax: 25.0, poorHighMin: 45.0
                    ),
                    .senior: MetricRange(
                        optimalMin: 25.0, optimalMax: 35.0,
                        acceptableLowMin: 20.0, acceptableLowMax: 25.0,
                        acceptableHighMin: 35.0, acceptableHighMax: 40.0,
                        poorLowMax: 20.0, poorHighMin: 40.0
                    ),
                    .elderly: MetricRange(
                        optimalMin: 23.0, optimalMax: 33.0,
                        acceptableLowMin: 18.0, acceptableLowMax: 23.0,
                        acceptableHighMin: 33.0, acceptableHighMax: 38.0,
                        poorLowMax: 18.0, poorHighMin: 38.0
                    )
                ]),
                description: "Percentage of sleep in REM and Deep stages. Declines with age; these are wellness targets."
            ),
            
            // Sleep Efficiency (%)
            // Evidence: Sleep efficiency decreases with age; ≥85-90% is good in adults
            SubMetricDefinition(
                id: .sleepEfficiency,
                parentPillar: .sleep,
                weightWithinPillar: 0.20,
                scoringDirection: .higherIsBetter,
                ageSpecificBenchmarks: AgeSpecificBenchmarks(byAgeGroup: [
                    .young: MetricRange(
                        optimalMin: 90.0, optimalMax: 100.0,
                        acceptableLowMin: 85.0, acceptableLowMax: 90.0,
                        acceptableHighMin: 100.0, acceptableHighMax: 100.0,
                        poorLowMax: 85.0, poorHighMin: 100.0
                    ),
                    .middle: MetricRange(
                        optimalMin: 88.0, optimalMax: 100.0,
                        acceptableLowMin: 83.0, acceptableLowMax: 88.0,
                        acceptableHighMin: 100.0, acceptableHighMax: 100.0,
                        poorLowMax: 83.0, poorHighMin: 100.0
                    ),
                    .senior: MetricRange(
                        optimalMin: 85.0, optimalMax: 100.0,
                        acceptableLowMin: 80.0, acceptableLowMax: 85.0,
                        acceptableHighMin: 100.0, acceptableHighMax: 100.0,
                        poorLowMax: 80.0, poorHighMin: 100.0
                    ),
                    .elderly: MetricRange(
                        optimalMin: 83.0, optimalMax: 100.0,
                        acceptableLowMin: 78.0, acceptableLowMax: 83.0,
                        acceptableHighMin: 100.0, acceptableHighMax: 100.0,
                        poorLowMax: 78.0, poorHighMin: 100.0
                    )
                ]),
                description: "Time asleep divided by time in bed. Higher is better; standards decrease with age."
            ),
            
            // Awake % (fragmentation)
            // Evidence: WASO increases with age
            SubMetricDefinition(
                id: .sleepFragmentationAwakePercent,
                parentPillar: .sleep,
                weightWithinPillar: 0.10,
                scoringDirection: .lowerIsBetter,
                ageSpecificBenchmarks: AgeSpecificBenchmarks(byAgeGroup: [
                    .young: MetricRange(
                        optimalMin: 0.0, optimalMax: 5.0,
                        acceptableLowMin: 0.0, acceptableLowMax: 0.0,
                        acceptableHighMin: 5.0, acceptableHighMax: 10.0,
                        poorLowMax: 0.0, poorHighMin: 10.0
                    ),
                    .middle: MetricRange(
                        optimalMin: 0.0, optimalMax: 7.0,
                        acceptableLowMin: 0.0, acceptableLowMax: 0.0,
                        acceptableHighMin: 7.0, acceptableHighMax: 12.0,
                        poorLowMax: 0.0, poorHighMin: 12.0
                    ),
                    .senior: MetricRange(
                        optimalMin: 0.0, optimalMax: 10.0,
                        acceptableLowMin: 0.0, acceptableLowMax: 0.0,
                        acceptableHighMin: 10.0, acceptableHighMax: 15.0,
                        poorLowMax: 0.0, poorHighMin: 15.0
                    ),
                    .elderly: MetricRange(
                        optimalMin: 0.0, optimalMax: 12.0,
                        acceptableLowMin: 0.0, acceptableLowMax: 0.0,
                        acceptableHighMin: 12.0, acceptableHighMax: 18.0,
                        poorLowMax: 0.0, poorHighMin: 18.0
                    )
                ]),
                description: "Percentage of time awake during sleep period. Lower is better; increases with age."
            )
        ]
    ),
    
    // MARK: Movement Pillar (33% of Vitality)
    PillarDefinition(
        id: .movement,
        weightInVitality: 0.33,
        subMetrics: [
            // Movement Minutes (moderate-equivalent per day)
            // Evidence: WHO recommends 150-300 min/week moderate activity → ~21-43 min/day
            SubMetricDefinition(
                id: .movementMinutes,
                parentPillar: .movement,
                weightWithinPillar: 0.40,
                scoringDirection: .higherIsBetter,
                ageSpecificBenchmarks: AgeSpecificBenchmarks(byAgeGroup: [
                    .young: MetricRange(
                        optimalMin: 30.0, optimalMax: 45.0,
                        acceptableLowMin: 20.0, acceptableLowMax: 30.0,
                        acceptableHighMin: 45.0, acceptableHighMax: 60.0,
                        poorLowMax: 20.0, poorHighMin: 60.0
                    ),
                    .middle: MetricRange(
                        optimalMin: 30.0, optimalMax: 45.0,
                        acceptableLowMin: 20.0, acceptableLowMax: 30.0,
                        acceptableHighMin: 45.0, acceptableHighMax: 60.0,
                        poorLowMax: 20.0, poorHighMin: 60.0
                    ),
                    .senior: MetricRange(
                        optimalMin: 20.0, optimalMax: 40.0,
                        acceptableLowMin: 15.0, acceptableLowMax: 20.0,
                        acceptableHighMin: 40.0, acceptableHighMax: 50.0,
                        poorLowMax: 15.0, poorHighMin: 50.0
                    ),
                    .elderly: MetricRange(
                        optimalMin: 20.0, optimalMax: 40.0,
                        acceptableLowMin: 15.0, acceptableLowMax: 20.0,
                        acceptableHighMin: 40.0, acceptableHighMax: 50.0,
                        poorLowMax: 15.0, poorHighMin: 50.0
                    )
                ]),
                description: "Minutes of moderate to vigorous physical activity per day. Based on WHO guidelines."
            ),
            
            // Steps (per day)
            // Evidence: Risk reduction plateaus ~8-10k steps/day for <60, ~6-8k for ≥60
            SubMetricDefinition(
                id: .steps,
                parentPillar: .movement,
                weightWithinPillar: 0.30,
                scoringDirection: .higherIsBetter,
                ageSpecificBenchmarks: AgeSpecificBenchmarks(byAgeGroup: [
                    .young: MetricRange(
                        optimalMin: 8000.0, optimalMax: 10000.0,
                        acceptableLowMin: 6000.0, acceptableLowMax: 8000.0,
                        acceptableHighMin: 10000.0, acceptableHighMax: 15000.0,
                        poorLowMax: 6000.0, poorHighMin: 15000.0
                    ),
                    .middle: MetricRange(
                        optimalMin: 8000.0, optimalMax: 10000.0,
                        acceptableLowMin: 6000.0, acceptableLowMax: 8000.0,
                        acceptableHighMin: 10000.0, acceptableHighMax: 15000.0,
                        poorLowMax: 6000.0, poorHighMin: 15000.0
                    ),
                    .senior: MetricRange(
                        optimalMin: 6000.0, optimalMax: 8000.0,
                        acceptableLowMin: 4000.0, acceptableLowMax: 6000.0,
                        acceptableHighMin: 8000.0, acceptableHighMax: 12000.0,
                        poorLowMax: 4000.0, poorHighMin: 12000.0
                    ),
                    .elderly: MetricRange(
                        optimalMin: 6000.0, optimalMax: 8000.0,
                        acceptableLowMin: 4000.0, acceptableLowMax: 6000.0,
                        acceptableHighMin: 8000.0, acceptableHighMax: 12000.0,
                        poorLowMax: 4000.0, poorHighMin: 12000.0
                    )
                ]),
                description: "Total step count per day. Targets based on research showing plateau effects by age."
            ),
            
            // Active Calories (per day)
            // Product decision: Simple uniform target for V1
            SubMetricDefinition(
                id: .activeCalories,
                parentPillar: .movement,
                weightWithinPillar: 0.30,
                scoringDirection: .higherIsBetter,
                ageSpecificBenchmarks: AgeSpecificBenchmarks(byAgeGroup: [
                    .young: MetricRange(
                        optimalMin: 300.0, optimalMax: 600.0,
                        acceptableLowMin: 200.0, acceptableLowMax: 300.0,
                        acceptableHighMin: 600.0, acceptableHighMax: 900.0,
                        poorLowMax: 200.0, poorHighMin: 900.0
                    ),
                    .middle: MetricRange(
                        optimalMin: 300.0, optimalMax: 600.0,
                        acceptableLowMin: 200.0, acceptableLowMax: 300.0,
                        acceptableHighMin: 600.0, acceptableHighMax: 900.0,
                        poorLowMax: 200.0, poorHighMin: 900.0
                    ),
                    .senior: MetricRange(
                        optimalMin: 300.0, optimalMax: 600.0,
                        acceptableLowMin: 200.0, acceptableLowMax: 300.0,
                        acceptableHighMin: 600.0, acceptableHighMax: 900.0,
                        poorLowMax: 200.0, poorHighMin: 900.0
                    ),
                    .elderly: MetricRange(
                        optimalMin: 300.0, optimalMax: 600.0,
                        acceptableLowMin: 200.0, acceptableLowMax: 300.0,
                        acceptableHighMin: 600.0, acceptableHighMax: 900.0,
                        poorLowMax: 200.0, poorHighMin: 900.0
                    )
                ]),
                description: "Calories burned through activity. Uniform targets for V1; may be age-adjusted in future."
            )
        ]
    ),
    
    // MARK: Stress Pillar (34% of Vitality)
    PillarDefinition(
        id: .stress,
        weightInVitality: 0.34,
        subMetrics: [
            // HRV (SDNN, ms)
            // Heuristic targets: SDNN declines with age; <50ms associated with higher risk
            SubMetricDefinition(
                id: .hrv,
                parentPillar: .stress,
                weightWithinPillar: 0.40,
                scoringDirection: .higherIsBetter,
                ageSpecificBenchmarks: AgeSpecificBenchmarks(byAgeGroup: [
                    .young: MetricRange(
                        optimalMin: 70.0, optimalMax: 100.0,
                        acceptableLowMin: 50.0, acceptableLowMax: 70.0,
                        acceptableHighMin: 100.0, acceptableHighMax: 150.0,
                        poorLowMax: 50.0, poorHighMin: 150.0
                    ),
                    .middle: MetricRange(
                        optimalMin: 60.0, optimalMax: 90.0,
                        acceptableLowMin: 45.0, acceptableLowMax: 60.0,
                        acceptableHighMin: 90.0, acceptableHighMax: 130.0,
                        poorLowMax: 45.0, poorHighMin: 130.0
                    ),
                    .senior: MetricRange(
                        optimalMin: 50.0, optimalMax: 80.0,
                        acceptableLowMin: 40.0, acceptableLowMax: 50.0,
                        acceptableHighMin: 80.0, acceptableHighMax: 110.0,
                        poorLowMax: 40.0, poorHighMin: 110.0
                    ),
                    .elderly: MetricRange(
                        optimalMin: 40.0, optimalMax: 70.0,
                        acceptableLowMin: 30.0, acceptableLowMax: 40.0,
                        acceptableHighMin: 70.0, acceptableHighMax: 100.0,
                        poorLowMax: 30.0, poorHighMin: 100.0
                    )
                ]),
                description: "Heart rate variability (SDNN). Higher HRV indicates better recovery; declines with age. Heuristic wellness targets."
            ),
            
            // Resting Heart Rate (bpm)
            // Wellness targets: Lower within normal range is generally better
            SubMetricDefinition(
                id: .restingHeartRate,
                parentPillar: .stress,
                weightWithinPillar: 0.40,
                scoringDirection: .lowerIsBetter,
                ageSpecificBenchmarks: AgeSpecificBenchmarks(byAgeGroup: [
                    .young: MetricRange(
                        optimalMin: 50.0, optimalMax: 65.0,
                        acceptableLowMin: 40.0, acceptableLowMax: 50.0,
                        acceptableHighMin: 65.0, acceptableHighMax: 75.0,
                        poorLowMax: 40.0, poorHighMin: 90.0
                    ),
                    .middle: MetricRange(
                        optimalMin: 50.0, optimalMax: 65.0,
                        acceptableLowMin: 40.0, acceptableLowMax: 50.0,
                        acceptableHighMin: 65.0, acceptableHighMax: 75.0,
                        poorLowMax: 40.0, poorHighMin: 90.0
                    ),
                    .senior: MetricRange(
                        optimalMin: 55.0, optimalMax: 70.0,
                        acceptableLowMin: 45.0, acceptableLowMax: 55.0,
                        acceptableHighMin: 70.0, acceptableHighMax: 80.0,
                        poorLowMax: 45.0, poorHighMin: 90.0
                    ),
                    .elderly: MetricRange(
                        optimalMin: 55.0, optimalMax: 70.0,
                        acceptableLowMin: 45.0, acceptableLowMax: 55.0,
                        acceptableHighMin: 70.0, acceptableHighMax: 80.0,
                        poorLowMax: 45.0, poorHighMin: 90.0
                    )
                ]),
                description: "Average resting heart rate. Lower is generally better; normal adult range is 60-100 bpm."
            ),
            
            // Breathing Rate (breaths/min during rest)
            // Evidence: Normal adult resting RR ~12-18 or 12-20 breaths/min
            SubMetricDefinition(
                id: .breathingRate,
                parentPillar: .stress,
                weightWithinPillar: 0.20,
                scoringDirection: .optimalRange,
                ageSpecificBenchmarks: AgeSpecificBenchmarks(byAgeGroup: [
                    .young: MetricRange(
                        optimalMin: 12.0, optimalMax: 18.0,
                        acceptableLowMin: 10.0, acceptableLowMax: 12.0,
                        acceptableHighMin: 18.0, acceptableHighMax: 20.0,
                        poorLowMax: 10.0, poorHighMin: 20.0
                    ),
                    .middle: MetricRange(
                        optimalMin: 12.0, optimalMax: 18.0,
                        acceptableLowMin: 10.0, acceptableLowMax: 12.0,
                        acceptableHighMin: 18.0, acceptableHighMax: 20.0,
                        poorLowMax: 10.0, poorHighMin: 20.0
                    ),
                    .senior: MetricRange(
                        optimalMin: 12.0, optimalMax: 18.0,
                        acceptableLowMin: 10.0, acceptableLowMax: 12.0,
                        acceptableHighMin: 18.0, acceptableHighMax: 20.0,
                        poorLowMax: 10.0, poorHighMin: 20.0
                    ),
                    .elderly: MetricRange(
                        optimalMin: 12.0, optimalMax: 18.0,
                        acceptableLowMin: 10.0, acceptableLowMax: 12.0,
                        acceptableHighMin: 18.0, acceptableHighMax: 20.0,
                        poorLowMax: 10.0, poorHighMin: 20.0
                    )
                ]),
                description: "Breaths per minute during rest. Normal range is 12-20 for adults of all ages."
            )
        ]
    )
]

// MARK: - Validation

#if DEBUG
/// Validates the schema integrity at runtime (debug builds only)
func validateVitalityScoringSchema() {
    print("🔍 Validating vitality scoring schema...")
    
    // Check pillar weights sum to ~1.0
    let totalPillarWeight = vitalityScoringSchema.reduce(0.0) { $0 + $1.weightInVitality }
    assert(
        abs(totalPillarWeight - 1.0) < 0.001,
        "⚠️ Pillar weights must sum to 1.0, got \(totalPillarWeight)"
    )
    print("  ✅ Pillar weights sum to \(totalPillarWeight)")
    
    // Validate each pillar
    for pillar in vitalityScoringSchema {
        let subMetricWeightSum = pillar.subMetrics.reduce(0.0) { $0 + $1.weightWithinPillar }
        print("  ✅ \(pillar.id.displayName): \(pillar.subMetrics.count) sub-metrics, weights sum to \(subMetricWeightSum)")
        
        // Validate age-specific benchmarks
        for subMetric in pillar.subMetrics {
            // Check all age groups are present
            for ageGroup in AgeGroup.allCases {
                assert(
                    subMetric.ageSpecificBenchmarks.byAgeGroup[ageGroup] != nil,
                    "⚠️ \(subMetric.id): missing benchmarks for age group \(ageGroup)"
                )
            }
            
            // Validate range logic for each age group
            for (ageGroup, range) in subMetric.ageSpecificBenchmarks.byAgeGroup {
                // Optimal range should be valid
                assert(
                    range.optimalMin <= range.optimalMax,
                    "⚠️ \(subMetric.id) (\(ageGroup)): optimalMin should be <= optimalMax"
                )
                
                // Acceptable low should connect to optimal
                assert(
                    range.acceptableLowMax <= range.optimalMin,
                    "⚠️ \(subMetric.id) (\(ageGroup)): acceptableLowMax should connect to optimalMin"
                )
                
                // Acceptable high should connect to optimal
                assert(
                    range.acceptableHighMin >= range.optimalMax,
                    "⚠️ \(subMetric.id) (\(ageGroup)): acceptableHighMin should connect to optimalMax"
                )
                
                // Poor thresholds should be outside acceptable ranges
                assert(
                    range.poorLowMax <= range.acceptableLowMin,
                    "⚠️ \(subMetric.id) (\(ageGroup)): poorLowMax should be <= acceptableLowMin"
                )
                
                assert(
                    range.poorHighMin >= range.acceptableHighMax,
                    "⚠️ \(subMetric.id) (\(ageGroup)): poorHighMin should be >= acceptableHighMax"
                )
            }
        }
    }
    
    print("✅ Vitality scoring schema validated successfully")
    print("   Total pillars: \(vitalityScoringSchema.count)")
    print("   Total sub-metrics: \(VitalitySubMetric.allCases.count)")
    print("   Age groups per sub-metric: \(AgeGroup.allCases.count)")
}
#endif

// MARK: - Convenience Helpers

extension VitalityPillar {
    /// Get the pillar definition from the schema
    var definition: PillarDefinition? {
        vitalityScoringSchema.first { $0.id == self }
    }
    
    /// Get all sub-metrics for this pillar
    var subMetrics: [SubMetricDefinition] {
        definition?.subMetrics ?? []
    }
}

extension VitalitySubMetric {
    /// Get the sub-metric definition from the schema
    var definition: SubMetricDefinition? {
        for pillar in vitalityScoringSchema {
            if let subMetric = pillar.subMetrics.first(where: { $0.id == self }) {
                return subMetric
            }
        }
        return nil
    }
    
    /// Get the parent pillar for this sub-metric
    var pillar: VitalityPillar? {
        definition?.parentPillar
    }
    
    /// Get the weight of this sub-metric within its parent pillar
    var weightWithinPillar: Double {
        definition?.weightWithinPillar ?? 0.0
    }
    
    /// Get the scoring direction for this sub-metric
    var scoringDirection: ScoringDirection? {
        definition?.scoringDirection
    }
    
    /// Get the metric range for a specific age
    func range(forAge age: Int) -> MetricRange? {
        definition?.ageSpecificBenchmarks.range(forAge: age)
    }
    
    /// Get the metric range for a specific age group
    func range(forAgeGroup ageGroup: AgeGroup) -> MetricRange? {
        definition?.ageSpecificBenchmarks.range(forAgeGroup: ageGroup)
    }
}

// MARK: - Schema Info (for debugging/UI)

struct VitalitySchemaInfo {
    static var summary: String {
        var lines: [String] = []
        lines.append("📊 Vitality Scoring Schema (Age-Specific)")
        lines.append("=" + String(repeating: "=", count: 60))
        
        for pillar in vitalityScoringSchema {
            lines.append("")
            lines.append("🔹 \(pillar.id.displayName) (\(Int(pillar.weightInVitality * 100))% of vitality)")
            
            for subMetric in pillar.subMetrics {
                let weight = Int(subMetric.weightWithinPillar * 100)
                let directionSymbol: String
                switch subMetric.scoringDirection {
                case .higherIsBetter: directionSymbol = "↑"
                case .lowerIsBetter: directionSymbol = "↓"
                case .optimalRange: directionSymbol = "⊕"
                }
                lines.append("  • \(subMetric.id.displayName) (\(weight)%) \(directionSymbol)")
                lines.append("    Age-specific ranges defined for \(AgeGroup.allCases.count) age groups")
            }
        }
        
        lines.append("")
        lines.append("Legend: ↑ = Higher is better, ↓ = Lower is better, ⊕ = Optimal range")
        
        return lines.joined(separator: "\n")
    }
    
    static func printSchema() {
        print(summary)
    }
    
    /// Print detailed age-specific ranges for a specific sub-metric
    static func printAgeRanges(for metric: VitalitySubMetric) {
        guard let def = metric.definition else {
            print("⚠️ No definition found for \(metric)")
            return
        }
        
        print("\n📊 \(metric.displayName) - Age-Specific Ranges")
        print("=" + String(repeating: "=", count: 60))
        print("Scoring Direction: \(def.scoringDirection)")
        print("Unit: \(metric.unit)")
        print("")
        
        for ageGroup in AgeGroup.allCases {
            if let range = def.ageSpecificBenchmarks.byAgeGroup[ageGroup] {
                print("\(ageGroup.displayName) (\(ageGroup.ageRange)):")
                print("  Optimal:       \(range.optimalMin)-\(range.optimalMax) \(metric.unit)")
                print("  Acceptable Low:  \(range.acceptableLowMin)-\(range.acceptableLowMax) \(metric.unit)")
                print("  Acceptable High: \(range.acceptableHighMin)-\(range.acceptableHighMax) \(metric.unit)")
                print("  Poor: <\(range.poorLowMax) or >\(range.poorHighMin) \(metric.unit)")
                print("")
            }
        }
    }
}

