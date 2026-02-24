import Foundation

/// Family badge computation (pure Swift, no networking).
/// - Daily badges are computed from today's pillar scores (0–100).
/// - Weekly badges are computed from UTC day-keyed `vitality_scores` history.
struct BadgeEngine {
    
    // MARK: - Types
    
    enum WeeklyBadgeType: String, CaseIterable {
        case weekly_vitality_mvp
        case weekly_sleep_mvp
        case weekly_movement_mvp
        case weekly_stressfree_mvp
        case weekly_family_anchor
        case weekly_consistency_mvp
        case weekly_balanced_week
        case weekly_biggest_comeback_day
        case weekly_sleep_streak_leader
        case weekly_movement_streak_leader
        case weekly_stress_streak_leader
        case weekly_data_champion
    }
    
    enum DailyBadgeType: String, CaseIterable {
        case daily_most_sleep
        case daily_most_movement
        case daily_most_stressfree
    }
    
    struct Winner: Identifiable {
        let id = UUID()
        let badgeType: String
        let winnerUserId: String
        let winnerName: String
        let metadata: [String: Any]
    }
    
    struct Member {
        let userId: String
        let name: String
    }
    
    struct ScoreRow {
        let userId: String
        let dayKey: String // YYYY-MM-DD (UTC)
        let total: Int?
        let sleep: Int?
        let movement: Int?
        let stress: Int?
    }
    
    enum Fairness {
        static let dailyBaselineWindowDays: Int = 7
        static let dailyMinHistoryDays: Int = 4
        static let dailyMinAbsoluteDelta: Double = 5.0
        static let dailyMinPercentDelta: Double = 8.0
        
        static let weeklyMinHistoryDays: Int = 5
        static let weeklyMinAbsoluteDelta: Double = 2.0
        static let weeklyMinPercentDelta: Double = 4.0
        
        static let streakThreshold: Int = 75
        static let biggestComebackMinDelta: Int = 6
    }
    
    // MARK: - Public API
    
    /// Compute daily badges based on percentage increase from previous day.
    /// Only awards badges for positive upward trends (increases).
    static func computeDailyBadges(
        members: [Member],
        todayRows: [ScoreRow],
        yesterdayRows: [ScoreRow],
        recentRows: [ScoreRow]
    ) -> [Winner] {
        let nameByUserId = Dictionary(uniqueKeysWithValues: members.map { ($0.userId.lowercased(), $0.name) })
        let todayByUser = Dictionary(uniqueKeysWithValues: todayRows.map { ($0.userId.lowercased(), $0) })
        let sortedRecentByUser = Dictionary(grouping: recentRows, by: { $0.userId.lowercased() })
            .mapValues { rows in rows.sorted { $0.dayKey < $1.dayKey } }
        
        func pickBestIncrease(_ getter: (ScoreRow) -> Int?, badge: DailyBadgeType) -> Winner? {
            var best: (
                uid: String,
                percentIncrease: Double,
                deltaPoints: Double,
                todayVal: Int,
                baselineAvg: Double,
                historyDays: Int
            )? = nil
            
            for (uid, todayUserRows) in todayByUser {
                guard let todayVal = getter(todayUserRows) else { continue }
                guard let recent = sortedRecentByUser[uid], !recent.isEmpty else { continue }
                
                // Build baseline from recent history excluding today's day-key, then take up to 7 latest days.
                let nonTodayHistory = recent
                    .filter { $0.dayKey < todayUserRows.dayKey }
                    .compactMap(getter)
                let baselineValues = Array(nonTodayHistory.suffix(Fairness.dailyBaselineWindowDays))
                guard baselineValues.count >= Fairness.dailyMinHistoryDays else { continue }
                
                let baselineAvg = robustAverage(baselineValues)
                guard baselineAvg > 0 else { continue }
                
                let delta = Double(todayVal) - baselineAvg
                let percentIncrease = (delta / baselineAvg) * 100.0
                
                // Only meaningful positive changes qualify.
                guard delta >= Fairness.dailyMinAbsoluteDelta,
                      percentIncrease >= Fairness.dailyMinPercentDelta else { continue }
                
                if best == nil ||
                    percentIncrease > best!.percentIncrease ||
                    (percentIncrease == best!.percentIncrease && delta > best!.deltaPoints) ||
                    (percentIncrease == best!.percentIncrease && delta == best!.deltaPoints && baselineValues.count > best!.historyDays) ||
                    (percentIncrease == best!.percentIncrease && delta == best!.deltaPoints && baselineValues.count == best!.historyDays && uid < best!.uid) {
                    best = (uid, percentIncrease, delta, todayVal, baselineAvg, baselineValues.count)
                }
            }
            guard let best else { return nil }
            
            return Winner(
                badgeType: badge.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: [
                    "percentIncrease": best.percentIncrease,
                    "deltaPoints": best.deltaPoints,
                    "todayValue": best.todayVal,
                    "baselineAverage": best.baselineAvg,
                    "historyDays": best.historyDays,
                    "baselineWindowDays": Fairness.dailyBaselineWindowDays,
                    "comparisonPeriod": "vs_recent_baseline",
                    "minimumAbsoluteDelta": Fairness.dailyMinAbsoluteDelta,
                    "minimumPercentDelta": Fairness.dailyMinPercentDelta
                ]
            )
        }
        
        return [
            pickBestIncrease({ $0.sleep }, badge: .daily_most_sleep),
            pickBestIncrease({ $0.movement }, badge: .daily_most_movement),
            pickBestIncrease({ $0.stress }, badge: .daily_most_stressfree)
        ].compactMap { $0 }
    }
    
