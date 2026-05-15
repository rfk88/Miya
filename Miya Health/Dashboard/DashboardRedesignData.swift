import Foundation
import SwiftUI

// MARK: - Score tier

/// Visual tier for a member's weekly vitality score.
/// Drives the pastel background + text colour on the new 38pt avatar strip
/// and the small alert-card avatar.
enum ScoreTier: Equatable {
    case good      // score >= 75
    case watch     // 55..<75
    case low       // < 55
    case noData    // no fresh score available

    var background: Color {
        switch self {
        case .good:   return Color(hex: "B8E4EF")
        case .watch:  return Color(hex: "FAE5C0")
        case .low:    return Color(hex: "F5C9C4")
        case .noData: return Color(hex: "F4F1ED")
        }
    }

    var foreground: Color {
        switch self {
        case .good:   return Color(hex: "0E7490")
        case .watch:  return Color(hex: "9A6B1A")
        case .low:    return Color(hex: "A0554B")
        case .noData: return Color(hex: "9CA3AF")
        }
    }
}

// MARK: - Consolidated alert (one per member)

/// One terracotta alert card per family member with 1+ active pattern alert
/// whose duration has reached >= 3 consecutive days. Derived from
/// `serverPatternAlerts` already loaded by the dashboard; introduces no new
/// fetches and no new persistence.
struct ConsolidatedMemberAlert: Identifiable, Equatable {
    let id: String                      // memberUserId (lower-cased) or fallback name key
    let memberUserId: String?
    let memberName: String
    let memberInitials: String
    let firstName: String
    let pillars: [VitalityPillar]       // de-duplicated, in pillar canonical order
    let maxDurationDays: Int            // largest patternDurationDays among grouped items
    let signalCount: Int                // distinct pillars surfaced for this member
    let representativeItemId: String    // id of the highest-duration FamilyNotificationItem

    static func == (lhs: ConsolidatedMemberAlert, rhs: ConsolidatedMemberAlert) -> Bool {
        lhs.id == rhs.id &&
        lhs.pillars == rhs.pillars &&
        lhs.maxDurationDays == rhs.maxDurationDays &&
        lhs.signalCount == rhs.signalCount &&
        lhs.representativeItemId == rhs.representativeItemId
    }
}

// MARK: - Suggested feed lanes

/// One row inside the new SUGGESTED card. Pure value type — no SwiftUI types
/// so the helpers can stay in the data extension.
struct SuggestedRow: Identifiable, Equatable {
    enum Lane: Equatable {
        case wins, checkIn, familyOps
    }

    enum Action: Equatable {
        /// Push the member's existing detail screen.
        case openMemberDetail(memberUserId: String?, memberName: String)
        /// Open Miya chat pre-loaded with member context (existing arloChatSheet).
        case openMiyaChat(memberUserId: String?, memberName: String)
        /// Push the existing wearable-setup flow.
        case openWearableSetup(memberUserId: String?, memberName: String)
        /// Push the existing guided setup review flow for this member record id.
        case openGuidedReview(memberRecordId: String, memberName: String)
    }

    let id: String
    let lane: Lane
    let memberUserId: String?           // nil for ops rows that have no member binding
    let text: String
    let action: Action
}

struct SuggestedFeed: Equatable {
    let lane1: [SuggestedRow]
    let lane2: [SuggestedRow]
    let lane3: [SuggestedRow]

    var isEmpty: Bool {
        lane1.isEmpty && lane2.isEmpty && lane3.isEmpty
    }

    var totalCount: Int {
        lane1.count + lane2.count + lane3.count
    }

    static let empty = SuggestedFeed(lane1: [], lane2: [], lane3: [])
}

// MARK: - Pillar display helpers

extension VitalityPillar {
    /// Marketing label used on the new dashboard: stress → "Recovery".
    var dashboardDisplayName: String {
        switch self {
        case .sleep:    return "Sleep"
        case .movement: return "Activity"
        case .stress:   return "Recovery"
        }
    }

    /// Dot colour for the pillar pills in the new Family Vitality hero card.
    var heroDotColor: Color {
        switch self {
        case .sleep:    return Color(hex: "C4B5D9")
        case .movement: return Color(hex: "7DD3C7")
        case .stress:   return Color(hex: "9BB8D4") // calm cool blue — not peach/orange
        }
    }

    /// Canonical ordering used when joining pillar names in alert subtitles.
    var canonicalOrder: Int {
        switch self {
        case .sleep:    return 0
        case .movement: return 1
        case .stress:   return 2
        }
    }
}

// MARK: - Pillar state band

