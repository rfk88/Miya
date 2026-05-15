import Foundation

// MARK: - Weekly family vitality series (client-side from daily RPC rows)

/// Buckets `get_family_vitality_scores` rows into ISO-week (UTC) aggregates for charts and arrows.
enum FamilyVitalityWeeklyAggregates {
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var isoUTCCalendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return cal
    }

    struct WeeklyPoint: Identifiable, Equatable {
        /// Stable key: UTC Monday (or ISO week start) as yyyy-MM-dd
        var id: String { weekStartDayKey }
        let weekStartDayKey: String
        let weekStartDate: Date
        let value: Double
    }

    enum WeekTrendGlyph: Equatable {
        case up
        case flat
        case down
        case insufficientData
    }

    static func pillarColumnValue(_ row: DataManager.FamilyVitalityScoreRow, pillar: VitalityPillar) -> Int? {
        switch pillar {
        case .sleep: return row.sleepPillar
        case .movement: return row.movementPillar
        case .stress: return row.stressPillar
        }
    }

    /// Mean of member `totalScore` per calendar day (UTC key), then mean of those daily averages per ISO week.
    static func weeklyFamilyTotalSeries(
        rows: [DataManager.FamilyVitalityScoreRow],
        maxWeeks: Int = 6
    ) -> [WeeklyPoint] {
        let daily = dailyAverages(rows: rows, value: { $0.totalScore })
        return weeklyMeans(fromDaily: daily, maxWeeks: maxWeeks)
    }

    /// Family-wide mean pillar score per day, then weekly mean (same pattern as total).
    static func weeklyFamilyPillarSeries(
        rows: [DataManager.FamilyVitalityScoreRow],
        pillar: VitalityPillar,
        maxWeeks: Int = 6
    ) -> [WeeklyPoint] {
        let daily = dailyAverages(rows: rows, value: { pillarColumnValue($0, pillar: pillar) })
        return weeklyMeans(fromDaily: daily, maxWeeks: maxWeeks)
    }

    /// One member's mean `totalScore` per UTC day, then weekly mean (ISO weeks), up to `maxWeeks` points.
    static func weeklyMemberTotalSeries(
        rows: [DataManager.FamilyVitalityScoreRow],
        userId: String,
        maxWeeks: Int = 6
    ) -> [WeeklyPoint] {
        let daily = dailyMemberValues(rows: rows, userId: userId, value: { $0.totalScore })
        return weeklyMeans(fromDaily: daily, maxWeeks: maxWeeks)
    }

    /// One member's pillar scores averaged per day, then weekly mean.
    static func weeklyMemberPillarSeries(
        rows: [DataManager.FamilyVitalityScoreRow],
        userId: String,
        pillar: VitalityPillar,
        maxWeeks: Int = 6
    ) -> [WeeklyPoint] {
        let daily = dailyMemberValues(rows: rows, userId: userId, value: { pillarColumnValue($0, pillar: pillar) })
        return weeklyMeans(fromDaily: daily, maxWeeks: maxWeeks)
    }

    /// Compare the last two weekly points in chronological order. No fake arrows: `.insufficientData` if < 2 weeks.
    static func weekOverWeekTrend(series: [WeeklyPoint], flatEpsilon: Double = 0.75) -> WeekTrendGlyph {
        let sorted = series.sorted { $0.weekStartDate < $1.weekStartDate }
        guard sorted.count >= 2,
              let last = sorted.last,
              let prev = sorted.dropLast().last else { return .insufficientData }
        let d = last.value - prev.value
        if d > flatEpsilon { return .up }
        if d < -flatEpsilon { return .down }
        return .flat
    }

    // MARK: - Private

    private struct DailyAvg {
        let dayKey: String
        let date: Date
        let average: Double
    }

    /// Groups rows by `scoreDate`, averages non-nil integers from `value` per member row.
    private static func dailyAverages(
        rows: [DataManager.FamilyVitalityScoreRow],
        value: (DataManager.FamilyVitalityScoreRow) -> Int?
    ) -> [DailyAvg] {
        var buckets: [String: [Int]] = [:]
        for row in rows {
            guard let v = value(row) else { continue }
            buckets[row.scoreDate, default: []].append(v)
        }
        return buckets.compactMap { key, vals in
            guard !vals.isEmpty,
                  let date = dayKeyFormatter.date(from: key) else { return nil }
            let avg = Double(vals.reduce(0, +)) / Double(vals.count)
            return DailyAvg(dayKey: key, date: date, average: avg)
        }
    }

    /// Per-day values for a single `userId` (averages if multiple rows share a day).
    private static func dailyMemberValues(
        rows: [DataManager.FamilyVitalityScoreRow],
        userId: String,
        value: (DataManager.FamilyVitalityScoreRow) -> Int?
    ) -> [DailyAvg] {
        let filtered = rows.filter { $0.userId == userId }
        var buckets: [String: [Int]] = [:]
        for row in filtered {
            guard let v = value(row) else { continue }
            buckets[row.scoreDate, default: []].append(v)
        }
        return buckets.compactMap { key, vals in
            guard !vals.isEmpty,
                  let date = dayKeyFormatter.date(from: key) else { return nil }
            let avg = Double(vals.reduce(0, +)) / Double(vals.count)
            return DailyAvg(dayKey: key, date: date, average: avg)
        }
    }

    private static func weeklyMeans(fromDaily daily: [DailyAvg], maxWeeks: Int) -> [WeeklyPoint] {
        guard !daily.isEmpty else { return [] }
        var byWeek: [String: [Double]] = [:]
        for d in daily {
            guard let weekStartKey = weekStartDayKey(containingUTCDate: d.date) else { continue }
            byWeek[weekStartKey, default: []].append(d.average)
        }
        let sortedKeys: [(String, Date)] = byWeek.keys.compactMap { key in
            guard let date = dayKeyFormatter.date(from: key) else { return nil }
            return (key, date)
        }
        .sorted { $0.1 < $1.1 }

        let trimmed = Array(sortedKeys.suffix(maxWeeks))
        return trimmed.compactMap { pair in
            let vals = byWeek[pair.0] ?? []
            guard !vals.isEmpty else { return nil }
            let mean = vals.reduce(0, +) / Double(vals.count)
            return WeeklyPoint(weekStartDayKey: pair.0, weekStartDate: pair.1, value: mean)
        }
    }

    private static func weekStartDayKey(containingUTCDate date: Date) -> String? {
        let cal = isoUTCCalendar
        guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else { return nil }
        return dayKeyFormatter.string(from: interval.start)
    }
}

// MARK: - ~42d fetch window (UTC day keys)

enum FamilyVitalityHistoryFetch {
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Inclusive ~42-day window ending today (UTC): `(startDate, endDate)` as `yyyy-MM-dd`.
    static func fortyTwoDayWindowKeys() -> (start: String, end: String) {
        let end = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let start = cal.date(byAdding: .day, value: -41, to: end) ?? end
        return (dayKeyFormatter.string(from: start), dayKeyFormatter.string(from: end))
    }

    static func loadFamilyScoreRows(
        dataManager: DataManager,
        familyMemberUserIds: [String]
    ) async throws -> [DataManager.FamilyVitalityScoreRow] {
        guard let familyId = dataManager.currentFamilyId else { return [] }
        let range = fortyTwoDayWindowKeys()
        do {
            return try await dataManager.fetchFamilyVitalityScores(
                familyId: familyId,
                startDate: range.start,
                endDate: range.end
            )
        } catch {
            let ids = familyMemberUserIds.filter { !$0.isEmpty }
            guard !ids.isEmpty else { throw error }
            return try await dataManager.fetchFamilyVitalityScoresFallbackByUserIds(
                userIds: ids,
                startDate: range.start,
                endDate: range.end
            )
        }
    }
}
