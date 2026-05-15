import SwiftUI

struct ChampionsChangeMoment: Identifiable {
    let id: String
    let iconName: String
    let title: String
    let message: String
    let accent: Color
}

enum ChampionsChangeMomentStore {
    private static let snapshotKey = "miya.champions.lastSnapshotSummary"
    private static let shownKeyPrefix = "miya.champions.shownMoments."

    static func consumeMomentIfNeeded(
        current data: ChampionsData,
        currentUserId: String?,
        vitalityFactors: [VitalityFactor]
    ) -> ChampionsChangeMoment? {
        let current = ChampionsSnapshotSummary(data: data)
        defer { saveSnapshot(current) }

        guard let previous = loadSnapshot(),
              previous.weekKey == current.weekKey
        else {
            return nil
        }

        guard let moment = ChampionsChangeMomentDetector.detect(
            previous: previous,
            current: current,
            currentUserId: currentUserId?.lowercased(),
            vitalityFactors: vitalityFactors
        ) else {
            return nil
        }

        guard !hasShown(momentId: moment.id, weekKey: current.weekKey) else {
            return nil
        }
        markShown(momentId: moment.id, weekKey: current.weekKey)
        return moment
    }

    private static func loadSnapshot() -> ChampionsSnapshotSummary? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(ChampionsSnapshotSummary.self, from: data)
    }

    private static func saveSnapshot(_ snapshot: ChampionsSnapshotSummary) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }

    private static func hasShown(momentId: String, weekKey: String) -> Bool {
        shownSet(weekKey: weekKey).contains(momentId)
    }

    private static func markShown(momentId: String, weekKey: String) {
        var shown = shownSet(weekKey: weekKey)
        shown.insert(momentId)
        UserDefaults.standard.set(Array(shown), forKey: shownKeyPrefix + weekKey)
    }

    private static func shownSet(weekKey: String) -> Set<String> {
        let values = UserDefaults.standard.stringArray(forKey: shownKeyPrefix + weekKey) ?? []
        return Set(values)
    }
}

private struct ChampionsSnapshotSummary: Codable {
    struct Member: Codable {
        let id: String
        let name: String
        let points: Int
    }

    struct Category: Codable {
        let id: String
        let leaderId: String
        let leaderName: String
        let displayValue: String
    }

    let weekKey: String
    let members: [Member]
    let categories: [Category]

    init(data: ChampionsData) {
        weekKey = "\(data.season.name)-\(data.season.weekNumber)"
        members = data.membersSortedByPoints.map {
            Member(id: $0.id.lowercased(), name: $0.name, points: $0.totalPoints)
        }
        categories = data.categories.compactMap { category in
            guard let leader = category.leader,
                  let member = data.member(for: leader.id)
            else { return nil }
            return Category(
                id: category.id.rawValue,
                leaderId: leader.id.lowercased(),
                leaderName: member.name,
                displayValue: leader.displayValue
            )
        }
    }

    var rankByMemberId: [String: Int] {
        Dictionary(uniqueKeysWithValues: members.enumerated().map { ($0.element.id, $0.offset) })
    }

    func memberName(for id: String) -> String {
        members.first { $0.id == id.lowercased() }?.name ?? "A family member"
    }

    func category(for id: String) -> Category? {
        categories.first { $0.id == id }
    }
}

private enum ChampionsChangeMomentDetector {
    private struct Candidate {
        let priority: Int
        let moment: ChampionsChangeMoment
    }

