import Foundation
import SwiftUI

/// Builds `ChampionsData` from the same `BadgeEngine.ScoreRow` windows used for weekly badges.
/// Season points use a **proxy**: sum of `total` pillar across all fetched day-rows for the member (see `totalPointsProxy`).
enum ChampionsSnapshotBuilder {

    private static let eligibilityMinDays = BadgeEngine.Fairness.weeklyMinHistoryDays
    private static let closeFraction: Double = 0.85

    // MARK: - Public

    static func build(
        familyMembers: [FamilyMemberScore],
        thisWeekRows: [BadgeEngine.ScoreRow],
        prevWeekRows: [BadgeEngine.ScoreRow],
        validMapped: [BadgeEngine.ScoreRow],
        weekStartKey: String,
        weekEndKey: String,
        referenceNow: Date = Date()
    ) -> ChampionsData? {
        let active = familyMembers.filter { !$0.isPending && $0.userId != nil }
        guard active.count >= 2 else { return nil }

        let membersChampion: [ChampionMember] = active.map { fm in
            let uid = fm.userId!.lowercased()
            let pts = totalPointsProxy(userId: uid, rows: validMapped)
            let accent = ChampionsTokens.memberAccentPalette[abs(uid.hashValue) % ChampionsTokens.memberAccentPalette.count]
            return ChampionMember(
                id: uid,
                name: fm.name,
                avatarURL: nil,
                accentColor: accent,
                totalPoints: pts
            )
        }

        let thisByUser = Dictionary(grouping: thisWeekRows, by: { $0.userId.lowercased() })
        let prevByUser = Dictionary(grouping: prevWeekRows, by: { $0.userId.lowercased() })

        var categories: [ChampionCategory] = []
        for cat in ChampionCategoryType.allCases {
            let rows = rankedRows(
                category: cat,
                memberIds: active.compactMap { $0.userId?.lowercased() },
                thisByUser: thisByUser,
                prevByUser: prevByUser
            )
            if !rows.isEmpty {
                categories.append(ChampionCategory(id: cat, rows: rows))
            }
        }

        let season = makeSeasonInfo(weekEndKey: weekEndKey, referenceNow: referenceNow)
        let isLive = isLiveWeekdayUTC(referenceNow)

        return ChampionsData(
            season: season,
            categories: categories,
            members: membersChampion,
            isLive: isLive
        )
    }

    /// Screenshot / fallback when no score rows: derive leaders from persisted weekly winners metadata.
    static func buildFallbackFromWeeklyWinners(
        familyMembers: [FamilyMemberScore],
        weeklyWinners: [BadgeEngine.Winner],
        weekStartKey: String,
        weekEndKey: String,
        referenceNow: Date = Date()
    ) -> ChampionsData? {
        let active = familyMembers.filter { !$0.isPending && $0.userId != nil }
        guard active.count >= 2 else { return nil }

        func metaDouble(_ w: BadgeEngine.Winner, _ key: String) -> Double? {
            w.metadata[key] as? Double
        }

        func metaInt(_ w: BadgeEngine.Winner, _ key: String) -> Int? {
            w.metadata[key] as? Int
        }

        var vitalityByUser: [String: Double] = [:]
        var sleepByUser: [String: Double] = [:]
        var moveByUser: [String: Double] = [:]
        var recoveryByUser: [String: Double] = [:]

        for w in weeklyWinners {
            let uid = w.winnerUserId.lowercased()
            switch w.badgeType {
            case "weekly_vitality_mvp":
                if let p = metaDouble(w, "percentIncrease") { vitalityByUser[uid] = p }
            case "weekly_sleep_mvp":
                if let a = metaDouble(w, "thisAvg") { sleepByUser[uid] = a }
            case "weekly_movement_mvp":
                if let a = metaDouble(w, "thisAvg") { moveByUser[uid] = a }
            case "weekly_stressfree_mvp":
                if let a = metaDouble(w, "thisAvg") { recoveryByUser[uid] = a }
            default:
                break
            }
        }

        let membersChampion: [ChampionMember] = active.map { fm in
            let uid = fm.userId!.lowercased()
            let base = (metaIntFromMembers(fm) ?? 0) * 12
            let accent = ChampionsTokens.memberAccentPalette[abs(uid.hashValue) % ChampionsTokens.memberAccentPalette.count]
            return ChampionMember(id: uid, name: fm.name, avatarURL: nil, accentColor: accent, totalPoints: min(5000, max(0, base)))
        }

        func buildCategory(_ type: ChampionCategoryType, values: [String: Double], vitalityFormat: Bool) -> ChampionCategory {
            let ids = active.compactMap { $0.userId?.lowercased() }
            let scored: [(String, Double)] = ids.map { ($0, values[$0] ?? -1) }.filter { $0.1 >= 0 }.sorted { $0.1 > $1.1 }
            guard let leaderScore = scored.first?.1 else {
                return ChampionCategory(id: type, rows: [])
            }
            var rows: [CategoryMemberRow] = []
            for (idx, pair) in scored.enumerated() {
                let id = pair.0
                let v = pair.1
                let isLeader = idx == 0
                let close = !isLeader && v >= leaderScore * closeFraction
                let status: MemberStatus = isLeader ? .leading : (close ? .close : .trailing)
                let display: String = vitalityFormat ? "+\(Int(v.rounded()))" : "\(Int(v.rounded()))"
                rows.append(CategoryMemberRow(id: id, status: status, displayValue: display))
            }
            // Append members without scores as trailing
            for id in ids where rows.firstIndex(where: { $0.id == id }) == nil {
                rows.append(CategoryMemberRow(id: id, status: .trailing, displayValue: "0"))
            }
            return ChampionCategory(id: type, rows: rows)
        }

        var cats: [ChampionCategory] = []
        let vCat = buildCategory(.vitality, values: vitalityByUser, vitalityFormat: true)
        if !vCat.rows.isEmpty { cats.append(vCat) }
        let sCat = buildCategory(.sleep, values: sleepByUser, vitalityFormat: false)
        if !sCat.rows.isEmpty { cats.append(sCat) }
        let mCat = buildCategory(.movement, values: moveByUser, vitalityFormat: false)
        if !mCat.rows.isEmpty { cats.append(mCat) }
        let rCat = buildCategory(.recovery, values: recoveryByUser, vitalityFormat: false)
        if !rCat.rows.isEmpty { cats.append(rCat) }

        if cats.isEmpty {
            cats = fallbackSyntheticCategories(active: active)
        }

        let season = makeSeasonInfo(weekEndKey: weekEndKey, referenceNow: referenceNow)
        return ChampionsData(season: season, categories: cats, members: membersChampion, isLive: isLiveWeekdayUTC(referenceNow))
    }

