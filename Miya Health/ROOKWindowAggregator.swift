//
//  ROOKWindowAggregator.swift
//  Miya Health
//
//  Builds a 7–30 day window of daily VitalityRawMetrics from a ROOK export dataset,
//  then aggregates into ONE VitalityRawMetrics by averaging metrics (skipping nils).
//
//  Pairing rules (UTC day keys):
//   - Sleep day key from: sleep_health.sleep_summaries[i].sleep_health.summary.sleep_summary.duration.sleep_date_string
//   - Physical day key from: physical_health.physical_summaries[i].physical_health.summary.physical_summary.metadata.datetime_string
//  Normalize both to "YYYY-MM-DD" (UTC).
//

import Foundation

struct ROOKWindowAggregator {

    /// Build per-day `VitalityRawMetrics` keyed by UTC "YYYY-MM-DD" for the entire dataset.
    /// This is used to backfill the last N days into `vitality_scores` for trend analysis.
    static func buildDailyRawMetricsByUTCKey(
        age: Int,
        dataset: ROOKDataset
    ) -> [(dayKey: String, raw: VitalityRawMetrics)] {
        // Build lookup tables by UTC day key
        let sleepByDay: [String: ROOKSleepSummaryWrapper] = {
            guard let arr = dataset.sleep_health?.sleep_summaries else { return [:] }
            var dict: [String: ROOKSleepSummaryWrapper] = [:]
            for item in arr {
                guard
                    let raw = item.sleep_health?.summary?.sleep_summary?.duration?.sleep_date_string,
                    let dayKey = normalizeUTCYYYYMMDD(from: raw)
                else { continue }
                dict[dayKey] = item
            }
            return dict
        }()
        
        let physicalByDay: [String: ROOKPhysicalSummaryWrapper] = {
            guard let arr = dataset.physical_health?.physical_summaries else { return [:] }
            var dict: [String: ROOKPhysicalSummaryWrapper] = [:]
            for item in arr {
                guard
                    let raw = item.physical_health?.summary?.physical_summary?.metadata?.datetime_string,
                    let dayKey = normalizeUTCYYYYMMDD(from: raw)
                else { continue }
                dict[dayKey] = item
            }
            return dict
        }()
        
        let allKeys = Set(sleepByDay.keys).union(physicalByDay.keys)
        let sortedKeys = allKeys.sorted() // YYYY-MM-DD lexicographic == chronological
        
        let mapped: [(String, VitalityRawMetrics)] = sortedKeys.map { dayKey in
            (dayKey, ROOKDayToMiyaAdapter.mapOneDay(
                age: age,
                sleepSummary: sleepByDay[dayKey],
                physicalSummary: physicalByDay[dayKey]
            ))
        }
        
        return mapped
    }
    
