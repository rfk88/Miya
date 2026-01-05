//
//  VitalityScoringEngine.swift
//  Miya Health
//
//  Production scoring engine using age-specific schema
//  Transforms raw wearable metrics into vitality scores
//

import Foundation

// MARK: - Input Structure

/// Raw wearable data input for vitality scoring
struct VitalityRawMetrics {
    let age: Int
    
    // Sleep
    let sleepDurationHours: Double?
    let restorativeSleepPercent: Double?
    let sleepEfficiencyPercent: Double?
    let awakePercent: Double?
    
    // Movement
    let movementMinutes: Double?
    let steps: Int?
    let activeCalories: Double?
    
    // Stress
    let hrvMs: Double?
    let hrvType: String?  // "sdnn" or "rmssd" - tracks which HRV metric was used
    let restingHeartRate: Double?
    let breathingRate: Double?
}

// MARK: - Output Structures

/// Score for a single sub-metric
struct SubMetricScore {
    let subMetric: VitalitySubMetric
    let rawValue: Double?
    let score: Int  // 0–100
}

/// Score for a pillar (aggregated from sub-metrics)
struct PillarScore {
    let pillar: VitalityPillar
    let score: Int  // 0–100
    let subMetricScores: [SubMetricScore]
    
    /// True if this pillar has at least one available submetric (rawValue != nil).
    /// Representation only; does not affect scoring math.
    var isAvailable: Bool {
        subMetricScores.contains(where: { $0.rawValue != nil })
    }
}

/// Complete vitality snapshot with all scores
struct VitalitySnapshot {
    let age: Int
    let ageGroup: AgeGroup
    let totalScore: Int  // 0–100
    let pillarScores: [PillarScore]
}

// MARK: - Scoring Engine

struct VitalityScoringEngine {
    
    /// Score raw metrics using the vitality scoring schema
    /// - Parameters:
    ///   - raw: Raw wearable metrics
    ///   - schema: Scoring schema (defaults to vitalityScoringSchema)
    /// - Returns: Complete vitality snapshot with all scores
    func score(
        raw: VitalityRawMetrics,
        using schema: [PillarDefinition] = vitalityScoringSchema
    ) -> VitalitySnapshot {
        scoreInternal(raw: raw, using: schema).snapshot
    }
    
    /// Score raw metrics and capture an auditable breakdown using the same production scoring path.
    func scoreWithBreakdown(
        raw: VitalityRawMetrics,
        using schema: [PillarDefinition] = vitalityScoringSchema
    ) -> (snapshot: VitalitySnapshot, breakdown: VitalityBreakdown) {
        scoreInternal(raw: raw, using: schema, includeBreakdown: true)
    }
    
    /// Convenience API: return both the breakdown and a lightweight explanation layer derived from it.
    /// No scoring changes; explanation is derived mechanically from `VitalityBreakdown`.
    func scoreWithBreakdownAndExplanation(
        raw: VitalityRawMetrics,
        using schema: [PillarDefinition] = vitalityScoringSchema
    ) -> (snapshot: VitalitySnapshot, breakdown: VitalityBreakdown, explanation: VitalityExplanation) {
        let scored = scoreWithBreakdown(raw: raw, using: schema)
        let explanation = VitalityExplanation.derive(from: scored.breakdown)
        return (scored.snapshot, scored.breakdown, explanation)
    }
    
    /// Score only if data is sufficiently complete.
    /// - Returns: `(snapshot, breakdown)` if at least 2 pillars have at least 1 available submetric.
    /// - Otherwise: `nil` (caller should surface "insufficient data").
    func scoreIfPossible(
        raw: VitalityRawMetrics,
        using schema: [PillarDefinition] = vitalityScoringSchema
    ) -> (snapshot: VitalitySnapshot, breakdown: VitalityBreakdown)? {
        let scored = scoreInternal(raw: raw, using: schema, includeBreakdown: true)
        
        // A pillar is "available" if it has at least one available submetric (rawValue != nil).
        let availablePillars = scored.snapshot.pillarScores.filter { pillar in
            pillar.subMetricScores.contains(where: { $0.rawValue != nil })
        }
        
        guard availablePillars.count >= 2 else {
            return nil
        }
        
        return scored
    }
    