    static func detect(
        previous: ChampionsSnapshotSummary,
        current: ChampionsSnapshotSummary,
        currentUserId: String?,
        vitalityFactors: [VitalityFactor]
    ) -> ChampionsChangeMoment? {
        var candidates: [Candidate] = []
        let previousRanks = previous.rankByMemberId
        let currentRanks = current.rankByMemberId

        if let userId = currentUserId,
           let oldRank = previousRanks[userId],
           let newRank = currentRanks[userId],
           newRank < oldRank {
            if newRank == 0 {
                candidates.append(
                    Candidate(
                        priority: 0,
                        moment: makeMoment(
                            id: "total-first-\(userId)",
                            category: .vitality,
                            title: "You’re top of Champions",
                            message: "You’ve moved into first overall. Brilliant work."
                        )
                    )
                )
            }

            if let overtakenId = current.members.dropFirst(newRank + 1).first(where: { member in
                guard let oldOtherRank = previousRanks[member.id] else { return false }
                return oldOtherRank < oldRank
            })?.id {
                candidates.append(
                    Candidate(
                        priority: 1,
                        moment: makeMoment(
                            id: "total-overtook-\(userId)-\(overtakenId)",
                            category: .vitality,
                            title: "Champions update",
                            message: "You’ve just overtaken \(current.memberName(for: overtakenId)) in Champions. Brilliant work."
                        )
                    )
                )
            }
        }

        if let userId = currentUserId,
           let oldRank = previousRanks[userId],
           let newRank = currentRanks[userId],
           newRank > oldRank,
           newRank > 0 {
            let overtaker = current.members[newRank - 1]
            if let oldOtherRank = previousRanks[overtaker.id], oldOtherRank > oldRank {
                candidates.append(
                    Candidate(
                        priority: 2,
                        moment: makeMoment(
                            id: "total-overtaken-\(overtaker.id)-\(userId)",
                            category: .vitality,
                            title: "Champions update",
                            message: "\(firstName(overtaker.name)) has just edged ahead in Champions. \(advice(for: .vitality, factors: vitalityFactors))"
                        )
                    )
                )
            }
        }

        for currentCategory in current.categories {
            guard let previousCategory = previous.category(for: currentCategory.id),
                  previousCategory.leaderId != currentCategory.leaderId,
                  let type = ChampionCategoryType(rawValue: currentCategory.id)
            else { continue }

            let priority: Int
            let message: String
            if currentCategory.leaderId == currentUserId {
                priority = 0
                message = "You’re now leading \(type.displayName). Brilliant work."
            } else if previousCategory.leaderId == currentUserId {
                priority = 2
                message = "\(firstName(currentCategory.leaderName)) has just edged ahead in \(type.displayName). \(advice(for: type, factors: vitalityFactors))"
            } else {
                priority = 3
                message = "\(firstName(currentCategory.leaderName)) has moved into first for \(type.displayName)."
            }

            candidates.append(
                Candidate(
                    priority: priority,
                    moment: makeMoment(
                        id: "category-\(type.rawValue)-\(previousCategory.leaderId)-\(currentCategory.leaderId)",
                        category: type,
                        title: "Champions changed",
                        message: message
                    )
                )
            )
        }

        return candidates.sorted { $0.priority < $1.priority }.first?.moment
    }

    private static func makeMoment(
        id: String,
        category: ChampionCategoryType,
        title: String,
        message: String
    ) -> ChampionsChangeMoment {
        ChampionsChangeMoment(
            id: id,
            iconName: category.icon,
            title: title,
            message: message,
            accent: category.accentColor
        )
    }

    private static func firstName(_ name: String) -> String {
        name.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? name
    }

    private static func advice(for category: ChampionCategoryType, factors: [VitalityFactor]) -> String {
        switch category {
        case .sleep:
            return "Protect your sleep window tonight: set a wind-down time and keep your wake-up time steady."
        case .movement:
            return "Add a 10-minute walk or choose one active family moment today to close the gap."
        case .recovery:
            return "Aim for a lighter last hour tonight: dim lights, no hard workout, and a steady bedtime."
        case .vitality:
            return vitalityAdvice(factors: factors)
        }
    }

    private static func vitalityAdvice(factors: [VitalityFactor]) -> String {
        guard let weakest = factors.min(by: { $0.percent < $1.percent }) else {
            return "Pick one small win today across sleep, movement, or recovery to close the gap."
        }

        let pillar = VitalityPillar.allCases.first {
            DashboardDataRelevance.factorName(for: $0) == weakest.name
        }

        switch pillar {
        case .sleep:
            return advice(for: .sleep, factors: factors)
        case .movement:
            return advice(for: .movement, factors: factors)
        case .stress:
            return advice(for: .recovery, factors: factors)
        case .none:
            return "Focus on \(weakest.name.lowercased()) today with one small, repeatable action."
        }
    }
}