/// Status band used in the hero card's glass pillar pills.
/// Mirrors the existing PillarTile.statusLabel(for:) thresholds so nothing
/// drifts visually if the original tile changes.
enum PillarStateBand {
    case excellent, good, stable, drifting, urgent, noData, stale

    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good:      return "Good"
        case .stable:    return "Stable"
        case .drifting:  return "Drifting"
        case .urgent:    return "Urgent"
        case .noData:    return "No data yet"
        case .stale:     return "Data out of date"
        }
    }

    static func band(for factor: VitalityFactor) -> PillarStateBand {
        let scores = factor.memberScores
        if !scores.isEmpty {
            let allNoScore = scores.allSatisfy { !$0.hasScore }
            if allNoScore { return .noData }
            let allStale = scores.allSatisfy { $0.isStale || !$0.hasScore }
            if allStale { return .stale }
        }
        let clamped = max(0, min(factor.percent, 100))
        switch clamped {
        case 80...100: return .excellent
        case 65..<80:  return .good
        case 50..<65:  return .stable
        case 35..<50:  return .drifting
        default:       return .urgent
        }
    }
}

// MARK: - DashboardView helpers

extension DashboardView {

    /// Pastel-tier mapping for the weekly vitality score (0–100).
    /// `nil` (or a member with no fresh score) maps to `.noData`.
    func scoreTier(for member: FamilyMemberScore) -> ScoreTier {
        guard member.hasScore else { return .noData }
        if member.isStale { return .noData }
        return Self.scoreTier(forScore: member.currentScore)
    }

    /// Same mapping for cases where we only have a raw integer score.
    static func scoreTier(forScore score: Int?) -> ScoreTier {
        guard let s = score else { return .noData }
        if s >= 75 { return .good }
        if s >= 55 { return .watch }
        if s >= 0  { return .low }
        return .noData
    }

    /// True when any of `serverPatternAlerts` is tied to this member.
    /// Drives the amber alert dot on the avatar strip and the bell-area
    /// "are there alerts at all" determination.
    func hasActiveAlerts(memberUserId: String?) -> Bool {
        guard let id = memberUserId?.lowercased(), !id.isEmpty else { return false }
        return relevantServerPatternAlerts.contains { $0.memberUserId?.lowercased() == id }
    }

    var relevantServerPatternAlerts: [FamilyNotificationItem] {
        serverPatternAlerts.filter {
            DashboardDataRelevance.shouldShowAlert($0, factors: vitalityFactors)
        }
    }

    /// All member ids (lowercased) currently flagged as having an active alert.
    /// Useful for the Suggested cross-lane rule: Wins rows cannot reference
    /// alert members.
    var alertMemberIdSet: Set<String> {
        Set(
            relevantServerPatternAlerts.compactMap { $0.memberUserId?.lowercased() }
        )
    }

    /// Build the terracotta-bordered "Rami — N signals, N days" cards from
    /// the existing `serverPatternAlerts` array. Only members whose longest
    /// alert has been active for >= 3 days are surfaced; ordered by duration
    /// descending; dismissed members are filtered out by the view layer.
    func consolidatedAlerts() -> [ConsolidatedMemberAlert] {
        let relevantAlerts = relevantServerPatternAlerts
        guard !relevantAlerts.isEmpty else { return [] }

        // Group items by member id (fall back to memberName for items without ids).
        var grouped: [String: [FamilyNotificationItem]] = [:]
        var order: [String] = []
        for item in relevantAlerts {
            let key = (item.memberUserId?.lowercased() ?? item.memberName.lowercased())
            if grouped[key] == nil {
                grouped[key] = []
                order.append(key)
            }
            grouped[key]?.append(item)
        }

        let results: [ConsolidatedMemberAlert] = order.compactMap { key in
            guard let items = grouped[key], !items.isEmpty else { return nil }

            // Longest active duration across this member's items.
            let durations = items.compactMap { $0.patternDurationDays }
            let maxDuration = durations.max() ?? 0
            guard maxDuration >= 3 else { return nil }

            // De-duplicated, canonical-ordered pillar list.
            var seenPillars: Set<VitalityPillar> = []
            var pillars: [VitalityPillar] = []
            for item in items where !seenPillars.contains(item.pillar) {
                seenPillars.insert(item.pillar)
                pillars.append(item.pillar)
            }
            pillars.sort { $0.canonicalOrder < $1.canonicalOrder }

            // Representative item = the one whose duration matches the max
            // (falls back to the first item for the member).
            let representative = items.first(where: { ($0.patternDurationDays ?? 0) == maxDuration }) ?? items[0]

            let memberName = representative.memberName
            let firstName = memberName
                .split(separator: " ", omittingEmptySubsequences: true)
                .first
                .map(String.init) ?? memberName

            return ConsolidatedMemberAlert(
                id: key,
                memberUserId: representative.memberUserId,
                memberName: memberName,
                memberInitials: representative.memberInitials,
                firstName: firstName,
                pillars: pillars,
                maxDurationDays: maxDuration,
                signalCount: pillars.count,
                representativeItemId: representative.id
            )
        }

        return results.sorted { $0.maxDurationDays > $1.maxDurationDays }
    }

