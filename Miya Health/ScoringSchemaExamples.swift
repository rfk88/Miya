//
//  ScoringSchemaExamples.swift
//  Miya Health
//
//  Example usage and tests for the vitality scoring schema
//  This file is for demonstration and can be deleted later
//

import Foundation

#if DEBUG

/// Examples showing how to use the vitality scoring schema
struct ScoringSchemaExamples {
    
    /// Example 1: Print complete schema overview
    static func printSchemaOverview() {
        print("\n" + "═" * 60)
        print("VITALITY SCORING SCHEMA OVERVIEW (Age-Specific)")
        print("═" * 60 + "\n")
        
        for pillar in vitalityScoringSchema {
            print("🔹 \(pillar.id.displayName.uppercased())")
            print("   Weight in Vitality: \(Int(pillar.weightInVitality * 100))%")
            print("   Sub-metrics:")
            
            for subMetric in pillar.subMetrics {
                let weight = Int(subMetric.weightWithinPillar * 100)
                let direction = directionSymbol(for: subMetric.scoringDirection)
                print("      • \(subMetric.id.displayName) (\(weight)%) \(direction)")
                print("        Age-specific ranges defined for \(AgeGroup.allCases.count) age groups")
            }
            print("")
        }
    }
    
    /// Example 2: Access specific sub-metric information (age-specific)
    static func demonstrateSubMetricAccess() {
        print("\n" + "═" * 60)
        print("SUB-METRIC ACCESS EXAMPLE (Age-Specific)")
        print("═" * 60 + "\n")
        
        // Example: Get sleep duration info for a 35-year-old
        if let sleepDef = VitalitySubMetric.sleepDuration.definition {
            print("📊 Sleep Duration Analysis (35-year-old):")
            print("   Parent Pillar: \(sleepDef.parentPillar.displayName)")
            print("   Weight in Sleep: \(Int(sleepDef.weightWithinPillar * 100))%")
            print("   Direction: \(sleepDef.scoringDirection)")
            print("   Unit: \(VitalitySubMetric.sleepDuration.unit)")
            
            let range = sleepDef.ageSpecificBenchmarks.range(forAge: 35)
            print("   Age-Specific Ranges:")
            print("      Optimal: \(range.optimalMin)-\(range.optimalMax) hours")
            print("      Acceptable Low: \(range.acceptableLowMin)-\(range.acceptableLowMax) hours")
            print("      Acceptable High: \(range.acceptableHighMin)-\(range.acceptableHighMax) hours")
            print("      Poor: <\(range.poorLowMax) or >\(range.poorHighMin) hours")
            print("")
        }
        
        // Example: Compare HRV ranges across age groups
        if let hrvDef = VitalitySubMetric.hrv.definition {
            print("💓 HRV Analysis (Age Comparison):")
            print("   Parent Pillar: \(hrvDef.parentPillar.displayName)")
            print("   Weight in Stress: \(Int(hrvDef.weightWithinPillar * 100))%")
            print("   Direction: \(hrvDef.scoringDirection)")
            print("   Unit: \(VitalitySubMetric.hrv.unit)")
            print("   Optimal Range by Age Group:")
            
            for ageGroup in AgeGroup.allCases {
                let range = hrvDef.ageSpecificBenchmarks.range(forAgeGroup: ageGroup)
                print("      \(ageGroup.displayName): \(range.optimalMin)-\(range.optimalMax) ms")
            }
            print("")
        }
    }
    
    /// Example 3: Iterate through all metrics and show their contribution
    static func demonstrateWeightCalculation() {
        print("\n" + "═" * 60)
        print("WEIGHT CONTRIBUTION ANALYSIS")
        print("═" * 60 + "\n")
        
        print("How each sub-metric contributes to total vitality:\n")
        
        for pillar in vitalityScoringSchema {
            print("From \(pillar.id.displayName) (\(Int(pillar.weightInVitality * 100))% of vitality):")
            
            for subMetric in pillar.subMetrics {
                let pillarWeight = pillar.weightInVitality
                let subMetricWeight = subMetric.weightWithinPillar
                let totalContribution = pillarWeight * subMetricWeight * 100
                
                print("   • \(subMetric.id.displayName): \(String(format: "%.1f", totalContribution))% of total vitality")
            }
            print("")
        }
        
        print("Example:")
        print("If you score 100/100 on Sleep Duration, it adds \(String(format: "%.1f", 0.33 * 0.40 * 100)) points to your total vitality.")
        print("If you score 80/100 on Steps, it adds \(String(format: "%.1f", 0.33 * 0.30 * 80)) points to your total vitality.")
        print("")
    }
    