    static func buildWindowRawMetrics(
        age: Int,
        dataset: ROOKDataset,
        windowMaxDays: Int = 30,
        windowMinDays: Int = 7
    ) -> VitalityRawMetrics {
        // Build lookup tables by UTC day key
        let sleepByDay: [String: ROOKSleepSummaryWrapper] = {
            guard let arr = dataset.sleep_health?.sleep_summaries else { return [:] }
            var dict: [String: ROOKSleepSummaryWrapper] = [:]
            for item in arr {
                guard
                    let raw = item.sleep_health?.summary?.sleep_summary?.duration?.sleep_date_string,
                    let dayKey = normalizeUTCYYYYMMDD(from: raw)
                else { continue }
                // If duplicates exist, keep the most recent by preferring later key overwrite;
                // we do not have a reliable timestamp inside sleep_date_string beyond the day.
                dict[dayKey] = item
            }
            return dict
        }()
        
        let physicalByDay: [String: ROOKPhysicalSummaryWrapper] = {
            guard let arr = dataset.physical_health?.physical_summaries else { return [:] }
            var dict: [String: ROOKPhysicalSummaryWrapper] = [:]
            for item in arr {
                guard
                    let raw = item.physical_health?.summary?.physical_summary?.metadata?.datetime_string,
                    let dayKey = normalizeUTCYYYYMMDD(from: raw)
                else { continue }
                // If multiple summaries exist for the same day, overwrite (last wins).
                dict[dayKey] = item
            }
            return dict
        }()
        
        // Union of all day keys present in either sleep or physical
        let allKeys = Set(sleepByDay.keys).union(physicalByDay.keys)
        let sortedKeys = allKeys.sorted() // YYYY-MM-DD lexicographic == chronological
        
        // Window selection: most recent N days (N<=windowMaxDays), else all available
        let windowKeys: [String] = {
            if sortedKeys.count >= windowMaxDays {
                return Array(sortedKeys.suffix(windowMaxDays))
            }
            // If 7–29 exist, use all. If <7 exist, use all anyway.
            // (Behavior unchanged; warn to avoid misleading windowMinDays parameter.)
            if sortedKeys.count < windowMinDays {
                print("ROOKWindowAggregator: only \(sortedKeys.count) days available (<\(windowMinDays)); aggregating what we have")
            }
            return sortedKeys
        }()
        
        // Per-day raw metrics (all available days) so we can backfill from the previous week if needed.
        let dailyByDayKey: [String: VitalityRawMetrics] = Dictionary(
            uniqueKeysWithValues: buildDailyRawMetricsByUTCKey(age: age, dataset: dataset)
        )
        
        // Window days
        let daily: [VitalityRawMetrics] = windowKeys.compactMap { dailyByDayKey[$0] }
        
        // Aggregation helpers
        func avgDouble(_ values: [Double?]) -> Double? {
            let xs = values.compactMap { $0 }
            guard !xs.isEmpty else { return nil }
            return xs.reduce(0.0, +) / Double(xs.count)
        }
        
        func avgIntRounded(_ values: [Int?]) -> Int? {
            let xs = values.compactMap { $0 }
            guard !xs.isEmpty else { return nil }
            let mean = Double(xs.reduce(0, +)) / Double(xs.count)
            return Int(mean.rounded())
        }
        
        // Aggregate all 10 metrics (plus hrvType)
        let sleepDurationHoursUnfilled = avgDouble(daily.map { $0.sleepDurationHours })
        let restorativeSleepPercentUnfilled = avgDouble(daily.map { $0.restorativeSleepPercent })
        let sleepEfficiencyPercentUnfilled = avgDouble(daily.map { $0.sleepEfficiencyPercent })
        let awakePercentUnfilled = avgDouble(daily.map { $0.awakePercent })
        
        let movementMinutesUnfilled = avgDouble(daily.map { $0.movementMinutes })
        let stepsUnfilled = avgIntRounded(daily.map { $0.steps })
        let activeCaloriesUnfilled = avgDouble(daily.map { $0.activeCalories })
        
        let hrvMsUnfilled = avgDouble(daily.map { $0.hrvMs })
        let restingHeartRateUnfilled = avgDouble(daily.map { $0.restingHeartRate })
        let breathingRateUnfilled = avgDouble(daily.map { $0.breathingRate })
        
        // HRV type rollup rules:
        // - If ≥60% of days with HRV are "rmssd" -> "rmssd"
        // - Else if ≥60% are "sdnn" -> "sdnn"
        // - Else if both appear -> "mixed"
        // - Else nil
        let hrvType: String? = {
            let types: [String] = daily.compactMap { day in
                guard day.hrvMs != nil, let t = day.hrvType else { return nil }
                return t
            }
            guard !types.isEmpty else { return nil }
            let total = Double(types.count)
            let rmssdCount = Double(types.filter { $0 == "rmssd" }.count)
            let sdnnCount = Double(types.filter { $0 == "sdnn" }.count)
            if rmssdCount / total >= 0.60 { return "rmssd" }
            if sdnnCount / total >= 0.60 { return "sdnn" }
            if rmssdCount > 0 && sdnnCount > 0 { return "mixed" }
            return nil
        }()
        
        // Backfill missing metrics from the previous week (last-known-value, max 7 days).
        // If a metric is nil across the current window, look back up to 7 previous days
        // and use the most recent non-nil value found. Never invent values, never average across weeks.
        let lookbackKeys: [String] = {
            guard let startKey = windowKeys.first, let startDate = parseUTCYYYYMMDD(startKey) else { return [] }
            guard let lookbackStart = Calendar.current.date(byAdding: .day, value: -7, to: startDate) else { return [] }
            // Prior keys only (strictly before the window start), within lookbackStart...<startDate
            return sortedKeys.filter { key in
                guard let d = parseUTCYYYYMMDD(key) else { return false }
                return d < startDate && d >= lookbackStart
            }
        }()
        
        func backfillDoubleIfNeeded(_ current: Double?, getter: (VitalityRawMetrics) -> Double?) -> Double? {
            guard current == nil else { return current }
            for key in lookbackKeys.reversed() {
                if let day = dailyByDayKey[key], let v = getter(day) { return v }
            }
            return nil
        }
        
        func backfillIntIfNeeded(_ current: Int?, getter: (VitalityRawMetrics) -> Int?) -> Int? {
            guard current == nil else { return current }
            for key in lookbackKeys.reversed() {
                if let day = dailyByDayKey[key], let v = getter(day) { return v }
            }
            return nil
        }
        
        // HRV: if missing across window, backfill most recent HRV (and carry its type if available).
        let lastKnownHrvFromLookback: (ms: Double, type: String?)? = {
            for key in lookbackKeys.reversed() {
                guard let day = dailyByDayKey[key], let ms = day.hrvMs else { continue }
                return (ms, day.hrvType)
            }
            return nil
        }()
        
        let sleepDurationHours = backfillDoubleIfNeeded(sleepDurationHoursUnfilled) { $0.sleepDurationHours }
        let restorativeSleepPercent = backfillDoubleIfNeeded(restorativeSleepPercentUnfilled) { $0.restorativeSleepPercent }
        let sleepEfficiencyPercent = backfillDoubleIfNeeded(sleepEfficiencyPercentUnfilled) { $0.sleepEfficiencyPercent }
        let awakePercent = backfillDoubleIfNeeded(awakePercentUnfilled) { $0.awakePercent }
        
        let movementMinutes = backfillDoubleIfNeeded(movementMinutesUnfilled) { $0.movementMinutes }
        let steps = backfillIntIfNeeded(stepsUnfilled) { $0.steps }
        let activeCalories = backfillDoubleIfNeeded(activeCaloriesUnfilled) { $0.activeCalories }
        
        let hrvMs = hrvMsUnfilled ?? lastKnownHrvFromLookback?.ms
        let restingHeartRate = backfillDoubleIfNeeded(restingHeartRateUnfilled) { $0.restingHeartRate }
        let breathingRate = backfillDoubleIfNeeded(breathingRateUnfilled) { $0.breathingRate }
        
        let hrvTypeBackfilled: String? = {
            if hrvMsUnfilled == nil, let t = lastKnownHrvFromLookback?.type { return t }
            return hrvType
        }()
        
        return VitalityRawMetrics(
            age: age,
            sleepDurationHours: sleepDurationHours,
            restorativeSleepPercent: restorativeSleepPercent,
            sleepEfficiencyPercent: sleepEfficiencyPercent,
            awakePercent: awakePercent,
            movementMinutes: movementMinutes,
            steps: steps,
            activeCalories: activeCalories,
            hrvMs: hrvMs,
            hrvType: hrvTypeBackfilled,
            restingHeartRate: restingHeartRate,
            breathingRate: breathingRate
        )
    }
    
