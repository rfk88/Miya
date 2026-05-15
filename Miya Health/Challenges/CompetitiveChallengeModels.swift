//
//  CompetitiveChallengeModels.swift
//  Miya Health
//
//  Domain model for Phase B competitive challenges (head-to-head and family brawl).
//  Mon–Sun, per-participant local timezone, mutual accept.
//

import Foundation
import SwiftUI

// MARK: - Focus

/// What the competitive challenge measures.
///
/// Display labels live on the case (`displayName`); database keys come from `dbKey`
/// because the storage layer (`big_competitive_challenges.focus`) reuses the legacy
/// pillar names (`sleep` / `movement` / `stress`) plus `steps`.
enum ChallengeFocus: String, CaseIterable, Codable, Hashable {
    case sleep
    case activity
    case recovery
    case steps

    /// Camera-ready label for UI.
    var displayName: String {
        switch self {
        case .sleep:    return "Sleep"
        case .activity: return "Activity"
        case .recovery: return "Recovery"
        case .steps:    return "Steps"
        }
    }

    /// Wire / database key. **Do not change**: shared with the DB CHECK constraint
    /// on `big_competitive_challenges.focus` and the daily evaluator.
    var dbKey: String {
        switch self {
        case .sleep:    return "sleep"
        case .activity: return "movement"
        case .recovery: return "stress"
        case .steps:    return "steps"
        }
    }

    /// SF Symbol used in the focus card and pillar chips.
    var sfSymbol: String {
        switch self {
        case .sleep:    return "moon.fill"
        case .activity: return "bolt.fill"
        case .recovery: return "heart.fill"
        case .steps:    return "figure.walk"
        }
    }

    /// Miya accent color for this lane (light-theme).
    var accent: Color {
        switch self {
        case .sleep:    return CompetitiveChallengeTheme.focusSleep
        case .activity: return CompetitiveChallengeTheme.focusActivity
        case .recovery: return CompetitiveChallengeTheme.focusRecovery
        case .steps:    return CompetitiveChallengeTheme.focusSteps
        }
    }

    /// Short scoring rule shown in the composer info strip and pending summary.
    var scoringRule: String {
        switch self {
        case .sleep, .activity, .recovery:
            return "Highest 7-day average wins"
        case .steps:
            return "Highest total Mon–Sun wins"
        }
    }

    /// `true` when the metric is a cumulative weekly total (steps) rather than an average (pillars).
    var isCumulative: Bool { self == .steps }

    /// Reverse lookup from a stored DB key. Returns nil for unknown values so callers can decide policy.
    init?(dbKey: String) {
        switch dbKey {
        case "sleep":    self = .sleep
        case "movement": self = .activity
        case "stress":   self = .recovery
        case "steps":    self = .steps
        default:         return nil
        }
    }
}

// MARK: - Mode

/// Shape of the competition.
///
/// Mapped from participant count by `ChallengeMode.from(participantCount:)`. Always 2..6 once active
/// (server-enforced by `big_competitive_participants_enforce_caps` trigger).
enum ChallengeMode: String, Codable, Hashable {
    case headToHead = "head_to_head"
    case familyBrawl = "family_brawl"

    static func from(participantCount: Int) -> ChallengeMode {
        return participantCount > 2 ? .familyBrawl : .headToHead
    }

    var displayName: String {
        switch self {
        case .headToHead:  return "Head to head"
        case .familyBrawl: return "Family brawl"
        }
    }
}

// MARK: - Status

/// Status enum local to the iOS layer; maps to `big_competitive_challenges.status` text values.
enum CompetitiveChallengeStatus: String, Codable, Hashable {
    case pendingAccepts = "pending_accepts"
    case active
    case completed
    case cancelled

    /// Convenience for view filtering.
    var isOpen: Bool { self == .pendingAccepts || self == .active }
    var isClosed: Bool { self == .completed || self == .cancelled }
}

// MARK: - Participant

/// One competitor in a competitive challenge. `userId` is the canonical user UUID (lowercased).
struct CompetitiveChallengeParticipant: Identifiable, Hashable {
    let userId: String
    let displayName: String
    let initials: String
    let avatarTint: Color
    let inviteStatus: InviteStatus
    let acceptedAt: Date?

    /// Running aggregate at fetch time (pillar mean OR step total, depending on focus).
    var currentScore: Double

