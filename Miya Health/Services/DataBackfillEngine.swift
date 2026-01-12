//
//  DataBackfillEngine.swift
//  Miya Health
//
//  Intelligent data backfill for missing days and sub-metrics with recency limits
//

import Foundation

// MARK: - Input Models

struct DailyDataPoint {
    let date: String // YYYY-MM-DD
    let value: Double?
    let subMetrics: [String: Double?] // e.g., ["steps": 8234, "movement_minutes": nil]
}

// MARK: - Output Models

struct BackfilledDataPoint {
    let date: String
    let value: Double?
    let isBackfilled: Bool
    let sourceDate: String? // date of source data if backfilled
    let ageInDays: Int? // how old the source data was
    let subMetrics: [String: SubMetricValue]
}

struct SubMetricValue {
    let value: Double
    let isBackfilled: Bool
    let sourceDate: String?
    let ageInDays: Int?
}

struct BackfillMetadata {
    let totalDaysBackfilled: Int
    let affectedMetrics: [String] // e.g., ["steps", "movement_minutes"]
    let oldestSourceAgeInDays: Int // for notification context
    let membersAffected: Int // number of members with backfilled data
}

// MARK: - Backfill Engine

struct DataBackfillEngine {
    
    /// Backfill missing days and sub-metrics in a time series with intelligent lookback
    /// - Parameters:
    ///   - series: Array of daily data points (may have gaps)
    ///   - recencyLimitDays: Maximum age of source data for backfill (default 3 days)
    ///   - targetWindowDays: Number of days in the target window (default 7)
    /// - Returns: Tuple of filled data points and metadata about what was backfilled
    static func backfillSeries(
        _ series: [DailyDataPoint],
        recencyLimitDays: Int = 3,
        targetWindowDays: Int = 7
    ) -> (filled: [BackfilledDataPoint], metadata: BackfillMetadata) {
        
        guard !series.isEmpty else {
            return ([], BackfillMetadata(
                totalDaysBackfilled: 0,
                affectedMetrics: [],
                oldestSourceAgeInDays: 0,
                membersAffected: 0
            ))
        }
        
        // Sort by date
        let sorted = series.sorted { $0.date < $1.date }
        
        // Determine target date range (last N days)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        guard let lastDate = dateFormatter.date(from: sorted.last?.date ?? ""),
              let firstTargetDate = Calendar.current.date(byAdding: .day, value: -(targetWindowDays - 1), to: lastDate) else {
            return (sorted.map { convertToBackfilled($0, isBackfilled: false) }, BackfillMetadata(
                totalDaysBackfilled: 0,
                affectedMetrics: [],
                oldestSourceAgeInDays: 0,
                membersAffected: 0
            ))
        }
        
        let firstTargetString = dateFormatter.string(from: firstTargetDate)
        let lastTargetString = sorted.last?.date ?? ""
        
        // Build complete date range for target window
        var targetDates: [String] = []
        var currentDate = firstTargetDate
        while currentDate <= lastDate {
            targetDates.append(dateFormatter.string(from: currentDate))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = next
        }
        
        // Create lookup map for existing data
        let dataByDate = Dictionary(uniqueKeysWithValues: sorted.map { ($0.date, $0) })
        
        // Backfill missing days
        var filled: [BackfilledDataPoint] = []
        var daysBackfilled = 0
        var oldestSourceAge = 0
        var allAffectedMetrics = Set<String>()
        
        for targetDate in targetDates {
            if let existing = dataByDate[targetDate] {
                // Data exists for this day
                filled.append(convertToBackfilled(existing, isBackfilled: false))
            } else {
                // Missing day - look back for source data
                if let backfilled = backfillDay(
                    targetDate: targetDate,
                    existingData: sorted,
                    recencyLimitDays: recencyLimitDays,
                    dateFormatter: dateFormatter
                ) {
                    filled.append(backfilled)
                    daysBackfilled += 1
                    if let age = backfilled.ageInDays {
                        oldestSourceAge = max(oldestSourceAge, age)
                    }
                    // Track affected metrics
                    for (key, subMetric) in backfilled.subMetrics {
                        if subMetric.isBackfilled {
                            allAffectedMetrics.insert(key)
                        }
                    }
                } else {
                    // No source data within recency limit - leave as nil
                    filled.append(BackfilledDataPoint(
                        date: targetDate,
                        value: nil,
                        isBackfilled: false,
                        sourceDate: nil,
                        ageInDays: nil,
                        subMetrics: [:]
                    ))
                }
            }
        }
        
        // Backfill missing sub-metrics within existing days
        for i in 0..<filled.count {
            let point = filled[i]
            if point.value != nil { // Only backfill sub-metrics if we have a day with data
                var updatedSubMetrics = point.subMetrics
                
                // Get all unique metric keys from the series
                let allMetricKeys = Set(sorted.flatMap { $0.subMetrics.keys })
                
                for metricKey in allMetricKeys {
                    // If this metric is missing for this day, try to backfill it
                    if point.subMetrics[metricKey] == nil {
                        if let backfilledMetric = backfillSubMetric(
                            targetDate: point.date,
                            metricKey: metricKey,
                            existingData: sorted,
                            recencyLimitDays: recencyLimitDays,
                            dateFormatter: dateFormatter
                        ) {
                            updatedSubMetrics[metricKey] = backfilledMetric
                            if backfilledMetric.isBackfilled {
                                allAffectedMetrics.insert(metricKey)
                                if let age = backfilledMetric.ageInDays {
                                    oldestSourceAge = max(oldestSourceAge, age)
                                }
                            }
                        }
                    }
                }
                
                filled[i] = BackfilledDataPoint(
                    date: point.date,
                    value: point.value,
                    isBackfilled: point.isBackfilled,
                    sourceDate: point.sourceDate,
                    ageInDays: point.ageInDays,
                    subMetrics: updatedSubMetrics
                )
            }
        }
        
        let metadata = BackfillMetadata(
            totalDaysBackfilled: daysBackfilled,
            affectedMetrics: Array(allAffectedMetrics),
            oldestSourceAgeInDays: oldestSourceAge,
            membersAffected: daysBackfilled > 0 ? 1 : 0 // Will be aggregated at caller level
        )
        
        return (filled, metadata)
    }
    