    // MARK: Suggested feed

    /// Compose the three-lane SUGGESTED card content from existing state.
    /// Cross-lane rules (mirrors the plan):
    ///   1. Reject any row whose copy starts with "Review " or "View ".
    ///   2. Lane 1 rows cannot reference alert members.
    ///   3. Members already claimed by an earlier lane cannot appear in a later one.
    ///   4. Lane 1 ≤ 2, Lane 2 ≤ 2, Lane 3 ≤ 1, global total ≤ 4 in lane order.
    ///   5. If serverPatternAlerts.isEmpty && trendInsights.isEmpty,
    ///      Lane 2 may only emit helpCards.
    ///   6. helpCards and FamilyRecommendationEngine rows for the same
    ///      member cannot both appear in the same session.
    func suggestedFeed() -> SuggestedFeed {
        var claimedMemberIds: Set<String> = []
        let relevantAlerts = relevantServerPatternAlerts
        let relevantTrendInsights = trendInsights.filter {
            DashboardDataRelevance.shouldShowInsight($0, factors: vitalityFactors)
        }
        let alertIds = alertMemberIdSet

        // ----- Lane 1: Wins -----
        var lane1: [SuggestedRow] = []

        // Source 1: celebrate trend insights for non-alert members.
        for insight in relevantTrendInsights where insight.severity == .celebrate {
            let memberKey = insight.memberUserId.lowercased()
            if alertIds.contains(memberKey) { continue }
            if claimedMemberIds.contains(memberKey) { continue }
            let firstName = insight.memberName
                .split(separator: " ", omittingEmptySubsequences: true)
                .first
                .map(String.init) ?? insight.memberName
            let pillarLabel = insight.pillar.dashboardDisplayName.lowercased()
            let text: String
            if MemberProfileOwnVoice.isCurrentUser(memberUserId: insight.memberUserId, authUserId: currentUserIdString) {
                text = "Your \(pillarLabel) is well above your usual this week"
            } else {
                text = "\(firstName)'s \(pillarLabel) is well above their usual this week"
            }
            if rejectsNavigationCopy(text) { continue }
            lane1.append(
                SuggestedRow(
                    id: "lane1-celebrate-\(insight.id.uuidString)",
                    lane: .wins,
                    memberUserId: insight.memberUserId,
                    text: text,
                    action: .openMemberDetail(memberUserId: insight.memberUserId, memberName: insight.memberName)
                )
            )
            claimedMemberIds.insert(memberKey)
            if lane1.count >= 2 { break }
        }

        // Source 2: snapshot.celebrateMembers for any non-alert member not already claimed.
        if lane1.count < 2, let snapshot = familySnapshot {
            for member in snapshot.celebrateMembers {
                guard let uid = member.memberUserId?.lowercased(), !uid.isEmpty else { continue }
                if alertIds.contains(uid) { continue }
                if claimedMemberIds.contains(uid) { continue }
                let firstName = member.memberName
                    .split(separator: " ", omittingEmptySubsequences: true)
                    .first
                    .map(String.init) ?? member.memberName
                let text: String
                if MemberProfileOwnVoice.isCurrentUser(memberUserId: member.memberUserId, authUserId: currentUserIdString) {
                    text = "You're close to your vitality target this week"
                } else {
                    text = "\(firstName) is close to their vitality target this week"
                }
                if rejectsNavigationCopy(text) { continue }
                lane1.append(
                    SuggestedRow(
                        id: "lane1-celebrate-snapshot-\(member.id.uuidString)",
                        lane: .wins,
                        memberUserId: member.memberUserId,
                        text: text,
                        action: .openMemberDetail(memberUserId: member.memberUserId, memberName: member.memberName)
                    )
                )
                claimedMemberIds.insert(uid)
                if lane1.count >= 2 { break }
            }
        }

        // TODO: dashboard-redesign: ChampionsData exposes no "days held leader"
        // duration, so Lane 1 Source 3 (current Champions leaders held 3+ days)
        // is intentionally skipped here. Re-enable once that data exists.

        // ----- Lane 2: Check in -----
        var lane2: [SuggestedRow] = []
        let coverageEmpty = relevantAlerts.isEmpty && relevantTrendInsights.isEmpty
        let recommendationRows: [FamilyRecommendationRow] = familySnapshot.map { snapshot in
            FamilyRecommendationEngine.build(
                snapshot: snapshot,
                trendInsights: relevantTrendInsights,
                coverage: trendCoverage
            )
        } ?? []
        var recommendationClaimedMemberKeys: Set<String> = []

        // Source 1: due check-ins from server pattern alerts in monitoring state.
        if !coverageEmpty {
            let today = Calendar.current.startOfDay(for: Date())
            for item in relevantAlerts {
                guard item.careState == .monitoring,
                      let due = item.followUpDueDate,
                      Calendar.current.startOfDay(for: due) <= today,
                      let uid = item.memberUserId?.lowercased(), !uid.isEmpty
                else { continue }
                if claimedMemberIds.contains(uid) { continue }
                let firstName = item.memberName
                    .split(separator: " ", omittingEmptySubsequences: true)
                    .first
                    .map(String.init) ?? item.memberName
                let text = "You said you'd check in with \(firstName)"
                if rejectsNavigationCopy(text) { continue }
                // TODO: dashboard-redesign: pre-filled Messages compose for this row
                // is not implemented — for now we push the member detail view.
                lane2.append(
                    SuggestedRow(
                        id: "lane2-due-\(item.id)",
                        lane: .checkIn,
                        memberUserId: item.memberUserId,
                        text: text,
                        action: .openMemberDetail(memberUserId: item.memberUserId, memberName: item.memberName)
                    )
                )
                claimedMemberIds.insert(uid)
                if lane2.count >= 2 { break }
            }
        }

        // Source 2: FamilyRecommendationEngine action lines (skipped if coverage empty).
        if !coverageEmpty && lane2.count < 2 {
            for row in recommendationRows {
                if lane2.count >= 2 { break }
                let memberKey = row.memberUserId?.lowercased() ?? "engine-\(row.id.uuidString)"
                if let uid = row.memberUserId?.lowercased(), claimedMemberIds.contains(uid) { continue }
                if rejectsNavigationCopy(row.text) { continue }
                lane2.append(
                    SuggestedRow(
                        id: "lane2-engine-\(row.id.uuidString)",
                        lane: .checkIn,
                        memberUserId: row.memberUserId,
                        text: row.text,
                        action: .openMemberDetail(memberUserId: row.memberUserId, memberName: memberDisplayName(forUserId: row.memberUserId))
                    )
                )
                recommendationClaimedMemberKeys.insert(memberKey)
                if let uid = row.memberUserId?.lowercased() {
                    claimedMemberIds.insert(uid)
                }
            }
        }

        // Source 3: helpCards. Always eligible. Suppressed for any member whose
        // recommendation line was already emitted in this composition.
        if lane2.count < 2, let snapshot = familySnapshot {
            for card in snapshot.helpCards {
                if lane2.count >= 2 { break }
                let memberKey = card.memberId.lowercased()
                if claimedMemberIds.contains(memberKey) { continue }
                if recommendationClaimedMemberKeys.contains(memberKey) { continue }
                if rejectsNavigationCopy(card.title) { continue }
                lane2.append(
                    SuggestedRow(
                        id: "lane2-help-\(card.id.uuidString)",
                        lane: .checkIn,
                        memberUserId: card.memberId,
                        text: card.title,
                        action: .openMiyaChat(memberUserId: card.memberId, memberName: card.memberName)
                    )
                )
                claimedMemberIds.insert(memberKey)
            }
        }

        // ----- Lane 3: Family ops (max 1) -----
        var lane3: [SuggestedRow] = []
        let usedCount = lane1.count + lane2.count
        if usedCount < 4 {
            // Source 1: missing wearable >= 48h.
            // `MissingWearableNotification.daysStale` is only ever 3 or 7 in the
            // current detector, so every entry already exceeds the 48h threshold.
            if let missing = missingWearableNotifications.first(where: { $0.daysStale >= 2 }) {
                if let uid = missing.memberUserId?.lowercased(), claimedMemberIds.contains(uid) {
                    // Skip — that member is already claimed earlier.
                } else {
                    let firstName = missing.memberName
                        .split(separator: " ", omittingEmptySubsequences: true)
                        .first
                        .map(String.init) ?? missing.memberName
                    let text = "Connect \(firstName)'s wearable to see their score"
                    if !rejectsNavigationCopy(text) {
                        lane3.append(
                            SuggestedRow(
                                id: "lane3-wearable-\(missing.id)",
                                lane: .familyOps,
                                memberUserId: missing.memberUserId,
                                text: text,
                                action: .openWearableSetup(memberUserId: missing.memberUserId, memberName: missing.memberName)
                            )
                        )
                        if let uid = missing.memberUserId?.lowercased() {
                            claimedMemberIds.insert(uid)
                        }
                    }
                }
            }

            // Source 2 (formerly "ending challenge") is intentionally not emitted.
            // The dashboard already shows `MyChallengeView` in-scroll for the
            // active personal challenge; emitting a Lane 3 row would duplicate it.

            // Source 3 (now the second Lane 3 source): guided setup pending review.
            // TODO: dashboard-redesign: no dedicated fetcher returns
            // `guidedSetupStatus == "data_complete_pending_review"` — we derive
            // it client-side from `familyMemberRecords`.
            if lane3.isEmpty {
                if let pending = familyMemberRecords.first(where: { $0.guidedSetupStatus == "data_complete_pending_review" }) {
                    let memberKey = (pending.userId?.uuidString.lowercased() ?? pending.id.uuidString.lowercased())
                    if !claimedMemberIds.contains(memberKey) {
                        let text = "\(pending.firstName)'s health profile is waiting for your review"
                        if !rejectsNavigationCopy(text) {
                            lane3.append(
                                SuggestedRow(
                                    id: "lane3-review-\(pending.id.uuidString)",
                                    lane: .familyOps,
                                    memberUserId: pending.userId?.uuidString,
                                    text: text,
                                    action: .openGuidedReview(memberRecordId: pending.id.uuidString, memberName: pending.firstName)
                                )
                            )
                        }
                    }
                }
            }
        }

        // Final global cap of 4 in lane order (Lane 1 → Lane 2 → Lane 3).
        let combined = Array((lane1 + lane2 + lane3).prefix(4))
        let l1 = combined.filter { $0.lane == .wins }
        let l2 = combined.filter { $0.lane == .checkIn }
        let l3 = combined.filter { $0.lane == .familyOps }
        return SuggestedFeed(lane1: l1, lane2: l2, lane3: l3)
    }

