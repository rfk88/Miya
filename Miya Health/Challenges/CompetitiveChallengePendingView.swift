//
//  CompetitiveChallengePendingView.swift
//  Miya Health
//
//  Shown to both the inviter and invitees while a competitive challenge is in
//  `pending_accepts`. Inviter sees the waiting state with per-invitee status.
//  Invitees see Accept / Decline at the bottom of the same screen.
//

import SwiftUI

struct CompetitiveChallengePendingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: DataManager

    let challengeId: String
    /// Closure to run after a state-changing action (accept, decline, cancel) so the parent can refresh.
    var onChanged: () async -> Void = {}

    @State private var challenge: CompetitiveChallenge?
    @State private var isLoading: Bool = true
    @State private var loadError: String?
    @State private var pendingAction: PendingAction?
    @State private var actionError: String?

    private enum PendingAction: Equatable { case accept, decline }

    var body: some View {
        NavigationStack {
            content
                .background(CompetitiveChallengeTheme.sheetBackground.ignoresSafeArea())
                .navigationTitle("Pending challenge")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task { await load() }
                .refreshable { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            VStack(spacing: 8) {
                Text("Couldn’t load the challenge.")
                    .font(.headline)
                Text(loadError)
                    .font(.subheadline)
                    .foregroundColor(CompetitiveChallengeTheme.textSecondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let challenge {
            ScrollView {
                VStack(spacing: 18) {
                    waitingHeader(challenge: challenge)
                    summaryCard(challenge: challenge)
                    participantList(challenge: challenge)
                    if let actionError {
                        Text(actionError)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(CompetitiveChallengeTheme.rivalAccent)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
            .safeAreaInset(edge: .bottom) {
                actionBar(challenge: challenge)
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private func waitingHeader(challenge: CompetitiveChallenge) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(headerText(for: challenge))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                    .multilineTextAlignment(.center)
                CompetitiveWaitingDots()
            }
            Text("They’ll get a push. Everyone has to accept before it starts.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func headerText(for challenge: CompetitiveChallenge) -> String {
        let pendingNames = challenge.participants
            .filter { $0.inviteStatus == .pending }
            .map { $0.displayName }
        switch pendingNames.count {
        case 0: return "Starting…"
        case 1: return "Waiting for \(pendingNames[0])"
        case 2: return "Waiting for \(pendingNames[0]) and \(pendingNames[1])"
        default: return "Waiting for \(pendingNames.count) people"
        }
    }

    // MARK: Summary

    @ViewBuilder
    private func summaryCard(challenge: CompetitiveChallenge) -> some View {
        CompetitiveCard(padding: 18) {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: challenge.focus.sfSymbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(challenge.focus.accent)
                        .frame(width: 52, height: 52)
                        .background(challenge.focus.accent.opacity(0.16))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(challenge.focus.displayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                        Text(challenge.focus.scoringRule)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                Divider().opacity(0.6)
                HStack(spacing: 18) {
                    summaryStat(label: "Mode", value: challenge.mode.displayName)
                    summaryStat(label: "Window", value: "Mon–Sun")
                    summaryStat(label: "People", value: "\(challenge.participants.count)")
                }
            }
        }
    }

    private func summaryStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).competitiveSectionLabel()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Participants

    @ViewBuilder
    private func participantList(challenge: CompetitiveChallenge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("People")
                .competitiveSectionLabel()
            VStack(spacing: 6) {
                ForEach(challenge.participants) { participant in
                    participantRow(participant)
                }
            }
        }
    }

    private func participantRow(_ p: CompetitiveChallengeParticipant) -> some View {
        HStack(spacing: 12) {
            CompetitiveAvatarCircle(initials: p.initials, tint: p.avatarTint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.displayName + (p.isCurrentUser ? " (you)" : ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                if p.inviteStatus == .accepted, let acceptedAt = p.acceptedAt {
                    Text("Accepted · \(Self.relativeTime(acceptedAt))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                } else if p.inviteStatus == .declined {
                    Text("Declined")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CompetitiveChallengeTheme.rivalAccent)
                } else {
                    Text("Waiting…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                }
            }
            Spacer()
            statusBadge(for: p.inviteStatus)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CompetitiveChallengeTheme.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous)
                .strokeBorder(CompetitiveChallengeTheme.cardBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous))
    }

    @ViewBuilder
    private func statusBadge(for status: CompetitiveChallengeParticipant.InviteStatus) -> some View {
        switch status {
        case .accepted:
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(CompetitiveChallengeTheme.youAccent)
                .font(.system(size: 18, weight: .semibold))
        case .declined:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(CompetitiveChallengeTheme.rivalAccent)
                .font(.system(size: 18, weight: .semibold))
        case .pending:
            Image(systemName: "hourglass")
                .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                .font(.system(size: 18, weight: .semibold))
        }
    }

    // MARK: Action bar

    @ViewBuilder
    private func actionBar(challenge: CompetitiveChallenge) -> some View {
        let me = challenge.currentUser
        VStack(spacing: 10) {
            if let me, me.inviteStatus == .pending {
                HStack(spacing: 10) {
                    Button {
                        Task { await respond(.decline) }
                    } label: {
                        Text(pendingAction == .decline ? "Declining…" : "Decline")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(CompetitiveChallengeTheme.cardSurfaceMuted)
                            .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusLg, style: .continuous))
                    }
                    .disabled(pendingAction != nil)

                    Button {
                        Task { await respond(.accept) }
                    } label: {
                        HStack(spacing: 6) {
                            if pendingAction == .accept {
                                ProgressView().tint(.white)
                            }
                            Text(pendingAction == .accept ? "Accepting…" : "I'm in")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(CompetitiveChallengeTheme.youAccent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusLg, style: .continuous))
                    }
                    .disabled(pendingAction != nil)
                }
            } else if me?.inviteStatus == .accepted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(CompetitiveChallengeTheme.youAccent)
                    Text("You’re in. Just waiting on the others.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                EmptyView()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }

    // MARK: Actions

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let rows = try await dataManager.fetchCompetitiveChallengeDetail(challengeId: challengeId)
            let me = await dataManager.currentUserIdString
            let assembled = CompetitiveChallenge.assemble(rows: rows, currentUserId: me)
            await MainActor.run {
                self.challenge = assembled
                if assembled == nil {
                    self.loadError = "Challenge not available."
                }
            }
        } catch {
            await MainActor.run { loadError = error.localizedDescription }
        }
    }

    private func respond(_ action: PendingAction) async {
        guard pendingAction == nil else { return }
        pendingAction = action
        actionError = nil
        defer {
            Task { @MainActor in pendingAction = nil }
        }
        do {
            let result = try await dataManager.respondToCompetitiveChallengeInvite(
                challengeId: challengeId,
                action: action == .accept ? .accept : .decline
            )
            if !result.success {
                await MainActor.run {
                    actionError = CompetitiveChallengeComposerViewModel.friendlyMessage(forCode: result.error ?? "unknown")
                }
                return
            }
            await onChanged()
            // Re-fetch state. If decline → challenge is now cancelled; we keep the view open
            // so the user can see the outcome (declined) or, if accepted, see the updated list.
            await load()
            if action == .accept, result.all_accepted == true {
                // All-accepted → the parent will refresh and route to the active view.
                await MainActor.run { dismiss() }
            } else if action == .decline {
                await MainActor.run { dismiss() }
            }
        } catch {
            await MainActor.run { actionError = error.localizedDescription }
        }
    }

    // MARK: Util

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
