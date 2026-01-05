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
    
    // MARK: - Public API
    
    /// Compute daily badges based on percentage increase from previous day.
    /// Only awards badges for positive upward trends (increases).
    static func computeDailyBadges(
        members: [Member],
        todayRows: [ScoreRow],
        yesterdayRows: [ScoreRow]
    ) -> [Winner] {
        let nameByUserId = Dictionary(uniqueKeysWithValues: members.map { ($0.userId.lowercased(), $0.name) })
        let todayByUser = Dictionary(grouping: todayRows, by: { $0.userId.lowercased() })
        let yesterdayByUser = Dictionary(grouping: yesterdayRows, by: { $0.userId.lowercased() })
        
        func pickBestIncrease(_ getter: (ScoreRow) -> Int?, badge: DailyBadgeType) -> Winner? {
            var best: (uid: String, percentIncrease: Double, todayVal: Int, yesterdayVal: Int)? = nil
            for (uid, todayUserRows) in todayByUser {
                guard let todayRow = todayUserRows.last, let todayVal = getter(todayRow) else { continue }
                guard let yesterdayUserRows = yesterdayByUser[uid], let yesterdayRow = yesterdayUserRows.last, let yesterdayVal = getter(yesterdayRow) else { continue }
                
                // Only consider positive increases
                guard todayVal > yesterdayVal, yesterdayVal > 0 else { continue }
                
                let percentIncrease = (Double(todayVal - yesterdayVal) / Double(yesterdayVal)) * 100.0
                
                if best == nil || percentIncrease > best!.percentIncrease {
                    best = (uid, percentIncrease, todayVal, yesterdayVal)
                }
            }
            guard let best else { return nil }
            return Winner(
                badgeType: badge.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: [
                    "percentIncrease": best.percentIncrease,
                    "todayValue": best.todayVal,
                    "yesterdayValue": best.yesterdayVal
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
        eligibilityMinDays: Int = 5,
        streakThreshold: Int = 75
    ) -> [Winner] {
        let nameByUserId = Dictionary(uniqueKeysWithValues: members.map { ($0.userId.lowercased(), $0.name) })
        
        let thisByUser = Dictionary(grouping: thisWeekRows, by: { $0.userId.lowercased() })
        let prevByUser = Dictionary(grouping: prevWeekRows, by: { $0.userId.lowercased() })
        let last14ByUser = Dictionary(grouping: last14Rows, by: { $0.userId.lowercased() })
        
        func avg(_ xs: [Int]) -> Double? {
            guard !xs.isEmpty else { return nil }
            return Double(xs.reduce(0, +)) / Double(xs.count)
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
            var best: (uid: String, percentIncrease: Double, thisAvg: Double, prevAvg: Double)? = nil
            for (uid, thisRows) in thisByUser {
                guard let thisVals = eligibleValues(thisRows, getter: getter), let aThis = avg(thisVals) else { continue }
                guard let prevRows = prevByUser[uid], let prevVals = eligibleValues(prevRows, getter: getter), let aPrev = avg(prevVals) else { continue }
                
                // Only consider positive increases
                guard aThis > aPrev, aPrev > 0 else { continue }
                
                let percentIncrease = ((aThis - aPrev) / aPrev) * 100.0
                
                if best == nil || percentIncrease > best!.percentIncrease {
                    best = (uid, percentIncrease, aThis, aPrev)
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
                    "delta": best.thisAvg - best.prevAvg,
                    "percentIncrease": best.percentIncrease
                ]
            )
        }
        
        func pickMaxAvg(
            badge: WeeklyBadgeType,
            getter: (ScoreRow) -> Int?
        ) -> Winner? {
            var best: (uid: String, thisAvg: Double)? = nil
            for (uid, thisRows) in thisByUser {
                guard let thisVals = eligibleValues(thisRows, getter: getter), let aThis = avg(thisVals) else { continue }
                if best == nil || aThis > best!.thisAvg {
                    best = (uid, aThis)
                }
            }
            guard let best else { return nil }
            return Winner(
                badgeType: badge.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: ["thisAvg": best.thisAvg]
            )
        }
        
        func pickConsistency() -> Winner? {
            var best: (uid: String, sd: Double)? = nil
            for (uid, thisRows) in thisByUser {
                guard let vals = eligibleValues(thisRows, getter: { $0.total }), let sd = stddev(vals) else { continue }
                if best == nil || sd < best!.sd {
                    best = (uid, sd)
                }
            }
            guard let best else { return nil }
            return Winner(
                badgeType: WeeklyBadgeType.weekly_consistency_mvp.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: ["stddev": best.sd]
            )
        }
        
        func pickBalancedWeek() -> Winner? {
            var best: (uid: String, balance: Double, sleepAvg: Double, moveAvg: Double, stressAvg: Double)? = nil
            for uid in thisByUser.keys {
                guard let sleepVals = eligibleValues(thisByUser[uid] ?? [], getter: { $0.sleep }), let aS = avg(sleepVals) else { continue }
                guard let moveVals = eligibleValues(thisByUser[uid] ?? [], getter: { $0.movement }), let aM = avg(moveVals) else { continue }
                guard let stressVals = eligibleValues(thisByUser[uid] ?? [], getter: { $0.stress }), let aR = avg(stressVals) else { continue }
                let bal = min(aS, aM, aR)
                if best == nil || bal > best!.balance {
                    best = (uid, bal, aS, aM, aR)
                }
            }
            guard let best else { return nil }
            return Winner(
                badgeType: WeeklyBadgeType.weekly_balanced_week.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: ["balance": best.balance, "sleepAvg": best.sleepAvg, "movementAvg": best.moveAvg, "stressAvg": best.stressAvg]
            )
        }
        
        func pickBiggestComebackDay() -> Winner? {
            var best: (uid: String, maxDelta: Int, dayKey: String)? = nil
            for (uid, thisRows) in thisByUser {
                let sorted = thisRows.sorted { $0.dayKey < $1.dayKey }
                let vals = sorted.compactMap { $0.total }
                let keys = sorted.map { $0.dayKey }
                guard vals.count >= 2 else { continue }
                var localBest: (d: Int, day: String)? = nil
                // Compare adjacent available totals (simple; missing days naturally reduce comparisons)
                for i in 1..<sorted.count {
                    guard let prev = sorted[i-1].total, let cur = sorted[i].total else { continue }
                    let delta = cur - prev
                    if localBest == nil || delta > localBest!.d {
                        localBest = (delta, keys[i])
                    }
                }
                guard let localBest else { continue }
                if best == nil || localBest.d > best!.maxDelta {
                    best = (uid, localBest.d, localBest.day)
                }
            }
            guard let best else { return nil }
            return Winner(
                badgeType: WeeklyBadgeType.weekly_biggest_comeback_day.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: ["maxDelta": best.maxDelta, "dayKey": best.dayKey]
            )
        }
        
        func pickStreak(badge: WeeklyBadgeType, getter: (ScoreRow) -> Int?) -> Winner? {
            var best: (uid: String, streak: Int)? = nil
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
                if best == nil || streak > best!.streak {
                    best = (uid, streak)
                }
            }
            guard let best, best.streak > 0 else { return nil }
            return Winner(
                badgeType: badge.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: ["streakDays": best.streak, "threshold": streakThreshold]
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
                if best == nil || days > best!.days {
                    best = (uid, days)
                }
            }
            guard let best else { return nil }
            return Winner(
                badgeType: WeeklyBadgeType.weekly_data_champion.rawValue,
                winnerUserId: best.uid,
                winnerName: nameByUserId[best.uid] ?? "Member",
                metadata: ["daysWith2PlusPillars": best.days]
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
}