    #if DEBUG
    func debugScoreIfPossibleReason(
        raw: VitalityRawMetrics,
        using schema: [PillarDefinition] = vitalityScoringSchema
    ) -> String {
        let scored = scoreInternal(raw: raw, using: schema, includeBreakdown: true)
        let availablePillars = scored.snapshot.pillarScores.filter { pillar in
            pillar.subMetricScores.contains(where: { $0.rawValue != nil })
        }
        if availablePillars.count >= 2 {
            return "ok"
        }
        let names = availablePillars.map { $0.pillar.displayName }.joined(separator: ", ")
        return "insufficient pillars: \(availablePillars.count) (\(names))"
    }
    #endif
    
    #if DEBUG
    static func debugPrintBreakdown(_ b: VitalityBreakdown) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(b)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Failed to encode VitalityBreakdown: \(error.localizedDescription)"
        }
    }
    #endif
    
    // MARK: - Internal scoring (shared path)
    
    private func scoreInternal(
        raw: VitalityRawMetrics,
        using schema: [PillarDefinition],
        includeBreakdown: Bool = false
    ) -> (snapshot: VitalitySnapshot, breakdown: VitalityBreakdown) {
        
        // Step A: Determine AgeGroup
        let ageGroup = AgeGroup.from(age: raw.age)
        
        // Step B & C: Score each pillar
        var pillarScores: [PillarScore] = []
        var pillarBreakdowns: [PillarBreakdown] = []
        
        for pillarDef in schema {
            var subMetricScores: [SubMetricScore] = []
            var subBreakdowns: [SubmetricBreakdown] = []
            
            // Score each sub-metric in this pillar
            for subMetricDef in pillarDef.subMetrics {
                // Map VitalitySubMetric to raw value
                let rawValue = getRawValue(for: subMetricDef.id, from: raw)
                
                // If nil, score is 0
                guard let value = rawValue else {
                    let scoreObj = SubMetricScore(subMetric: subMetricDef.id, rawValue: nil, score: 0)
                    subMetricScores.append(scoreObj)
                    
                    if includeBreakdown {
                        subBreakdowns.append(SubmetricBreakdown(
                            id: breakdownID(for: subMetricDef),
                            label: subMetricDef.id.displayName,
                            valueText: "nil",
                            targetText: formatTargetText(range: subMetricDef.ageSpecificBenchmarks.range(forAgeGroup: ageGroup), unit: subMetricDef.id.unit, direction: subMetricDef.scoringDirection),
                            points: 0.0,
                            maxPoints: 100.0 * subMetricDef.weightWithinPillar,
                            status: .missing,
                            notes: breakdownNotes(for: subMetricDef.id, raw: raw)
                        ))
                    }
                    continue
                }
                
                // Get age-specific range
                let range = subMetricDef.ageSpecificBenchmarks.range(forAgeGroup: ageGroup)
                
                // Score based on direction
                let score = scoreValue(value: value, range: range, direction: subMetricDef.scoringDirection)
                let scoreObj = SubMetricScore(subMetric: subMetricDef.id, rawValue: value, score: score)
                subMetricScores.append(scoreObj)
                
                if includeBreakdown {
                    let status = statusFor(value: value, range: range, direction: subMetricDef.scoringDirection, producedScore: score)
                    subBreakdowns.append(SubmetricBreakdown(
                        id: breakdownID(for: subMetricDef),
                        label: subMetricDef.id.displayName,
                        valueText: formatValueText(metric: subMetricDef.id, value: value),
                        targetText: formatTargetText(range: range, unit: subMetricDef.id.unit, direction: subMetricDef.scoringDirection),
                        points: Double(score) * subMetricDef.weightWithinPillar,
                        maxPoints: 100.0 * subMetricDef.weightWithinPillar,
                        status: status,
                        notes: breakdownNotes(for: subMetricDef.id, raw: raw)
                    ))
                }
            }
            
            // Step D: Compute pillar score (weighted average of sub-metrics)
            let pillarScore = computePillarScore(subMetricScores: subMetricScores, subMetricDefinitions: pillarDef.subMetrics)
            pillarScores.append(PillarScore(pillar: pillarDef.id, score: pillarScore, subMetricScores: subMetricScores))
            
            if includeBreakdown {
                pillarBreakdowns.append(PillarBreakdown(
                    id: pillarDef.id.rawValue,
                    label: pillarDef.id.displayName,
                    score: Double(pillarScore),
                    maxScore: 100.0,
                    submetrics: subBreakdowns
                ))
            }
        }
        
        // Step E: Compute total vitality (weighted average of pillars)
        let totalScore = computeTotalVitality(pillarScores: pillarScores, pillarDefinitions: schema)
        
        let snapshot = VitalitySnapshot(
            age: raw.age,
            ageGroup: ageGroup,
            totalScore: totalScore,
            pillarScores: pillarScores
        )
        
        let pillarsUsed = pillarScores.filter { $0.isAvailable }.count
        let pillarsPossible = schema.count
        
        let breakdown = VitalityBreakdown(
            totalScore: Double(totalScore),
            totalMaxScore: 100.0,
            pillarsUsed: pillarsUsed,
            pillarsPossible: pillarsPossible,
            pillars: pillarBreakdowns
        )
        
        return (snapshot, breakdown)
    }
    
    // MARK: - Helper: Map SubMetric to Raw Value
    
    /// Extract raw value from VitalityRawMetrics based on sub-metric ID
    private func getRawValue(for subMetric: VitalitySubMetric, from raw: VitalityRawMetrics) -> Double? {
        switch subMetric {
        case .sleepDuration:
            return raw.sleepDurationHours
        case .restorativeSleepPercent:
            return raw.restorativeSleepPercent
        case .sleepEfficiency:
            return raw.sleepEfficiencyPercent
        case .sleepFragmentationAwakePercent:
            return raw.awakePercent
        case .movementMinutes:
            return raw.movementMinutes
        case .steps:
            return raw.steps.map { Double($0) }
        case .activeCalories:
            return raw.activeCalories
        case .hrv:
            return raw.hrvMs
        case .restingHeartRate:
            return raw.restingHeartRate
        case .breathingRate:
            return raw.breathingRate
        }
    }
    
    // MARK: - Breakdown helpers
    
    private func breakdownID(for def: SubMetricDefinition) -> String {
        "\(def.parentPillar.rawValue).\(def.id.rawValue)"
    }
    
    private func breakdownNotes(for metric: VitalitySubMetric, raw: VitalityRawMetrics) -> String? {
        // Only surface notes that are already present in raw input / mapping (no new scoring).
        switch metric {
        case .hrv:
            if let t = raw.hrvType, !t.isEmpty {
                return "hrvType=\(t)"
            }
            return nil
        default:
            return nil
        }
    }
    
    private func formatValueText(metric: VitalitySubMetric, value: Double) -> String {
        // Keep formatting minimal and deterministic (no additional scoring logic here).
        switch metric {
        case .steps:
            return "\(Int(value.rounded())) \(metric.unit)"
        case .restorativeSleepPercent, .sleepEfficiency, .sleepFragmentationAwakePercent:
            return "\(String(format: "%.1f", value)) \(metric.unit)"
        default:
            return "\(String(format: "%.2f", value)) \(metric.unit)"
        }
    }
    
    private func formatTargetText(range: MetricRange, unit: String, direction: ScoringDirection) -> String {
        // Use schema-defined ranges only (no invented thresholds).
        func fmt(_ x: Double) -> String {
            // Heuristic: show fewer decimals for larger numbers (e.g., steps).
            if abs(x) >= 100 { return String(format: "%.0f", x) }
            if abs(x) >= 10 { return String(format: "%.1f", x) }
            return String(format: "%.2f", x)
        }
        
        switch direction {
        case .optimalRange:
            return "Optimal: \(fmt(range.optimalMin))–\(fmt(range.optimalMax)) \(unit); Acceptable: \(fmt(range.acceptableLowMin))–\(fmt(range.acceptableLowMax)) / \(fmt(range.acceptableHighMin))–\(fmt(range.acceptableHighMax)) \(unit)"
        case .higherIsBetter:
            return "Optimal: \(fmt(range.optimalMin))–\(fmt(range.optimalMax)) \(unit); Acceptable (min): \(fmt(range.acceptableLowMin)) \(unit)"
        case .lowerIsBetter:
            return "Optimal: \(fmt(range.optimalMin))–\(fmt(range.optimalMax)) \(unit); Acceptable (max): \(fmt(range.acceptableHighMax)) \(unit)"
        }
    }
    
    private func statusFor(value: Double, range: MetricRange, direction: ScoringDirection, producedScore: Int) -> VitalityStatus {
        // Prefer using the engine's own effective bucket logic (range comparisons).
        // If comparisons are inconclusive, fall back to score==0 vs >0.
        switch direction {
        case .optimalRange:
            if value >= range.optimalMin && value <= range.optimalMax { return .optimal }
            let inAcceptableLow = (value >= range.acceptableLowMin && value <= range.acceptableLowMax)
            let inAcceptableHigh = (value >= range.acceptableHighMin && value <= range.acceptableHighMax)
            if inAcceptableLow || inAcceptableHigh { return .ok }
            return .low
        case .higherIsBetter:
            if value >= range.optimalMin { return .optimal }
            if value >= range.acceptableLowMin { return .ok }
            return .low
        case .lowerIsBetter:
            // Mirror effective branching used by `scoreLowerIsBetter` (see implementation above).
            if value <= range.optimalMax { return .optimal }
            if value <= range.acceptableHighMax { return .ok }
            return producedScore > 0 ? .ok : .low
        }
    }
    
    // MARK: - Scoring Functions
    
    /// Score a raw value based on its range and scoring direction
    private func scoreValue(value: Double, range: MetricRange, direction: ScoringDirection) -> Int {
        switch direction {
        case .optimalRange:
            return scoreOptimalRange(value: value, range: normalizedRange(range))
        case .higherIsBetter:
            return scoreHigherIsBetter(value: value, range: normalizedRange(range))
        case .lowerIsBetter:
            return scoreLowerIsBetter(value: value, range: normalizedRange(range))
        }
    }
    
    /// Normalize degenerate/invalid "poor" bounds using only existing schema bounds.
    /// This prevents cliffs to 0 when `poorLowMax`/`poorHighMin` are missing/degenerate.
    private func normalizedRange(_ range: MetricRange) -> MetricRange {
        var poorLowMax = range.poorLowMax
        var poorHighMin = range.poorHighMin
        
        // Low side: if poorLowMax is missing/degenerate (>= acceptableLowMin), mirror outward from acceptable->optimal distance.
        if poorLowMax >= range.acceptableLowMin {
            let delta = (range.optimalMin - range.acceptableLowMin)
            poorLowMax = range.acceptableLowMin - delta
        }
        
        // High side: if poorHighMin is missing/degenerate (<= acceptableHighMax), mirror outward from optimal->acceptable distance.
        if poorHighMin <= range.acceptableHighMax {
            let delta = (range.acceptableHighMax - range.optimalMax)
            poorHighMin = range.acceptableHighMax + delta
        }
        
        return MetricRange(
            optimalMin: range.optimalMin,
            optimalMax: range.optimalMax,
            acceptableLowMin: range.acceptableLowMin,
            acceptableLowMax: range.acceptableLowMax,
            acceptableHighMin: range.acceptableHighMin,
            acceptableHighMax: range.acceptableHighMax,
            poorLowMax: poorLowMax,
            poorHighMin: poorHighMin
        )
    }
    
    /// Score for optimalRange metrics
    /// Optimal band → 80-100, Acceptable → 50-80, Poor → 0-50
    private func scoreOptimalRange(value: Double, range: MetricRange) -> Int {
        // In optimal range
        if value >= range.optimalMin && value <= range.optimalMax {
            // Linear interpolation: optimalMin → 80, optimalMax → 100
            let progress = (value - range.optimalMin) / (range.optimalMax - range.optimalMin)
            return Int(80 + (progress * 20))
        }
        
        // In acceptable low range
        if value >= range.acceptableLowMin && value < range.optimalMin {
            // Linear interpolation: acceptableLowMin → 50, optimalMin → 80
            let progress = (value - range.acceptableLowMin) / (range.optimalMin - range.acceptableLowMin)
            return Int(50 + (progress * 30))
        }
        
        // In acceptable high range
        if value > range.optimalMax && value <= range.acceptableHighMax {
            // Linear interpolation: optimalMax → 100, acceptableHighMax → 80
            let progress = (value - range.optimalMax) / (range.acceptableHighMax - range.optimalMax)
            return Int(100 - (progress * 20))
        }
        
        // Below acceptable low (poor)
        if value < range.acceptableLowMin {
            // Linear interpolation: poorLowMax → 0, acceptableLowMin → 50
            if value <= range.poorLowMax {
                return 0
            }
            let progress = (value - range.poorLowMax) / (range.acceptableLowMin - range.poorLowMax)
            return Int(progress * 50)
        }
        
        // Above acceptable high (poor)
        if value > range.acceptableHighMax {
            // Linear interpolation: acceptableHighMax → 80, poorHighMin → 50
            if value >= range.poorHighMin {
                return 0
            }
            let progress = (value - range.acceptableHighMax) / (range.poorHighMin - range.acceptableHighMax)
            return Int(80 - (progress * 30))
        }
        
        // Fallback (shouldn't happen)
        return 0
    }
    
    /// Score for higherIsBetter metrics
    /// Below poor → 0, At acceptable → ~60, ≥ optimal upper bound → 100
    private func scoreHigherIsBetter(value: Double, range: MetricRange) -> Int {
        // At or above optimal upper bound
        if value >= range.optimalMax {
            return 100
        }
        
        // In optimal range
        if value >= range.optimalMin && value < range.optimalMax {
            // Linear interpolation: optimalMin → 80, optimalMax → 100
            let progress = (value - range.optimalMin) / (range.optimalMax - range.optimalMin)
            return Int(80 + (progress * 20))
        }
        
        // In acceptable high range (above optimal)
        if value > range.optimalMax && value <= range.acceptableHighMax {
            // Already capped at 100, but handle edge case
            return 100
        }
        
        // In acceptable low range
        if value >= range.acceptableLowMin && value < range.optimalMin {
            // Linear interpolation: acceptableLowMin → 60, optimalMin → 80
            let progress = (value - range.acceptableLowMin) / (range.optimalMin - range.acceptableLowMin)
            return Int(60 + (progress * 20))
        }
        
        // Below acceptable (poor)
        if value < range.acceptableLowMin {
            // Linear interpolation: poorLowMax → 0, acceptableLowMin → 60
            if value <= range.poorLowMax {
                return 0
            }
            let progress = (value - range.poorLowMax) / (range.acceptableLowMin - range.poorLowMax)
            return Int(progress * 60)
        }
        
        // Fallback
        return 0
    }
    
    /// Score for lowerIsBetter metrics (inverse of higherIsBetter)
    private func scoreLowerIsBetter(value: Double, range: MetricRange) -> Int {
        // At or below optimal lower bound
        if value <= range.optimalMin {
            return 100
        }
        
        // In optimal range
        if value > range.optimalMin && value <= range.optimalMax {
            // Linear interpolation: optimalMin → 100, optimalMax → 80
            let progress = (value - range.optimalMin) / (range.optimalMax - range.optimalMin)
            return Int(100 - (progress * 20))
        }
        
        // In acceptable low range (below optimal)
        if value < range.optimalMin && value >= range.acceptableLowMin {
            // Linear interpolation: acceptableLowMin → 60, optimalMin → 100
            let progress = (value - range.acceptableLowMin) / (range.optimalMin - range.acceptableLowMin)
            return Int(60 + (progress * 40))
        }
        
        // In acceptable high range
        if value > range.optimalMax && value <= range.acceptableHighMax {
            // Linear interpolation: optimalMax → 80, acceptableHighMax → 60
            let progress = (value - range.optimalMax) / (range.acceptableHighMax - range.optimalMax)
            return Int(80 - (progress * 20))
        }
        
        // Above acceptable (poor)
        if value > range.acceptableHighMax {
            // Linear interpolation: acceptableHighMax → 60, poorHighMin → 0
            if value >= range.poorHighMin {
                return 0
            }
            let progress = (value - range.acceptableHighMax) / (range.poorHighMin - range.acceptableHighMax)
            return Int(60 - (progress * 60))
        }
        
        // Fallback
        return 0
    }
    
    // MARK: - Aggregation Functions
    
    /// Compute pillar score as weighted average of sub-metric scores
    private func computePillarScore(
        subMetricScores: [SubMetricScore],
        subMetricDefinitions: [SubMetricDefinition]
    ) -> Int {
        var weightedSum: Double = 0.0
        var totalWeight: Double = 0.0
        
        for subMetricScore in subMetricScores {
            // Find matching definition to get weight
            if let def = subMetricDefinitions.first(where: { $0.id == subMetricScore.subMetric }) {
                // Step 1: Missing submetrics must not penalize users.
                // Exclude missing (rawValue == nil) submetrics entirely from weight normalization.
                guard subMetricScore.rawValue != nil else { continue }
                
                weightedSum += Double(subMetricScore.score) * def.weightWithinPillar
                totalWeight += def.weightWithinPillar
            }
        }
        
        guard totalWeight > 0 else { return 0 }
        return Int(round(weightedSum / totalWeight))
    }
    
    /// Compute total vitality score as weighted average of pillar scores
    private func computeTotalVitality(
        pillarScores: [PillarScore],
        pillarDefinitions: [PillarDefinition]
    ) -> Int {
        var weightedSum: Double = 0.0
        var totalWeight: Double = 0.0
        
        for pillarScore in pillarScores {
            // Exclude pillars that have no available submetrics (all rawValue == nil).
            // Missing pillars must not penalize total vitality.
            let hasAnyAvailableSubmetric = pillarScore.subMetricScores.contains(where: { $0.rawValue != nil })
            guard hasAnyAvailableSubmetric else { continue }
            
            // Find matching definition to get weight
            if let def = pillarDefinitions.first(where: { $0.id == pillarScore.pillar }) {
                weightedSum += Double(pillarScore.score) * def.weightInVitality
                totalWeight += def.weightInVitality
            }
        }
        
        guard totalWeight > 0 else { return 0 }
        return Int(round(weightedSum / totalWeight))
    }
}

