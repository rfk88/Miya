//
//  CompetitiveChallengeResultView.swift
//  Miya Health
//
//  Sunday / post-completion screen. Surfaces three shapes:
//  - Winner card (clear winner): big score, runner-up, Champions points earned.
//  - "So close" (within 5%): same data, softer copy.
//  - Brawl podium (rank ≥ 3 participants): top three highlighted.
//  - Draw: offers a tie-break choice (highest single day) or "Run it back" rematch.
//

import SwiftUI

struct CompetitiveChallengeResultView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: DataManager

    let challengeId: String
    var onChanged: () async -> Void = {}

    @State private var challenge: CompetitiveChallenge?
    @State private var isLoading: Bool = true
    @State private var loadError: String?
    @State private var pendingAction: PendingAction?
    @State private var actionError: String?
    @State private var rematchSheet: Bool = false

    private enum PendingAction: Equatable { case tieBreak }

    var body: some View {
        NavigationStack {
            content
                .background(CompetitiveChallengeTheme.sheetBackground.ignoresSafeArea())
                .navigationTitle("Result")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task { await load() }
                .refreshable { await load() }
                .sheet(isPresented: $rematchSheet) {
                    if let challenge {
                        CompetitiveChallengeComposerView(
                            prefill: rematchPrefill(from: challenge),
                            onCreated: { _ in
                                await onChanged()
                            }
                        )
                        .environmentObject(dataManager)
                    } else {
                        ProgressView().padding()
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            VStack(spacing: 6) {
                Text("Couldn’t load the result.").font(.headline)
                Text(loadError).font(.subheadline).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if let challenge {
            ScrollView {
                VStack(spacing: 18) {
                    header(challenge)
                    if challenge.status == .cancelled {
                        cancelledCard(challenge)
                    } else if challenge.winnerUserId == nil {
                        drawSection(challenge)
                    } else {
                        outcomeCard(challenge)
                    }
                    standingsList(challenge)
                    if let actionError {
                        Text(actionError)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(CompetitiveChallengeTheme.rivalAccent)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: Header

    private func header(_ c: CompetitiveChallenge) -> some View {
        VStack(spacing: 8) {
            Image(systemName: c.focus.sfSymbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(c.focus.accent)
                .frame(width: 56, height: 56)
                .background(c.focus.accent.opacity(0.16))
                .clipShape(Circle())
            Text(headerTitle(c))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(headerSubtitle(c))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private func headerTitle(_ c: CompetitiveChallenge) -> String {
        if c.status == .cancelled { return "Challenge cancelled" }
        if c.winnerUserId == nil { return "Photo finish" }
        if c.currentUser?.userId == c.winnerUserId { return "You won" }
        let winner = c.participants.first { $0.userId == c.winnerUserId }?.displayName ?? "They"
        return "\(winner) took it"
    }

    private func headerSubtitle(_ c: CompetitiveChallenge) -> String {
        switch c.status {
        case .cancelled:
            return "Someone declined. Start a fresh one whenever you’re ready."
        case .completed:
            if c.winnerUserId == nil {
                return c.tieBreakUsed
                    ? "Already settled by tie-break."
                    : "Aggregate is tied. Settle with a tie-break or run it back."
            }
            if c.tieBreakUsed {
                return "Decided by the highest single day."
            }
            return "\(c.focus.displayName) · Mon–Sun"
        default:
            return ""
        }
    }

    // MARK: Cancelled

    private func cancelledCard(_ c: CompetitiveChallenge) -> some View {
        CompetitiveCard(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("No champions points awarded.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                Button {
                    rematchSheet = true
                } label: {
                    Text("Try another challenge")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(CompetitiveChallengeTheme.youAccent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusLg, style: .continuous))
                }
            }
        }
    }

    // MARK: Outcome card (winner present)

    private func outcomeCard(_ c: CompetitiveChallenge) -> some View {
        let s = c.standings
        let leader = s[0]
        let runnerUp = s.count >= 2 ? s[1] : nil
        let pointsAwarded = championsPoints(for: c, leader: leader)
        return CompetitiveCard(padding: 20) {
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    CompetitiveAvatarCircle(initials: leader.initials, tint: leader.avatarTint, size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(leader.displayName + (leader.isCurrentUser ? " (you)" : ""))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                        CompetitiveScoreDisplay(
                            value: leader.currentScore,
                            focus: c.focus,
                            color: c.focus.accent,
                            size: 30
                        )
                        if let pts = pointsAwarded {
                            HStack(spacing: 6) {
                                Image(systemName: "rosette")
                                    .font(.system(size: 12, weight: .bold))
                                Text("+\(pts) Champions pts")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(CompetitiveChallengeTheme.youAccent)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(CompetitiveChallengeTheme.youAccentSoft, in: Capsule())
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let runnerUp {
                    Divider().opacity(0.5)
                    HStack(spacing: 12) {
                        Text("Runner-up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(CompetitiveChallengeTheme.textMuted)
                            .frame(width: 76, alignment: .leading)
                        CompetitiveAvatarCircle(initials: runnerUp.initials, tint: runnerUp.avatarTint, size: 28)
                        Text(runnerUp.displayName + (runnerUp.isCurrentUser ? " (you)" : ""))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                        Spacer()
                        Text(c.formatScore(runnerUp.currentScore) + " " + c.focus.scoreUnit)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                            .monospacedDigit()
                    }
                }
                Button {
                    rematchSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                        Text("Run it back")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(CompetitiveChallengeTheme.cardSurfaceMuted)
                    .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusLg, style: .continuous))
                }
            }
        }
    }

    private func championsPoints(for c: CompetitiveChallenge, leader: CompetitiveChallengeParticipant) -> Int? {
        guard c.winnerUserId == leader.userId else { return nil }
        switch c.mode {
        case .headToHead:
            return BigChallengeChampionsRewards.duelWinnerPoints
        case .familyBrawl:
            return BigChallengeChampionsRewards.pointsForBrawl(placement: 1)
        }
    }

    // MARK: Draw

    private func drawSection(_ c: CompetitiveChallenge) -> some View {
        CompetitiveCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "equal.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(CompetitiveChallengeTheme.rivalAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aggregate tied")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                        if let s = c.standings.first {
                            Text("Top score: \(c.formatScore(s.currentScore)) \(c.focus.scoreUnit)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                        }
                    }
                    Spacer()
                }
                Text("Pick how to settle it:")
                    .competitiveSectionLabel()
                Button {
                    Task { await runTieBreak() }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "bolt.heart.fill")
                                .foregroundColor(CompetitiveChallengeTheme.youAccent)
                            Text(pendingAction == .tieBreak ? "Settling…" : "Settle with tie-break")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                            Spacer()
                            if pendingAction == .tieBreak {
                                ProgressView().tint(CompetitiveChallengeTheme.youAccent)
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(CompetitiveChallengeTheme.textMuted)
                            }
                        }
                        Text("Whoever had the single best day wins.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(CompetitiveChallengeTheme.youAccentSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous)
                            .strokeBorder(CompetitiveChallengeTheme.youAccent.opacity(0.35), lineWidth: 0.8)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous))
                }
                .disabled(pendingAction != nil)

                Button {
                    rematchSheet = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .foregroundColor(CompetitiveChallengeTheme.rivalAccent)
                            Text("Run it back next week")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(CompetitiveChallengeTheme.textMuted)
                        }
                        Text("Start a fresh Mon–Sun challenge with the same focus.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(CompetitiveChallengeTheme.cardSurfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous)
                            .strokeBorder(CompetitiveChallengeTheme.cardBorder, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous))
                }
            }
        }
    }

    // MARK: Standings list

    private func standingsList(_ c: CompetitiveChallenge) -> some View {
        let s = c.standings
        return CompetitiveCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Standings").competitiveSectionLabel()
                VStack(spacing: 6) {
                    ForEach(Array(s.enumerated()), id: \.element.id) { idx, p in
                        standingsRow(rank: idx + 1, p: p, focus: c.focus, winner: p.userId == c.winnerUserId)
                    }
                }
            }
        }
    }

    private func standingsRow(rank: Int, p: CompetitiveChallengeParticipant, focus: ChallengeFocus, winner: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(rank <= 3 ? CompetitiveChallengeTheme.youAccent : CompetitiveChallengeTheme.textMuted)
                .frame(width: 18)
            CompetitiveAvatarCircle(initials: p.initials, tint: p.avatarTint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(p.displayName + (p.isCurrentUser ? " (you)" : ""))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                    if winner {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(CompetitiveChallengeTheme.rivalAccent)
                    }
                }
                if let best = p.bestSingleDay {
                    Text("Best day: \(focus.formatScore(best)) \(focus.scoreUnit)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CompetitiveChallengeTheme.textMuted)
                }
            }
            Spacer()
            Text(focus.formatScore(p.currentScore) + " " + focus.scoreUnit)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(p.isCurrentUser ? CompetitiveChallengeTheme.youAccentSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusSm, style: .continuous))
    }

    // MARK: Actions

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let rows = try await dataManager.fetchCompetitiveChallengeDetail(challengeId: challengeId)
            let me = await dataManager.currentUserIdString
            await MainActor.run {
                self.challenge = CompetitiveChallenge.assemble(rows: rows, currentUserId: me)
                if self.challenge == nil {
                    self.loadError = "Challenge not available."
                }
            }
        } catch {
            await MainActor.run { loadError = error.localizedDescription }
        }
    }

    private func runTieBreak() async {
        guard pendingAction == nil else { return }
        pendingAction = .tieBreak
        actionError = nil
        defer { Task { @MainActor in pendingAction = nil } }
        do {
            let result = try await dataManager.resolveCompetitiveChallengeTieBreak(challengeId: challengeId)
            if !result.success {
                await MainActor.run {
                    actionError = Self.friendlyTieBreakError(result.error)
                }
                return
            }
            await onChanged()
            await load()
        } catch {
            await MainActor.run { actionError = error.localizedDescription }
        }
    }

    private func rematchPrefill(from challenge: CompetitiveChallenge) -> CompetitiveChallengeComposerView.Prefill {
        let invitees = challenge.participants
            .filter { !$0.isCurrentUser }
            .map { $0.userId }
        return .init(focus: challenge.focus, inviteeUserIds: invitees)
    }

    private static func friendlyTieBreakError(_ code: String?) -> String {
        switch code?.lowercased() {
        case "still_tied":
            return "Even the best single day is tied. Try “Run it back” instead."
        case "no_data_for_tie_break":
            return "Not enough daily data to tie-break this week."
        case "challenge_not_completed":
            return "The challenge isn’t over yet."
        case "not_authorized":
            return "Only family members can settle this."
        default:
            return code.map { "Couldn’t settle (\($0))." } ?? "Couldn’t settle the tie-break."
        }
    }
}