    // MARK: - Date Normalization
    
    /// Normalize a ROOK date/datetime string to UTC "YYYY-MM-DD".
    /// Supports ISO8601 with/without fractional seconds, plus plain "YYYY-MM-DD".
    private static func normalizeUTCYYYYMMDD(from raw: String) -> String? {
        // Fast path for plain date
        if raw.count >= 10 {
            let prefix10 = String(raw.prefix(10))
            // Cheap structural check before DateFormatter parse.
            // (Avoids String integer subscripting; DateFormatter parse is the final truth.)
            if prefix10.count == 10, prefix10.split(separator: "-").count == 3 {
                // If prefix parses as date, accept it.
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = "yyyy-MM-dd"
                if df.date(from: prefix10) != nil {
                    return prefix10
                }
            }
        }
        
        // ISO8601 parsing
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        if let d = iso.date(from: raw) {
            return formatUTCYYYYMMDD(d)
        }
        
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        isoNoFrac.timeZone = TimeZone(secondsFromGMT: 0)
        if let d = isoNoFrac.date(from: raw) {
            return formatUTCYYYYMMDD(d)
        }
        
        // Fallback: try replacing space with T (some ROOK granular timestamps use spaces)
        let normalized = raw.replacingOccurrences(of: " ", with: "T")
        if let d = iso.date(from: normalized) ?? isoNoFrac.date(from: normalized) {
            return formatUTCYYYYMMDD(d)
        }
        
        return nil
    }
    
    private static func formatUTCYYYYMMDD(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
    
    private static func parseUTCYYYYMMDD(_ dayKey: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: dayKey)
    }
}