// MARK: - Adapter from Legacy Data

/// Builds VitalityRawMetrics from a flexible window of legacy VitalityData records
struct VitalityMetricsBuilder {
    
    /// Convert a flexible window of VitalityData into VitalityRawMetrics
    /// - Parameters:
    ///   - age: User's age
    ///   - records: Array of VitalityData (uses 7-30 day window based on availability)
    /// - Returns: VitalityRawMetrics with averaged values from the window
    ///
    /// Window selection:
    /// - If 30+ records: use last 30 days
    /// - If 7-29 records: use all available
    /// - If <7 records: use all available (compute score with what we have)
    static func fromWindow(
        age: Int,
        records: [VitalityData]
    ) -> VitalityRawMetrics {
        // Sort by date
        let sorted = records.sorted { $0.date < $1.date }
        
        // Select window based on availability
        let window: [VitalityData]
        if sorted.count >= 30 {
            // Use last 30 days
            window = Array(sorted.suffix(30))
        } else {
            // Use all available (whether <7, 7-29)
            window = sorted
        }
        
        // Backfill (last-known-value) for missing metrics:
        // If a metric is nil across the current scoring window, look back up to 7 previous days
        // and use the most recent non-nil value found. Never invent values, never average across weeks.
        let windowStartDate: Date? = window.first?.date
        func backfillDoubleIfNeeded(_ current: Double?, value: (VitalityData) -> Double?) -> Double? {
            guard current == nil, let start = windowStartDate else { return current }
            guard let lookbackStart = Calendar.current.date(byAdding: .day, value: -7, to: start) else { return current }
            // Most recent first
            for r in sorted.reversed() {
                guard r.date < start && r.date >= lookbackStart else { continue }
                if let v = value(r) { return v }
            }
            return nil
        }
        
        func backfillIntIfNeeded(_ current: Int?, value: (VitalityData) -> Int?) -> Int? {
            guard current == nil, let start = windowStartDate else { return current }
            guard let lookbackStart = Calendar.current.date(byAdding: .day, value: -7, to: start) else { return current }
            for r in sorted.reversed() {
                guard r.date < start && r.date >= lookbackStart else { continue }
                if let v = value(r) { return v }
            }
            return nil
        }
        
        // Average sleep hours
        let sleepValues = window.compactMap { $0.sleepHours }
        let avgSleepUnfilled = sleepValues.isEmpty ? nil : sleepValues.reduce(0, +) / Double(sleepValues.count)
        let avgSleep = backfillDoubleIfNeeded(avgSleepUnfilled) { $0.sleepHours }
        
        // Average steps
        let stepsValues = window.compactMap { $0.steps }
        let avgStepsUnfilled = stepsValues.isEmpty ? nil : stepsValues.reduce(0, +) / stepsValues.count
        let avgSteps = backfillIntIfNeeded(avgStepsUnfilled) { $0.steps }
        
        // Average HRV
        let hrvValues = window.compactMap { $0.hrvMs }
        let avgHrvUnfilled = hrvValues.isEmpty ? nil : hrvValues.reduce(0, +) / Double(hrvValues.count)
        let avgHrv = backfillDoubleIfNeeded(avgHrvUnfilled) { $0.hrvMs }
        
        // Average resting heart rate
        let rhrValues = window.compactMap { $0.restingHr }
        let avgRhrUnfilled = rhrValues.isEmpty ? nil : rhrValues.reduce(0, +) / Double(rhrValues.count)
        let avgRhr = backfillDoubleIfNeeded(avgRhrUnfilled) { $0.restingHr }
        
        // Build VitalityRawMetrics
        // Note: VitalityData does not yet contain restorative %, efficiency, awake %, 
        // movement minutes, active calories, or breathing rate, so those are nil
        return VitalityRawMetrics(
            age: age,
            sleepDurationHours: avgSleep,
            restorativeSleepPercent: nil,
            sleepEfficiencyPercent: nil,
            awakePercent: nil,
            movementMinutes: nil,
            steps: avgSteps,
            activeCalories: nil,
            hrvMs: avgHrv,
            hrvType: nil,  // Legacy data doesn't track HRV type
            restingHeartRate: avgRhr,
            breathingRate: nil
        )
    }
}