    /// Compute all weekly winners (12). Returns one Winner per badge type if eligible data exists.
    static func computeWeeklyBadges(
        members: [Member],
        thisWeekRows: [ScoreRow],
        prevWeekRows: [ScoreRow],
        last14Rows: [ScoreRow],
        eligibilityMinDays: Int = Fairness.weeklyMinHistoryDays,
        streakThreshold: Int = Fairness.streakThreshold
    ) -> [Winner] {
        let nameByUserId = Dictionary(uniqueKeysWithValues: members.map { ($0.userId.lowercased(), $0.name) })
        
        let thisByUser = Dictionary(grouping: thisWeekRows, by: { $0.userId.lowercased() })
        let prevByUser = Dictionary(grouping: prevWeekRows, by: { $0.userId.lowercased() })
        let last14ByUser = Dictionary(grouping: last14Rows, by: { $0.userId.lowercased() })
        
        func avg(_ xs: [Int]) -> Double? {
            guard !xs.isEmpty else { return nil }
            return Double(xs.reduce(0, +)) / Double(xs.count)
        }
        
        func robustAverage(_ xs: [Int]) -> Double? {
            guard !xs.isEmpty else { return nil }
            let sorted = xs.sorted()
            if sorted.count >= 5 {
                let trimmed = Array(sorted.dropFirst().dropLast())
                guard !trimmed.isEmpty else { return avg(sorted) }
                return avg(trimmed)
            }
            return avg(sorted)
        }
        
        func stddev(_ xs: [Int]) -> Double? {
            guard xs.count >= 2, let m = avg(xs) else { return nil }
            let v = xs.map { pow(Double($0) - m, 2.0) }.reduce(0, +) / Double(xs.count - 1)
            return sqrt(v)
        }
        
        func eligibleValues(_ rows: [ScoreRow], getter: (ScoreRow) -> Int?) -> [Int]? {
            let vals = rows.compactMap(getter)
            return vals.count >= eligibilityMinDays ? vals : nil
        }
        
        func date(_ dayKey: String) -> Date? {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: dayKey)
        }
        