    private static func metaIntFromMembers(_ fm: FamilyMemberScore) -> Int? {
        fm.hasScore ? fm.currentScore : nil
    }

    private static func fallbackSyntheticCategories(active: [FamilyMemberScore]) -> [ChampionCategory] {
        let ids = active.compactMap { $0.userId?.lowercased() }
        guard ids.count >= 2 else { return [] }
        func rows(values: [String: Int], vitalityStyle: Bool) -> [CategoryMemberRow] {
            let sorted = ids.sorted { (values[$0] ?? 0) > (values[$1] ?? 0) }
            guard let top = sorted.first, let leaderV = values[top] else { return [] }
            return sorted.enumerated().map { idx, id in
                let v = values[id] ?? 0
                let isLeader = idx == 0
                let close = !isLeader && Double(v) >= Double(leaderV) * closeFraction
                let st: MemberStatus = isLeader ? .leading : (close ? .close : .trailing)
                let disp = vitalityStyle ? "+\(v)" : "\(v)"
                return CategoryMemberRow(id: id, status: st, displayValue: disp)
            }
        }
        var mapV: [String: Int] = [:]
        var v = 88
        for id in ids { mapV[id] = v; v -= 4 }
        let c1 = ChampionCategory(id: .vitality, rows: rows(values: mapV, vitalityStyle: true))
        var mapS: [String: Int] = [:]
        v = 82
        for id in ids { mapS[id] = v; v -= 3 }
        let c2 = ChampionCategory(id: .sleep, rows: rows(values: mapS, vitalityStyle: false))
        var mapM: [String: Int] = [:]
        v = 79
        for id in ids { mapM[id] = v; v -= 3 }
        let c3 = ChampionCategory(id: .movement, rows: rows(values: mapM, vitalityStyle: false))
        var mapR: [String: Int] = [:]
        v = 76
        for id in ids { mapR[id] = v; v -= 2 }
        let c4 = ChampionCategory(id: .recovery, rows: rows(values: mapR, vitalityStyle: false))
        return [c1, c2, c3, c4]
    }

    // MARK: - Season / live

    private static func utcCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    static func isLiveWeekdayUTC(_ date: Date) -> Bool {
        let wd = utcCalendar().component(.weekday, from: date)
        return wd != 1
    }

    /// `totalPoints` proxy: sum of `total` pillar across all fetched rows for the user (same window as badge RPC).
    private static func totalPointsProxy(userId: String, rows: [BadgeEngine.ScoreRow]) -> Int {
        let uid = userId.lowercased()
        let sum = rows
            .filter { $0.userId.lowercased() == uid }
            .compactMap { $0.total }
            .reduce(0, +)
        return min(20_000, max(0, sum))
    }

