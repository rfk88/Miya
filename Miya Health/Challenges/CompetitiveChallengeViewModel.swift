//
//  CompetitiveChallengeViewModel.swift
//  Miya Health
//
//  View model shell for the Phase B competitive-challenge composer. Backend wiring
//  arrives in Phase 2 (`DataManager.createCompetitiveChallenge`). The shell defines
//  the contract that view layer and view-model layer agree on so the composer can
//  be built and previewed before the RPC exists.
//

import Combine
import Foundation
import SwiftUI

/// Picker member entry for the WHO grid.
struct CompetitiveChallengePickableMember: Identifiable, Equatable {
    let userId: String
    let displayName: String
    let initials: String
    let avatarTint: Color
    /// When true, render the pill disabled with a small "In a challenge" badge.
    let isInActiveChallenge: Bool

    var id: String { userId }

    static func == (lhs: CompetitiveChallengePickableMember, rhs: CompetitiveChallengePickableMember) -> Bool {
        return lhs.userId == rhs.userId
            && lhs.displayName == rhs.displayName
            && lhs.isInActiveChallenge == rhs.isInActiveChallenge
    }
}

/// Outcomes the view layer reacts to after pressing **Send**.
enum CompetitiveChallengeComposerOutcome: Equatable {
    case created(challengeId: String)
    /// Server returned `success: false` with an `error` code; surface friendly copy.
    case rejected(reason: String)
    /// Network / parsing / unexpected error.
    case failed(message: String)
}

@MainActor
final class CompetitiveChallengeComposerViewModel: ObservableObject {

    // MARK: Inputs
    @Published var members: [CompetitiveChallengePickableMember] = []
    @Published var youInitials: String = "ME"
    @Published var selectedMemberIds: Set<String> = []
    @Published var selectedFocus: ChallengeFocus = .sleep

    // MARK: Lifecycle state
    @Published private(set) var isLoadingMembers: Bool = false
    @Published private(set) var isSending: Bool = false
    @Published private(set) var loadError: String?
    @Published private(set) var sendError: String?

    // MARK: Derived

    /// Resolved mode given current selection size; nil while empty.
    var mode: ChallengeMode? {
        guard !selectedMemberIds.isEmpty else { return nil }
        return ChallengeMode.from(participantCount: selectedMemberIds.count + 1)
    }

    /// Server-enforced max participant count (current user counts as one).
    static let maxParticipants: Int = 6

    /// Max additional invitees that can still be selected (cap minus current-user slot).
    static let maxSelectableInvitees: Int = maxParticipants - 1

    /// True when at least one invitee is selected and we are not mid-flight.
    var canSend: Bool {
        return !selectedMemberIds.isEmpty && !isSending && !isLoadingMembers && !isAtCapLimit
    }

    /// True when the selection is at the hard cap so the picker should disable further selection.
    var isAtCapLimit: Bool {
        selectedMemberIds.count >= Self.maxSelectableInvitees
    }

    // MARK: Intents

    func toggleMember(_ userId: String) {
        if selectedMemberIds.contains(userId) {
            selectedMemberIds.remove(userId)
        } else {
            // Hard cap: refuse to add over the cap.
            guard selectedMemberIds.count < Self.maxSelectableInvitees else { return }
            selectedMemberIds.insert(userId)
        }
    }

    func clearSendError() { sendError = nil }

    // MARK: Backend hooks (wired in Phase 2)

    /// Set this from the view's `task` to load the member list.
    var loadMembers: (() async -> Void)?
    /// Set this from the view's environment; receives the participant id list (excluding the caller).
    var send: ((_ inviteeUserIds: [String], _ focus: ChallengeFocus) async -> CompetitiveChallengeComposerOutcome)?

    func runLoad() async {
        guard !isLoadingMembers else { return }
        isLoadingMembers = true
        loadError = nil
        defer { isLoadingMembers = false }
        await loadMembers?()
    }

    func runSend() async -> CompetitiveChallengeComposerOutcome? {
        guard canSend, let send else { return nil }
        isSending = true
        sendError = nil
        defer { isSending = false }
        let invitees = Array(selectedMemberIds)
        let outcome = await send(invitees, selectedFocus)
        switch outcome {
        case .rejected(let reason):
            sendError = Self.friendlyMessage(forCode: reason)
        case .failed(let message):
            sendError = message
        case .created:
            break
        }
        return outcome
    }

    // MARK: Error mapping

    static func friendlyMessage(forCode code: String) -> String {
        switch code.lowercased() {
        case "family_brawl_max_6_participants":
            return "A challenge can have up to 6 people. Drop someone and try again."
        case "active_challenge_exists":
            return "One of the people you picked is already in a challenge this week. Try again when it wraps up."
        case "member_not_in_same_family":
            return "Someone you picked isn’t in your family anymore."
        case "not_authenticated":
            return "Please sign in and try again."
        case "duplicate_participants":
            return "You can’t challenge the same person twice."
        case "no_participants_selected":
            return "Pick at least one person to challenge."
        default:
            return "Couldn’t start the challenge (\(code)). Please try again."
        }
    }
}