        func longestStreak(dayKeys: [String], values: [Int], threshold: Int) -> Int {
            // Assumes dayKeys aligned to values and both sorted ascending by day.
            var best = 0
            var cur = 0
            var prevDate: Date? = nil
            for (k, v) in zip(dayKeys, values) {
                guard let d = date(k) else { continue }
                let isGood = v >= threshold
                if !isGood {
                    cur = 0
                    prevDate = d
                    continue
                }
                if let p = prevDate {
                    let diff = Calendar(identifier: .gregorian).dateComponents([.day], from: p, to: d).day ?? 99
                    cur = (diff == 1) ? (cur + 1) : 1
                } else {
                    cur = 1
                }
                best = max(best, cur)
                prevDate = d
            }
            return best
        }
        
        func pickMaxDelta(
            badge: WeeklyBadgeType,
            getter: (ScoreRow) -> Int?
        ) -> Winner? {
            var best: (uid: String, percentIncrease: Double, delta: Double, thisAvg: Double, prevAvg: Double, thisDays: Int, prevDays: Int)? = nil
            for (uid, thisRows) in thisByUser {
                guard let thisVals = eligibleValues(thisRows, getter: getter), let aThis = robustAverage(thisVals) else { continue }
                guard let prevRows = prevByUser[uid], let prevVals = eligibleValues(prevRows, getter: getter), let aPrev = robustAverage(prevVals) else { continue }
                
                // Only consider positive increases
                guard aThis > aPrev, aPrev > 0 else { continue }
                let delta = aThis - aPrev
                
                let percentIncrease = (delta / aPrev) * 100.0
                guard delta >= Fairness.weeklyMinAbsoluteDelta,
                      percentIncrease >= Fairness.weeklyMinPercentDelta else { continue }
                
                if best == nil ||
                    percentIncrease > best!.percentIncrease ||
                    (percentIncrease == best!.percentIncrease && delta > best!.delta) ||
                    (percentIncrease == best!.percentIncrease && delta == best!.delta && thisVals.count > best!.thisDays) ||
                    (percentIncrease == best!.percentIncrease && delta == best!.delta && thisVals.count == best!.thisDays && prevVals.count > best!.prevDays) ||
                    (percentIncrease == best!.percentIncrease && delta == best!.delta && thisVals.count == best!.thisDays && prevVals.count == best!.prevDays && uid < best!.uid) {
                    best = (uid, percentIncrease, delta, aThis, aPrev, thisVals.count, prevVals.count)
                }
            }
            guard let best else { return nil }
            return Winner(
                badgeType: badge.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: [
                    "thisAvg": best.thisAvg,
                    "prevAvg": best.prevAvg,
                    "delta": best.delta,
                    "percentIncrease": best.percentIncrease,
                    "thisWeekDays": best.thisDays,
                    "prevWeekDays": best.prevDays,
                    "comparisonPeriod": "this_week_vs_previous_week",
                    "minimumAbsoluteDelta": Fairness.weeklyMinAbsoluteDelta,
                    "minimumPercentDelta": Fairness.weeklyMinPercentDelta
                ]
            )
        }
        
        func pickMaxAvg(
            badge: WeeklyBadgeType,
            getter: (ScoreRow) -> Int?
        ) -> Winner? {
            var best: (uid: String, thisAvg: Double, qualifyingDays: Int)? = nil
            for (uid, thisRows) in thisByUser {
                guard let thisVals = eligibleValues(thisRows, getter: getter), let aThis = robustAverage(thisVals) else { continue }
                if best == nil ||
                    aThis > best!.thisAvg ||
                    (aThis == best!.thisAvg && thisVals.count > best!.qualifyingDays) ||
                    (aThis == best!.thisAvg && thisVals.count == best!.qualifyingDays && uid < best!.uid) {
                    best = (uid, aThis, thisVals.count)
                }
            }
            guard let best else { return nil }
            return Winner(
                badgeType: badge.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: [
                    "thisAvg": best.thisAvg,
                    "thisWeekDays": best.qualifyingDays,
                    "comparisonPeriod": "this_week_highest_average"
                ]
            )
        }
        
