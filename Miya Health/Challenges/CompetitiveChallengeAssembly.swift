//
//  CompetitiveChallengeAssembly.swift
//  Miya Health
//
//  Turns RPC rows from `get_competitive_challenge_detail` into the UI-facing
//  `CompetitiveChallenge` model. Centralised so the composer, pending, active,
//  and result screens all read consistent data.
//

import Foundation
import SwiftUI

extension CompetitiveChallenge {

    /// Build a `CompetitiveChallenge` aggregate from the rows the RPC returns.
    /// - Parameters:
    ///   - rows: one row per participant.
    ///   - currentUserId: lowercased UUID of the authenticated user. Pass nil if unknown.
    static func assemble(
        rows: [DataManager.CompetitiveChallengeDetailRow],
        currentUserId: String?
    ) -> CompetitiveChallenge? {
        guard let first = rows.first,
              let focus = ChallengeFocus(dbKey: first.focus),
              let status = CompetitiveChallengeStatus(rawValue: first.status) else {
            return nil
        }

        let mode: ChallengeMode = ChallengeMode(rawValue: first.mode) ?? .from(participantCount: rows.count)

        let isoDate = ISO8601DateFormatter()
        isoDate.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoDateNoFractional = ISO8601DateFormatter()
        isoDateNoFractional.formatOptions = [.withInternetDateTime]
        func parseTimestamp(_ s: String?) -> Date? {
            guard let s else { return nil }
            return isoDate.date(from: s) ?? isoDateNoFractional.date(from: s)
        }
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let startDate: Date? = first.start_date.flatMap { dayFormatter.date(from: $0) }
        let endDate: Date? = first.end_date.flatMap { dayFormatter.date(from: $0) }
        let createdAt: Date = parseTimestamp(first.created_at) ?? Date()
        let completedAt: Date? = parseTimestamp(first.completed_at)

        // Deterministic colour assignment by participant index AFTER putting the current
        // user first if present. Slot 0 = teal (you), slot 1 = amber (rival), then a small
        // distinct palette for brawls.
        let palette: [Color] = [
            CompetitiveChallengeTheme.youAccent,        // 0
            CompetitiveChallengeTheme.rivalAccent,      // 1
            CompetitiveChallengeTheme.focusSleep,       // 2
            CompetitiveChallengeTheme.focusActivity,    // 3
            CompetitiveChallengeTheme.focusRecovery,    // 4
            CompetitiveChallengeTheme.focusSteps        // 5
        ]

        // Sort: current user first, then alphabetically for stable visual ordering.
        let orderedRows: [DataManager.CompetitiveChallengeDetailRow] = rows.sorted { lhs, rhs in
            let lhsIsMe = (currentUserId.map { lhs.participant_user_id.lowercased() == $0.lowercased() }) ?? false
            let rhsIsMe = (currentUserId.map { rhs.participant_user_id.lowercased() == $0.lowercased() }) ?? false
            if lhsIsMe != rhsIsMe { return lhsIsMe }
            let lhsName = lhs.participant_first_name ?? "Member"
            let rhsName = rhs.participant_first_name ?? "Member"
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        let participants: [CompetitiveChallengeParticipant] = orderedRows.enumerated().map { (index, row) in
            let isMe = (currentUserId.map { row.participant_user_id.lowercased() == $0.lowercased() }) ?? false
            let tint = palette[min(index, palette.count - 1)]
            let displayName = row.participant_first_name ?? "Member"
            let invite = CompetitiveChallengeParticipant.InviteStatus(rawValue: row.participant_invite_status) ?? .pending
            let acceptedAt = parseTimestamp(row.participant_accepted_at)

            let daily = Self.buildDailyValues(
                start: startDate,
                rowDaily: row.participant_daily ?? [],
                focus: focus,
                dayFormatter: dayFormatter
            )

            return CompetitiveChallengeParticipant(
                userId: row.participant_user_id.lowercased(),
                displayName: displayName,
                initials: CompetitiveChallengeParticipant.initials(from: displayName),
                avatarTint: tint,
                inviteStatus: invite,
                acceptedAt: acceptedAt,
                currentScore: row.participant_aggregate ?? 0,
                bestSingleDay: row.participant_best_day,
                dailyValues: daily,
                isCurrentUser: isMe
            )
        }

        return CompetitiveChallenge(
            id: first.challenge_id,
            familyId: first.family_id,
            focus: focus,
            mode: mode,
            status: status,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            completedAt: completedAt,
            participants: participants,
            winnerUserId: first.winner_user_id?.lowercased(),
            tieBreakUsed: first.tie_break_used ?? false
        )
    }

    /// Builds the Mon..Sun aligned array of daily values. `nil` entries mean "no data".
    private static func buildDailyValues(
        start: Date?,
        rowDaily: [DataManager.CompetitiveChallengeDetailRow.DailyEntry],
        focus: ChallengeFocus,
        dayFormatter: DateFormatter
    ) -> [Double?] {
        var slots: [Double?] = Array(repeating: nil, count: 7)
        guard let start else { return slots }
        let calendar = Calendar(identifier: .gregorian)
        var fromStartByDate: [String: (pillar: Double?, steps: Double?)] = [:]
        for entry in rowDaily {
            guard let dateString = entry.local_date else { continue }
            fromStartByDate[dateString] = (entry.pillar_score, entry.steps)
        }
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        for i in 0..<7 {
            if let day = utc.date(byAdding: .day, value: i, to: start) {
                let key = dayFormatter.string(from: day)
                if let data = fromStartByDate[key] {
                    if focus == .steps {
                        slots[i] = data.steps
                    } else {
                        slots[i] = data.pillar
                    }
                }
            }
        }
        return slots
    }
}