    /// Example 4: Simulate scoring for a sample day (age-specific)
    static func demonstrateSampleScoring() {
        print("\n" + "═" * 60)
        print("SAMPLE DAY SCORING (Conceptual, Age-Specific)")
        print("═" * 60 + "\n")
        
        print("Sample data for a 45-year-old moderately active person:")
        print("   Age: 45 (middle age group)")
        print("   Sleep: 7.5 hours")
        print("   Steps: 8,500")
        print("   HRV: 55 ms")
        print("   Resting HR: 68 bpm")
        print("")
        
        print("How this would score (once scoring engine is built):")
        print("")
        print("🛏️  SLEEP PILLAR:")
        if let sleepDef = VitalitySubMetric.sleepDuration.definition {
            let range = sleepDef.ageSpecificBenchmarks.range(forAge: 45)
            print("   • Sleep Duration: 7.5h")
            print("     Target for 45yo: \(range.optimalMin)-\(range.optimalMax)h optimal")
            print("     → Score: ~94/100 (in optimal range)")
        }
        print("   • [Other sleep metrics would be calculated]")
        print("   → Sleep Pillar Score: ~75/100 (estimated)")
        print("")
        
        print("🏃 MOVEMENT PILLAR:")
        if let stepsDef = VitalitySubMetric.steps.definition {
            let range = stepsDef.ageSpecificBenchmarks.range(forAge: 45)
            print("   • Steps: 8,500")
            print("     Target for 45yo: \(Int(range.optimalMin))-\(Int(range.optimalMax)) steps optimal")
            print("     → Score: ~75/100 (in optimal range)")
        }
        print("   • [Other movement metrics would be calculated]")
        print("   → Movement Pillar Score: ~70/100 (estimated)")
        print("")
        
        print("😌 STRESS PILLAR:")
        if let hrvDef = VitalitySubMetric.hrv.definition {
            let range = hrvDef.ageSpecificBenchmarks.range(forAge: 45)
            print("   • HRV: 55ms")
            print("     Target for 45yo: \(Int(range.optimalMin))-\(Int(range.optimalMax))ms optimal")
            print("     → Score: ~70/100 (slightly below optimal)")
        }
        if let rhrDef = VitalitySubMetric.restingHeartRate.definition {
            let range = rhrDef.ageSpecificBenchmarks.range(forAge: 45)
            print("   • Resting HR: 68bpm")
            print("     Target for 45yo: \(Int(range.optimalMin))-\(Int(range.optimalMax))bpm optimal")
            print("     → Score: ~80/100 (good range)")
        }
        print("   • [Other stress metrics would be calculated]")
        print("   → Stress Pillar Score: ~75/100 (estimated)")
        print("")
        
        let estimatedTotal = (75 * 0.33) + (70 * 0.33) + (75 * 0.34)
        print("TOTAL VITALITY: ~\(Int(estimatedTotal))/100")
        print("")
    }
    
    /// Example 5: Demonstrate age group differences
    static func demonstrateAgeGroupDifferences() {
        print("\n" + "═" * 60)
        print("AGE GROUP DIFFERENCES")
        print("═" * 60 + "\n")
        
        print("How ranges change with age (Sleep Duration example):")
        print("")
        
        if let sleepDef = VitalitySubMetric.sleepDuration.definition {
            for ageGroup in AgeGroup.allCases {
                let range = sleepDef.ageSpecificBenchmarks.range(forAgeGroup: ageGroup)
                print("\(ageGroup.displayName) (\(ageGroup.ageRange)):")
                print("  Optimal: \(range.optimalMin)-\(range.optimalMax) hours")
                print("  Acceptable: \(range.acceptableLowMin)-\(range.acceptableLowMax) and \(range.acceptableHighMin)-\(range.acceptableHighMax) hours")
                print("  Poor: <\(range.poorLowMax) or >\(range.poorHighMin) hours")
                print("")
            }
        }
        
        print("How ranges change with age (HRV example):")
        print("")
        
        if let hrvDef = VitalitySubMetric.hrv.definition {
            for ageGroup in AgeGroup.allCases {
                let range = hrvDef.ageSpecificBenchmarks.range(forAgeGroup: ageGroup)
                print("\(ageGroup.displayName) (\(ageGroup.ageRange)):")
                print("  Optimal: \(Int(range.optimalMin))-\(Int(range.optimalMax)) ms")
                print("")
            }
        }
    }
    