        func pickConsistency() -> Winner? {
            var best: (uid: String, sd: Double, qualifyingDays: Int)? = nil
            for (uid, thisRows) in thisByUser {
                guard let vals = eligibleValues(thisRows, getter: { $0.total }), let sd = stddev(vals) else { continue }
                if best == nil ||
                    sd < best!.sd ||
                    (sd == best!.sd && vals.count > best!.qualifyingDays) ||
                    (sd == best!.sd && vals.count == best!.qualifyingDays && uid < best!.uid) {
                    best = (uid, sd, vals.count)
                }
            }
            guard let best else { return nil }
            return Winner(
                badgeType: WeeklyBadgeType.weekly_consistency_mvp.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: [
                    "stddev": best.sd,
                    "thisWeekDays": best.qualifyingDays,
                    "comparisonPeriod": "this_week_lowest_variability"
                ]
            )
        }
        
        func pickBalancedWeek() -> Winner? {
            var best: (uid: String, balance: Double, sleepAvg: Double, moveAvg: Double, stressAvg: Double, qualifyingDays: Int)? = nil
            for uid in thisByUser.keys {
                guard let sleepVals = eligibleValues(thisByUser[uid] ?? [], getter: { $0.sleep }), let aS = avg(sleepVals) else { continue }
                guard let moveVals = eligibleValues(thisByUser[uid] ?? [], getter: { $0.movement }), let aM = avg(moveVals) else { continue }
                guard let stressVals = eligibleValues(thisByUser[uid] ?? [], getter: { $0.stress }), let aR = avg(stressVals) else { continue }
                let bal = min(aS, aM, aR)
                let qualifyingDays = min(sleepVals.count, moveVals.count, stressVals.count)
                if best == nil ||
                    bal > best!.balance ||
                    (bal == best!.balance && qualifyingDays > best!.qualifyingDays) ||
                    (bal == best!.balance && qualifyingDays == best!.qualifyingDays && uid < best!.uid) {
                    best = (uid, bal, aS, aM, aR, qualifyingDays)
                }
            }
            guard let best else { return nil }
            return Winner(
                badgeType: WeeklyBadgeType.weekly_balanced_week.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: [
                    "balance": best.balance,
                    "sleepAvg": best.sleepAvg,
                    "movementAvg": best.moveAvg,
                    "stressAvg": best.stressAvg,
                    "thisWeekDays": best.qualifyingDays,
                    "comparisonPeriod": "this_week_best_balanced_minimum"
                ]
            )
        }
        
        func pickBiggestComebackDay() -> Winner? {
            var best: (uid: String, maxDelta: Int, dayKey: String)? = nil
            for (uid, thisRows) in thisByUser {
                let sorted = thisRows.sorted { $0.dayKey < $1.dayKey }
                guard sorted.count >= 3 else { continue }
                
                // Smooth daily noise by using rolling 3-day averages.
                var smoothed: [(dayKey: String, value: Double)] = []
                for idx in 0..<sorted.count {
                    guard let current = sorted[idx].total else { continue }
                    var window: [Int] = [current]
                    if idx > 0, let prev = sorted[idx - 1].total { window.append(prev) }
                    if idx + 1 < sorted.count, let next = sorted[idx + 1].total { window.append(next) }
                    guard let value = avg(window) else { continue }
                    smoothed.append((dayKey: sorted[idx].dayKey, value: value))
                }
                guard smoothed.count >= 2 else { continue }
                
                var localBest: (d: Int, day: String)? = nil
                for i in 1..<smoothed.count {
                    let delta = Int((smoothed[i].value - smoothed[i - 1].value).rounded())
                    if localBest == nil || delta > localBest!.d {
                        localBest = (delta, smoothed[i].dayKey)
                    }
                }
                guard let localBest, localBest.d >= Fairness.biggestComebackMinDelta else { continue }
                if best == nil ||
                    localBest.d > best!.maxDelta ||
                    (localBest.d == best!.maxDelta && uid < best!.uid) {
                    best = (uid, localBest.d, localBest.day)
                }
            }
            guard let best else { return nil }
            return Winner(
                badgeType: WeeklyBadgeType.weekly_biggest_comeback_day.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: [
                    "maxDelta": best.maxDelta,
                    "dayKey": best.dayKey,
                    "comparisonPeriod": "this_week_smoothed_adjacent_day_delta",
                    "minimumAbsoluteDelta": Fairness.biggestComebackMinDelta
                ]
            )
        }
        
