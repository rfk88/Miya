import Foundation

enum AlertRelevanceState: String, Codable, Equatable {
    case currentConcern
    case recovered
    case staleData
    case missingCurrentData
}

enum DashboardDataRelevance {
    /// A current pillar score at/above this value should no longer produce warning-style UI.
    private static let recoveredScoreThreshold = 65
    /// Attention alerts get a slightly wider window, but still disappear once the pillar is good.
    private static let attentionConcernThreshold = 65
    /// Watch alerts should only feel like warnings when the current pillar is clearly struggling.
    private static let watchConcernThreshold = 50

    static func currentPillarScore(
        memberUserId: String?,
        pillar: VitalityPillar,
        factors: [VitalityFactor]
    ) -> FamilyMemberScore? {
        guard let normalizedUserId = memberUserId?.lowercased(), !normalizedUserId.isEmpty else {
            return nil
        }

        guard let factor = factors.first(where: { $0.name == factorName(for: pillar) }) else {
            return nil
        }

        return factor.memberScores.first {
            $0.userId?.lowercased() == normalizedUserId
        }
    }

    static func shouldShowAlert(
        _ item: FamilyNotificationItem,
        factors: [VitalityFactor],
        now: Date = Date()
    ) -> Bool {
        relevanceState(for: item, factors: factors, now: now) == .currentConcern
    }

    static func relevanceState(
        for item: FamilyNotificationItem,
        factors: [VitalityFactor],
        now: Date = Date()
    ) -> AlertRelevanceState {
        relevanceState(
            memberUserId: item.memberUserId,
            pillar: item.pillar,
            severity: severity(for: item),
            factors: factors
        )
    }

    static func shouldShowInsight(
        _ insight: TrendInsight,
        factors: [VitalityFactor],
        now: Date = Date()
    ) -> Bool {
        relevanceState(for: insight, factors: factors, now: now) == .currentConcern
    }

    static func relevanceState(
        for insight: TrendInsight,
        factors: [VitalityFactor],
        now: Date = Date()
    ) -> AlertRelevanceState {
        switch insight.severity {
        case .celebrate:
            guard let score = currentPillarScore(
                memberUserId: insight.memberUserId,
                pillar: insight.pillar,
                factors: factors
            ) else {
                return .missingCurrentData
            }
            guard score.hasScore else { return .missingCurrentData }
            guard !score.isStale else { return .staleData }
            return score.currentScore >= recoveredScoreThreshold ? .currentConcern : .recovered

        case .attention, .watch:
            return relevanceState(
                memberUserId: insight.memberUserId,
                pillar: insight.pillar,
                severity: insight.severity,
                factors: factors
            )
        }
    }

    static func factorName(for pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep:
            return "Sleep"
        case .movement:
            return "Activity"
        case .stress:
            return "Recovery"
        }
    }

    private static func relevanceState(
        memberUserId: String?,
        pillar: VitalityPillar,
        severity: TrendSeverity?,
        factors: [VitalityFactor]
    ) -> AlertRelevanceState {
        guard let score = currentPillarScore(
            memberUserId: memberUserId,
            pillar: pillar,
            factors: factors
        ) else {
            return .missingCurrentData
        }

        guard score.hasScore else { return .missingCurrentData }
        guard !score.isStale else { return .staleData }

        let threshold = severity == .attention ? attentionConcernThreshold : watchConcernThreshold
        return score.currentScore < threshold ? .currentConcern : .recovered
    }

    private static func severity(for item: FamilyNotificationItem) -> TrendSeverity? {
        switch item.kind {
        case .trend(let insight):
            return insight.severity
        case .fallback:
            return nil
        }
    }
}
