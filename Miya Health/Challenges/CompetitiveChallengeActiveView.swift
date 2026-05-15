//
//  CompetitiveChallengeActiveView.swift
//  Miya Health
//
//  Live view of an in-flight competitive challenge. Renders:
//  - Head-to-head: battle card (two scores, gap, lead pill).
//  - Family brawl: leaderboard list with podium.
//  - Week strip (Mon..Sun day dots).
//  - Stats grid (best day, last sync).
//

import SwiftUI

struct CompetitiveChallengeActiveView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: DataManager

    let challengeId: String

    @State private var challenge: CompetitiveChallenge?
    @State private var isLoading: Bool = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            content
                .background(CompetitiveChallengeTheme.sheetBackground.ignoresSafeArea())
                .navigationTitle("Live challenge")
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
            VStack(spacing: 6) {
                Text("Couldn’t load the challenge.").font(.headline)
                Text(loadError).font(.subheadline).foregroundColor(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
        } else if let challenge {
            ScrollView {
                VStack(spacing: 18) {
                    titleStrip(challenge)
                    if challenge.mode == .headToHead, challenge.participants.count == 2 {
                        battleCard(challenge)
                    } else {
                        brawlBoard(challenge)
                    }
                    weekCard(challenge)
                    statsGrid(challenge)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
    }

    private func titleStrip(_ c: CompetitiveChallenge) -> some View {
        HStack(spacing: 12) {
            Image(systemName: c.focus.sfSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(c.focus.accent)
                .frame(width: 38, height: 38)
                .background(c.focus.accent.opacity(0.16))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(c.focus.displayName) · \(c.mode.displayName)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                Text(c.focus.scoringRule)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CompetitiveChallengeTheme.textSecondary)
            }
            Spacer()
            CompetitiveLeadPill(state: leadState(for: c), focus: c.focus)
        }
    }

    private func leadState(for c: CompetitiveChallenge) -> CompetitiveLeadPill.State {
        let s = c.standings
        guard let top = s.first else { return .unknown }
        guard s.count >= 2 else { return .unknown }
        let second = s[1]
        if top.currentScore == second.currentScore { return .tied }
        let margin = top.currentScore - second.currentScore
        if top.isCurrentUser {
            return .youAhead(margin: margin)
        }
        let myScore = c.currentUser?.currentScore ?? 0
        let leaderName = top.displayName
        return .opponentAhead(name: leaderName, margin: top.currentScore - myScore)
    }

    // MARK: H2H battle card

    private func battleCard(_ c: CompetitiveChallenge) -> some View {
        let s = c.standings
        let leader = s[0]
        let trailing = s[1]
        return CompetitiveCard(padding: 20) {
            VStack(spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    sideStack(participant: leader, focus: c.focus, alignment: .leading)
                    VStack(spacing: 4) {
                        Text("VS")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(CompetitiveChallengeTheme.textMuted)
                        Text("Gap")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(CompetitiveChallengeTheme.textMuted)
                            .textCase(.uppercase)
                            .kerning(0.6)
                        Text(c.formatScore(c.topGap))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                            .monospacedDigit()
                    }
                    .frame(width: 64)
                    sideStack(participant: trailing, focus: c.focus, alignment: .trailing)
                }
            }
        }
    }

    private func sideStack(participant: CompetitiveChallengeParticipant, focus: ChallengeFocus, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            CompetitiveAvatarCircle(initials: participant.initials, tint: participant.avatarTint, size: 56)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
            Text(participant.displayName + (participant.isCurrentUser ? " (you)" : ""))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                .lineLimit(1)
            CompetitiveScoreDisplay(
                value: participant.currentScore,
                focus: focus,
                color: participant.isCurrentUser ? CompetitiveChallengeTheme.youAccent : CompetitiveChallengeTheme.textPrimary,
                size: 36
            )
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    // MARK: Brawl leaderboard

    private func brawlBoard(_ c: CompetitiveChallenge) -> some View {
        let s = c.standings
        return VStack(spacing: 8) {
            ForEach(Array(s.enumerated()), id: \.element.id) { idx, participant in
                brawlRow(rank: idx + 1, participant: participant, focus: c.focus)
            }
        }
    }

    private func brawlRow(rank: Int, participant: CompetitiveChallengeParticipant, focus: ChallengeFocus) -> some View {
        let isPodium = rank <= 3
        return HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(isPodium ? CompetitiveChallengeTheme.youAccent : CompetitiveChallengeTheme.textMuted)
                .frame(width: 22)
            CompetitiveAvatarCircle(initials: participant.initials, tint: participant.avatarTint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(participant.displayName + (participant.isCurrentUser ? " (you)" : ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                if let best = participant.bestSingleDay {
                    Text("Best day: \(focus.formatScore(best)) \(focus.scoreUnit)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CompetitiveChallengeTheme.textMuted)
                }
            }
            Spacer()
            CompetitiveScoreDisplay(
                value: participant.currentScore,
                focus: focus,
                color: participant.isCurrentUser ? CompetitiveChallengeTheme.youAccent : CompetitiveChallengeTheme.textPrimary,
                size: 22
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(participant.isCurrentUser ? CompetitiveChallengeTheme.youAccentSoft : CompetitiveChallengeTheme.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous)
                .strokeBorder(CompetitiveChallengeTheme.cardBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous))
    }

    // MARK: Week strip card

    private func weekCard(_ c: CompetitiveChallenge) -> some View {
        return CompetitiveCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Week").competitiveSectionLabel()
                    Spacer()
                    if let start = c.startDate, let end = c.endDate {
                        Text("\(Self.shortDay(start)) – \(Self.shortDay(end))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(CompetitiveChallengeTheme.textMuted)
                    }
                }
                CompetitiveWeekStrip(
                    values: c.currentUser?.dailyValues ?? Array(repeating: nil, count: 7),
                    todayIndex: todayIndex(in: c),
                    focus: c.focus
                )
            }
        }
    }

    private func todayIndex(in c: CompetitiveChallenge) -> Int? {
        guard let start = c.startDate else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: now).day ?? -1
        guard days >= 0 && days < 7 else { return nil }
        return days
    }

    private static func shortDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    // MARK: Stats grid

    private func statsGrid(_ c: CompetitiveChallenge) -> some View {
        let me = c.currentUser
        return CompetitiveCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your numbers").competitiveSectionLabel()
                HStack(spacing: 12) {
                    statTile(
                        title: "Best day",
                        value: me?.bestSingleDay.map { c.formatScore($0) } ?? "—",
                        unit: c.focus.scoreUnit,
                        tint: c.focus.accent
                    )
                    statTile(
                        title: c.focus.isCumulative ? "Total" : "Average",
                        value: me.map { c.formatScore($0.currentScore) } ?? "—",
                        unit: c.focus.scoreUnit,
                        tint: CompetitiveChallengeTheme.youAccent
                    )
                    statTile(
                        title: "Rank",
                        value: c.currentUserRank.map { String($0) } ?? "—",
                        unit: "of \(c.participants.count)",
                        tint: CompetitiveChallengeTheme.textSecondary
                    )
                }
            }
        }
    }

    private func statTile(title: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).competitiveSectionLabel()
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CompetitiveChallengeTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CompetitiveChallengeTheme.cardSurfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous))
    }

    // MARK: Loading

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
}