    // MARK: - Private Helpers
    
    private static func backfillDay(
        targetDate: String,
        existingData: [DailyDataPoint],
        recencyLimitDays: Int,
        dateFormatter: DateFormatter
    ) -> BackfilledDataPoint? {
        
        guard let target = dateFormatter.date(from: targetDate) else { return nil }
        
        // Look back up to recencyLimitDays for the most recent non-nil value
        for daysBack in 1...recencyLimitDays {
            guard let lookbackDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: target),
                  let lookbackString = Optional(dateFormatter.string(from: lookbackDate)) else {
                continue
            }
            
            if let source = existingData.first(where: { $0.date == lookbackString && $0.value != nil }) {
                // Found source data - backfill with it
                return BackfilledDataPoint(
                    date: targetDate,
                    value: source.value,
                    isBackfilled: true,
                    sourceDate: source.date,
                    ageInDays: daysBack,
                    subMetrics: source.subMetrics.mapValues { value in
                        SubMetricValue(
                            value: value ?? 0,
                            isBackfilled: value == nil ? false : true,
                            sourceDate: source.date,
                            ageInDays: daysBack
                        )
                    }
                )
            }
        }
        
        return nil
    }
    
    private static func backfillSubMetric(
        targetDate: String,
        metricKey: String,
        existingData: [DailyDataPoint],
        recencyLimitDays: Int,
        dateFormatter: DateFormatter
    ) -> SubMetricValue? {
        
        guard let target = dateFormatter.date(from: targetDate) else { return nil }
        
        // Look back up to recencyLimitDays for the most recent non-nil value for this metric
        for daysBack in 1...recencyLimitDays {
            guard let lookbackDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: target),
                  let lookbackString = Optional(dateFormatter.string(from: lookbackDate)) else {
                continue
            }
            
            if let source = existingData.first(where: { $0.date == lookbackString }),
               let metricValue = source.subMetrics[metricKey],
               let value = metricValue {
                // Found source data for this metric
                return SubMetricValue(
                    value: value,
                    isBackfilled: true,
                    sourceDate: source.date,
                    ageInDays: daysBack
                )
            }
        }
        
        return nil
    }
    
    private static func convertToBackfilled(_ point: DailyDataPoint, isBackfilled: Bool) -> BackfilledDataPoint {
        return BackfilledDataPoint(
            date: point.date,
            value: point.value,
            isBackfilled: isBackfilled,
            sourceDate: isBackfilled ? point.date : nil,
            ageInDays: isBackfilled ? 0 : nil,
            subMetrics: point.subMetrics.mapValues { value in
                guard let val = value else {
                    return SubMetricValue(
                        value: 0,
                        isBackfilled: false,
                        sourceDate: nil,
                        ageInDays: nil
                    )
                }
                return SubMetricValue(
                    value: val,
                    isBackfilled: isBackfilled,
                    sourceDate: isBackfilled ? point.date : nil,
                    ageInDays: isBackfilled ? 0 : nil
                )
            }
        )
    }
}