    /// Example 6: Show all sub-metrics organized by pillar
    static func listAllMetrics() {
        print("\n" + "═" * 60)
        print("ALL SUB-METRICS (with Age-Specific Ranges)")
        print("═" * 60 + "\n")
        
        for pillar in VitalityPillar.allCases {
            if let def = pillar.definition {
                print("\(pillar.displayName):")
                for (index, metric) in def.subMetrics.enumerated() {
                    let directionSymbol: String
                    switch metric.scoringDirection {
                    case .higherIsBetter: directionSymbol = "↑"
                    case .lowerIsBetter: directionSymbol = "↓"
                    case .optimalRange: directionSymbol = "⊕"
                    }
                    print("   \(index + 1). \(metric.id.displayName) (\(metric.id.unit)) \(directionSymbol)")
                }
                print("")
            }
        }
        
        print("Total: \(VitalitySubMetric.allCases.count) sub-metrics tracked")
        print("Age groups: \(AgeGroup.allCases.count) (\(AgeGroup.allCases.map { $0.displayName }.joined(separator: ", ")))")
        print("")
    }
    
    /// Helper: Get symbol for scoring direction
    private static func directionSymbol(for direction: ScoringDirection) -> String {
        switch direction {
        case .higherIsBetter: return "↑"
        case .lowerIsBetter: return "↓"
        case .optimalRange: return "⊕"
        }
    }
    
    /// Run all examples
    static func runAllExamples() {
        print("\n\n")
        print("🎯 VITALITY SCORING SCHEMA EXAMPLES (Age-Specific)")
        print("=" * 60)
        
        listAllMetrics()
        printSchemaOverview()
        demonstrateSubMetricAccess()
        demonstrateWeightCalculation()
        demonstrateSampleScoring()
        demonstrateAgeGroupDifferences()
        
        print("\n" + "=" * 60)
        print("✅ All examples complete!")
        print("=" * 60 + "\n\n")
    }
    
    /// Smoke test for the new VitalityScoringEngine
    static func runScoringEngineSmokeTest() {
        print("\n" + "═" * 60)
        print("VITALITY SCORING ENGINE SMOKE TEST")
        print("═" * 60 + "\n")
        
        let raw = VitalityRawMetrics(
            age: 35,
            sleepDurationHours: 6.0,
            restorativeSleepPercent: 30,
            sleepEfficiencyPercent: 85,
            awakePercent: 10,
            movementMinutes: 40,
            steps: 9000,
            activeCalories: 450,
            hrvMs: 55,
            hrvType: "sdnn",  // Example uses SDNN
            restingHeartRate: 62,
            breathingRate: 15
        )
        
        let engine = VitalityScoringEngine()
        let snapshot = engine.score(raw: raw)
        
        print("Input:")
        print("  Age: \(raw.age) (\(snapshot.ageGroup.displayName))")
        print("  Sleep: \(raw.sleepDurationHours ?? 0)h, \(raw.restorativeSleepPercent ?? 0)% restorative, \(raw.sleepEfficiencyPercent ?? 0)% efficiency, \(raw.awakePercent ?? 0)% awake")
        print("  Movement: \(raw.movementMinutes ?? 0)min, \(raw.steps ?? 0) steps, \(raw.activeCalories ?? 0) kcal")
        print("  Stress: \(raw.hrvMs ?? 0)ms HRV, \(raw.restingHeartRate ?? 0) bpm RHR, \(raw.breathingRate ?? 0) breaths/min")
        print("")
        
        print("Output:")
        print("  Total Vitality: \(snapshot.totalScore)/100")
        print("")
        
        for pillarScore in snapshot.pillarScores {
            print("  \(pillarScore.pillar.displayName) Pillar: \(pillarScore.score)/100")
            for subMetricScore in pillarScore.subMetricScores {
                let valueStr = subMetricScore.rawValue.map { String(format: "%.1f", $0) } ?? "nil"
                print("    • \(subMetricScore.subMetric.displayName): \(valueStr) \(subMetricScore.subMetric.unit) → \(subMetricScore.score)/100")
            }
            print("")
        }
        
        print("=" * 60)
        print("✅ Smoke test complete")
        print("=" * 60 + "\n")
    }
}

// Helper for string multiplication
fileprivate extension String {
    static func * (string: String, count: Int) -> String {
        return String(repeating: string, count: count)
    }
}

#endif