        func pickStreak(badge: WeeklyBadgeType, getter: (ScoreRow) -> Int?) -> Winner? {
            var best: (uid: String, streak: Int, qualifyingDays: Int)? = nil
            for (uid, rows) in last14ByUser {
                let sorted = rows.sorted { $0.dayKey < $1.dayKey }
                let vals = sorted.compactMap(getter)
                let keys = sorted.compactMap { $0.dayKey }
                guard vals.count >= eligibilityMinDays else { continue }
                // Align keys to vals by filtering both with getter non-nil
                var alignedKeys: [String] = []
                var alignedVals: [Int] = []
                for r in sorted {
                    if let v = getter(r) {
                        alignedKeys.append(r.dayKey)
                        alignedVals.append(v)
                    }
                }
                let streak = longestStreak(dayKeys: alignedKeys, values: alignedVals, threshold: streakThreshold)
                if best == nil ||
                    streak > best!.streak ||
                    (streak == best!.streak && alignedVals.count > best!.qualifyingDays) ||
                    (streak == best!.streak && alignedVals.count == best!.qualifyingDays && uid < best!.uid) {
                    best = (uid, streak, alignedVals.count)
                }
            }
            guard let best, best.streak > 0 else { return nil }
            return Winner(
                badgeType: badge.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: [
                    "streakDays": best.streak,
                    "threshold": streakThreshold,
                    "historyDays": best.qualifyingDays,
                    "comparisonPeriod": "last_14_days_longest_streak"
                ]
            )
        }
        
        func pickDataChampion() -> Winner? {
            var best: (uid: String, days: Int)? = nil
            for (uid, rows) in thisByUser {
                // Count days where at least 2 pillar scores are present
                let days = rows.filter { r in
                    let present = [r.sleep, r.movement, r.stress].compactMap { $0 }.count
                    return present >= 2
                }.count
                guard days >= eligibilityMinDays else { continue }
                if best == nil || days > best!.days || (days == best!.days && uid < best!.uid) {
                    best = (uid, days)
                }
            }
            guard let best else { return nil }
            return Winner(
                badgeType: WeeklyBadgeType.weekly_data_champion.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: [
                    "daysWith2PlusPillars": best.days,
                    "comparisonPeriod": "this_week_days_with_two_or_more_pillars"
                ]
            )
        }
        
        // Assemble all weekly winners
        let winners: [Winner] = [
            pickMaxDelta(badge: .weekly_vitality_mvp, getter: { $0.total }),
            pickMaxDelta(badge: .weekly_sleep_mvp, getter: { $0.sleep }),
            pickMaxDelta(badge: .weekly_movement_mvp, getter: { $0.movement }),
            pickMaxDelta(badge: .weekly_stressfree_mvp, getter: { $0.stress }),
            pickMaxAvg(badge: .weekly_family_anchor, getter: { $0.total }),
            pickConsistency(),
            pickBalancedWeek(),
            pickBiggestComebackDay(),
            pickStreak(badge: .weekly_sleep_streak_leader, getter: { $0.sleep }),
            pickStreak(badge: .weekly_movement_streak_leader, getter: { $0.movement }),
            pickStreak(badge: .weekly_stress_streak_leader, getter: { $0.stress }),
            pickDataChampion()
        ].compactMap { $0 }
        
        return winners
    }
    
    private static func robustAverage(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if sorted.count >= 5 {
            let trimmed = Array(sorted.dropFirst().dropLast())
            if !trimmed.isEmpty {
                let sum = trimmed.reduce(0, +)
                return Double(sum) / Double(trimmed.count)
            }
        }
        let sum = sorted.reduce(0, +)
        return Double(sum) / Double(sorted.count)
    }
}