    /// Optional best single-day value used for tie-break display / decision.
    var bestSingleDay: Double?

    /// Mon..Sun. `nil` slots = no data that day. For pillars: each entry is a daily pillar score;
    /// for steps: each entry is daily step count.
    var dailyValues: [Double?]

    var id: String { userId }

    enum InviteStatus: String, Codable, Hashable {
        case pending
        case accepted
        case declined
    }

    /// True if this participant is the current authenticated user. Set at view-model construction time.
    var isCurrentUser: Bool

    static func placeholder(userId: String, displayName: String, isCurrentUser: Bool) -> Self {
        return .init(
            userId: userId,
            displayName: displayName,
            initials: Self.initials(from: displayName),
            avatarTint: isCurrentUser ? CompetitiveChallengeTheme.youAccent : CompetitiveChallengeTheme.rivalAccent,
            inviteStatus: .pending,
            acceptedAt: nil,
            currentScore: 0,
            bestSingleDay: nil,
            dailyValues: Array(repeating: nil, count: 7),
            isCurrentUser: isCurrentUser
        )
    }

    static func initials(from displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "·" }
        let parts = trimmed.split(separator: " ")
        let first = parts.first.flatMap { $0.first } ?? Character("·")
        let last  = parts.dropFirst().last.flatMap { $0.first }
        if let last { return "\(first)\(last)".uppercased() }
        return String(first).uppercased()
    }
}

// MARK: - Challenge

/// The aggregate competitive challenge record. UI-facing model assembled from RPC responses.
struct CompetitiveChallenge: Identifiable, Hashable {
    let id: String
    let familyId: String
    let focus: ChallengeFocus
    let mode: ChallengeMode
    var status: CompetitiveChallengeStatus
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date
    var completedAt: Date?
    var participants: [CompetitiveChallengeParticipant]
    var winnerUserId: String?
    var tieBreakUsed: Bool

    /// Current authenticated user as a participant, if any.
    var currentUser: CompetitiveChallengeParticipant? {
        return participants.first { $0.isCurrentUser }
    }

    /// Highest-score participant by primary metric. Stable across ties via name sort.
    var leader: CompetitiveChallengeParticipant? {
        guard !participants.isEmpty else { return nil }
        let ranked = participants.sorted { lhs, rhs in
            if lhs.currentScore == rhs.currentScore {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.currentScore > rhs.currentScore
        }
        return ranked.first
    }

    /// 1-indexed rank of the current user; nil when there is no current user in this challenge.
    var currentUserRank: Int? {
        guard !participants.isEmpty else { return nil }
        let sorted = participants.sorted { $0.currentScore > $1.currentScore }
        return sorted.firstIndex(where: { $0.isCurrentUser }).map { $0 + 1 }
    }

    /// Returns the standings sorted high → low (primary metric). Ties keep alphabetical stability.
    var standings: [CompetitiveChallengeParticipant] {
        return participants.sorted { lhs, rhs in
            if lhs.currentScore == rhs.currentScore {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.currentScore > rhs.currentScore
        }
    }

    /// Distance between top-two participants (primary metric). 0 when alone or tied at the top.
    var topGap: Double {
        let s = standings
        guard s.count >= 2 else { return 0 }
        return max(0, s[0].currentScore - s[1].currentScore)
    }

    /// True when at least two participants share the top score (used for tie-break choice UI).
    var hasTopTie: Bool {
        let s = standings
        guard s.count >= 2 else { return false }
        return s[0].currentScore == s[1].currentScore
    }
}

// MARK: - Formatting helpers

extension CompetitiveChallenge {
    /// Format a score for the focus type used by this challenge.
    func formatScore(_ value: Double) -> String {
        focus.formatScore(value)
    }
}

extension ChallengeFocus {
    /// Format a single score for this focus type (pillars: 1 decimal; steps: integer thousands).
    func formatScore(_ value: Double) -> String {
        if isCumulative {
            let intValue = Int(value.rounded())
            let formatter = NumberFormatter()
            formatter.groupingSeparator = ","
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: intValue)) ?? "\(intValue)"
        }
        return String(format: "%.1f", value)
    }

    /// Unit suffix shown in result and pending copy (`"pts"` for pillars; `"steps"` for steps).
    var scoreUnit: String { isCumulative ? "steps" : "pts" }
}