    func arloDashboardContext() -> ArloChatAPI.DashboardContext {
        let freshMembers = familyMembers.filter { $0.hasScore && !$0.isStale }
        let staleMembers = familyMembers.filter { $0.isStale }
        let band = arloVitalityBand(for: familyVitalityScore)
        let clampedFamilyScore = familyVitalityScore.map { max(0, min($0, 100)) }

        let pillars = vitalityFactors.map { factor in
            let scores = factor.memberScores
            return ArloChatAPI.DashboardContext.Pillar(
                name: factor.name,
                score: max(0, min(factor.percent, 100)),
                label: PillarStateBand.band(for: factor).label,
                freshMemberCount: scores.filter { $0.hasScore && !$0.isStale }.count,
                staleMemberCount: scores.filter { $0.isStale }.count,
                missingMemberCount: scores.filter { !$0.hasScore }.count
            )
        }

        let activeAlerts = relevantServerPatternAlerts.prefix(5).map { item in
            ArloChatAPI.DashboardContext.ActiveAlert(
                memberName: item.memberName,
                pillar: item.pillar.dashboardDisplayName,
                durationDays: item.patternDurationDays,
                relevanceState: DashboardDataRelevance
                    .relevanceState(for: item, factors: vitalityFactors)
                    .rawValue
            )
        }

        let freshnessSummary: String
        if familyMembers.isEmpty {
            freshnessSummary = "No family member score rows are currently loaded."
        } else if staleMembers.isEmpty {
            freshnessSummary = "\(freshMembers.count) of \(familyMembers.count) family members have fresh score data."
        } else {
            freshnessSummary = "\(freshMembers.count) of \(familyMembers.count) family members have fresh score data; \(staleMembers.count) member score rows are stale."
        }

        return ArloChatAPI.DashboardContext(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            familyScore: clampedFamilyScore,
            familyScoreLabel: band.sentence,
            memberCount: familyMembers.count,
            freshMemberCount: freshMembers.count,
            staleMemberCount: staleMembers.count,
            activeAlerts: activeAlerts,
            pillars: pillars,
            dataFreshnessSummary: freshnessSummary
        )
    }

    // MARK: Internal helpers

    private func rejectsNavigationCopy(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("Review ") || trimmed.hasPrefix("View ")
    }

    private func memberDisplayName(forUserId userId: String?) -> String {
        guard let uid = userId?.lowercased() else { return "this member" }
        if let match = familyMembers.first(where: { $0.userId?.lowercased() == uid }) {
            return match.name
        }
        return "this member"
    }
}