    private static func makeSeasonInfo(weekEndKey: String, referenceNow: Date) -> SeasonInfo {
        let cal = utcCalendar()
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        let weekEnd = df.date(from: weekEndKey) ?? referenceNow
        let month = cal.component(.month, from: weekEnd)
        let year = cal.component(.year, from: weekEnd)
        let seasonLabel: String
        switch month {
        case 3...5: seasonLabel = "Spring \(year)"
        case 6...8: seasonLabel = "Summer \(year)"
        case 9...11: seasonLabel = "Fall \(year)"
        default: seasonLabel = "Winter \(year)"
        }
        let startOfYear = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? weekEnd
        let dayIndex = cal.dateComponents([.day], from: startOfYear, to: weekEnd).day ?? 0
        let weekNumber = min(13, max(1, dayIndex / 7 + 1))
        let totalWeeks = 13
        let wd = cal.component(.weekday, from: referenceNow)
        let daysRemaining: Int
        if wd == 1 { daysRemaining = 0 }
        else { daysRemaining = 8 - wd }
        return SeasonInfo(name: seasonLabel, weekNumber: weekNumber, totalWeeks: totalWeeks, daysRemaining: daysRemaining)
    }

    // MARK: - Ranking (mirrors BadgeEngine spirit)

    private static func avg(_ xs: [Int]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return Double(xs.reduce(0, +)) / Double(xs.count)
    }

    private static func robustAverage(_ xs: [Int]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let sorted = xs.sorted()
        if sorted.count >= 5 {
            let trimmed = Array(sorted.dropFirst().dropLast())
            guard !trimmed.isEmpty else { return avg(sorted) }
            return avg(trimmed)
        }
        return avg(sorted)
    }

    private static func eligibleValues(_ rows: [BadgeEngine.ScoreRow], getter get: (BadgeEngine.ScoreRow) -> Int?) -> [Int]? {
        let vals = rows.compactMap(get)
        return vals.count >= eligibilityMinDays ? vals : nil
    }

    private static func rankedRows(
        category: ChampionCategoryType,
        memberIds: [String],
        thisByUser: [String: [BadgeEngine.ScoreRow]],
        prevByUser: [String: [BadgeEngine.ScoreRow]]
    ) -> [CategoryMemberRow] {

        struct Scored {
            let id: String
            let sortKey: Double
            let display: String
            let eligible: Bool
        }

        var scored: [Scored] = []
        for uid in memberIds {
            let thisRows = thisByUser[uid] ?? []
            let prevRows = prevByUser[uid] ?? []
            switch category {
            case .vitality:
                guard let thisVals = eligibleValues(thisRows, getter: { $0.total }),
                      let aThis = robustAverage(thisVals),
                      let prevVals = eligibleValues(prevRows, getter: { $0.total }),
                      let aPrev = robustAverage(prevVals),
                      aPrev > 0, aThis > aPrev else {
                    scored.append(Scored(id: uid, sortKey: -1, display: "—", eligible: false))
                    continue
                }
                let delta = aThis - aPrev
                let percent = (delta / aPrev) * 100.0
                guard delta >= BadgeEngine.Fairness.weeklyMinAbsoluteDelta,
                      percent >= BadgeEngine.Fairness.weeklyMinPercentDelta else {
                    scored.append(Scored(id: uid, sortKey: -1, display: "—", eligible: false))
                    continue
                }
                let disp = "+\(Int(percent.rounded()))"
                scored.append(Scored(id: uid, sortKey: percent, display: disp, eligible: true))
            case .sleep, .movement, .recovery:
                let getter: (BadgeEngine.ScoreRow) -> Int? = {
                    switch category {
                    case .sleep: return $0.sleep
                    case .movement: return $0.movement
                    case .recovery: return $0.stress
                    default: return nil
                    }
                }
                guard let thisVals = eligibleValues(thisRows, getter: getter),
                      let aThis = robustAverage(thisVals) else {
                    scored.append(Scored(id: uid, sortKey: -1, display: "—", eligible: false))
                    continue
                }
                let disp = "\(Int(aThis.rounded()))"
                scored.append(Scored(id: uid, sortKey: aThis, display: disp, eligible: true))
            }
        }

        let eligibleRanked = scored.filter { $0.eligible }.sorted { $0.sortKey > $1.sortKey }
        let ineligible = scored.filter { !$0.eligible }

        guard let leaderScore = eligibleRanked.first?.sortKey else {
            return []
        }

        var rows: [CategoryMemberRow] = []
        for (idx, s) in eligibleRanked.enumerated() {
            let isLeader = idx == 0
            let close = !isLeader && s.sortKey >= leaderScore * closeFraction
            let status: MemberStatus = isLeader ? .leading : (close ? .close : .trailing)
            rows.append(CategoryMemberRow(id: s.id, status: status, displayValue: s.display))
        }
        for s in ineligible {
            rows.append(CategoryMemberRow(id: s.id, status: .trailing, displayValue: "—"))
        }
        return rows
    }
}
