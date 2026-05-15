//
//  CompetitiveChallengeComposerView.swift
//  Miya Health
//
//  Phase B composer for BIG (competitive) challenges: pick 1..5 family members,
//  pick a focus (Sleep / Activity / Recovery / Steps), send invites. Mode is
//  derived from selection size (1 picked → head_to_head, 2..5 → family_brawl).
//
//  Surfaces are Miya's light dashboard palette only.
//

import Auth
import Supabase
import SwiftUI

struct CompetitiveChallengeComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: DataManager

    /// Optional prefill (used by "Run it back" on the result screen).
    var prefill: Prefill?
    /// Called after a successful create. Receives the new challenge id so the parent can refresh / navigate.
    var onCreated: (_ challengeId: String) async -> Void

    @StateObject private var viewModel = CompetitiveChallengeComposerViewModel()

    /// Prefill data for rematches.
    struct Prefill: Equatable {
        let focus: ChallengeFocus
        let inviteeUserIds: [String]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    vsBanner
                    whoSection
                    focusSection
                    infoStrip
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 110) // leave room for the floating CTA
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CompetitiveChallengeTheme.sheetBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { sendButton }
            .navigationTitle("New challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isSending)
                }
            }
            .task {
                viewModel.loadMembers = { [weak viewModel] in
                    guard let viewModel else { return }
                    let loaded = await Self.loadMembers(dataManager: dataManager)
                    await MainActor.run {
                        viewModel.members = loaded.members
                        viewModel.youInitials = loaded.youInitials
                    }
                }
                viewModel.send = { [weak dataManager] invitees, focus in
                    guard let dataManager else { return .failed(message: "Internal error") }
                    do {
                        let result = try await dataManager.createCompetitiveChallenge(
                            focus: focus,
                            inviteeUserIds: invitees
                        )
                        if result.success, let challengeId = result.challenge_id {
                            return .created(challengeId: challengeId)
                        }
                        return .rejected(reason: result.error ?? "unknown")
                    } catch {
                        return .failed(message: error.localizedDescription)
                    }
                }
                await viewModel.runLoad()
                if let prefill {
                    await MainActor.run {
                        viewModel.selectedFocus = prefill.focus
                        let valid = Set(viewModel.members.map { $0.userId.lowercased() })
                        let kept = prefill.inviteeUserIds.map { $0.lowercased() }.filter { valid.contains($0) }
                        viewModel.selectedMemberIds = Set(kept.prefix(CompetitiveChallengeComposerViewModel.maxSelectableInvitees))
                    }
                }
            }
        }
    }

    // MARK: VS banner

    @ViewBuilder
    private var vsBanner: some View {
        CompetitiveCard(padding: 18) {
            HStack(spacing: 12) {
                CompetitiveAvatarCircle(
                    initials: viewModel.youInitials,
                    tint: CompetitiveChallengeTheme.youAccent,
                    size: 56
                )
                VStack(spacing: 4) {
                    Text("VS")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                    Text(modeLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                        .textCase(.uppercase)
                        .kerning(0.8)
                }
                .frame(maxWidth: .infinity)

                opponentBanner
            }
        }
    }

    private var opponentBanner: some View {
        let selected: [CompetitiveChallengePickableMember] = viewModel.members.filter { viewModel.selectedMemberIds.contains($0.userId) }
        return Group {
            if selected.isEmpty {
                CompetitiveAvatarCircle(
                    initials: "?",
                    tint: CompetitiveChallengeTheme.neutralChip,
                    size: 56
                )
            } else if selected.count == 1, let only = selected.first {
                CompetitiveAvatarCircle(
                    initials: only.initials,
                    tint: only.avatarTint,
                    size: 56
                )
            } else {
                CompetitiveAvatarStack(
                    avatars: selected.map { ($0.initials, $0.avatarTint, false) },
                    size: 44
                )
            }
        }
    }

    private var modeLabel: String {
        switch viewModel.mode {
        case .headToHead?:  return "Head to head"
        case .familyBrawl?: return "Family brawl"
        case nil:           return "Pick a rival"
        }
    }

    // MARK: WHO

    @ViewBuilder
    private var whoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Who")
                    .competitiveSectionLabel()
                Spacer()
                Text("\(viewModel.selectedMemberIds.count)/\(CompetitiveChallengeComposerViewModel.maxSelectableInvitees)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(viewModel.isAtCapLimit ? CompetitiveChallengeTheme.rivalAccent : CompetitiveChallengeTheme.textMuted)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }

            if viewModel.isLoadingMembers {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if viewModel.members.isEmpty {
                Text("No family members to challenge yet. Once others join your family, they'll show up here.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(viewModel.members) { member in
                        CompetitiveMemberPill(
                            displayName: member.displayName,
                            initials: member.initials,
                            avatarTint: member.avatarTint,
                            isSelected: viewModel.selectedMemberIds.contains(member.userId),
                            isDisabled: shouldDisable(member),
                            disabledReason: member.isInActiveChallenge ? "In a challenge" : nil
                        ) {
                            viewModel.toggleMember(member.userId)
                        }
                    }
                }
            }

            if viewModel.isAtCapLimit {
                Text("Maximum 6 people (you + 5).")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CompetitiveChallengeTheme.rivalAccent)
            }
        }
    }

    private func shouldDisable(_ member: CompetitiveChallengePickableMember) -> Bool {
        if member.isInActiveChallenge { return true }
        if viewModel.selectedMemberIds.contains(member.userId) { return false }
        return viewModel.isAtCapLimit
    }

    // MARK: FOCUS

    @ViewBuilder
    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focus")
                .competitiveSectionLabel()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(ChallengeFocus.allCases, id: \.self) { focus in
                    CompetitiveFocusCard(
                        focus: focus,
                        isSelected: viewModel.selectedFocus == focus
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            viewModel.selectedFocus = focus
                        }
                    }
                }
            }
        }
    }

    // MARK: Info strip

    @ViewBuilder
    private var infoStrip: some View {
        CompetitiveCard(padding: 14, radius: CompetitiveChallengeTheme.radiusMd, background: viewModel.selectedFocus.accent.opacity(0.08)) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: viewModel.selectedFocus.sfSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(viewModel.selectedFocus.accent)
                    .frame(width: 36, height: 36)
                    .background(viewModel.selectedFocus.accent.opacity(0.18))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.selectedFocus.displayName) · Mon–Sun")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                    Text("\(viewModel.selectedFocus.scoringRule). Everyone needs to accept before it starts.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(CompetitiveChallengeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: CTA

    @ViewBuilder
    private var sendButton: some View {
        VStack(spacing: 8) {
            if let sendError = viewModel.sendError {
                Text(sendError)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CompetitiveChallengeTheme.rivalAccent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSending {
                        ProgressView().tint(.white)
                    }
                    Text(viewModel.isSending ? "Sending…" : sendCTALabel)
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    viewModel.canSend
                        ? AnyShapeStyle(CompetitiveChallengeTheme.youAccent)
                        : AnyShapeStyle(CompetitiveChallengeTheme.neutralChip)
                )
                .foregroundColor(viewModel.canSend ? .white : CompetitiveChallengeTheme.textMuted)
                .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusLg, style: .continuous))
            }
            .disabled(!viewModel.canSend)
            .accessibilityLabel(Text(sendCTALabel))
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background(.thinMaterial)
    }

    private var sendCTALabel: String {
        switch viewModel.selectedMemberIds.count {
        case 0: return "Pick someone first"
        case 1: return "Send challenge"
        default: return "Send to \(viewModel.selectedMemberIds.count) people"
        }
    }

    private func submit() async {
        guard let outcome = await viewModel.runSend() else { return }
        if case let .created(challengeId) = outcome {
            await onCreated(challengeId)
            await MainActor.run { dismiss() }
        }
    }

    // MARK: Loading helpers (run as async stand-alone to keep the view body light)

    private struct LoadedMembers {
        let members: [CompetitiveChallengePickableMember]
        let youInitials: String
    }

    private static func loadMembers(dataManager: DataManager) async -> LoadedMembers {
        guard let familyId = await MainActor.run(body: { dataManager.currentFamilyId }) else {
            return LoadedMembers(members: [], youInitials: "ME")
        }
        let myId = await dataManager.currentUserIdString?.lowercased()
        let palette: [Color] = [
            CompetitiveChallengeTheme.rivalAccent,
            CompetitiveChallengeTheme.focusSleep,
            CompetitiveChallengeTheme.focusActivity,
            CompetitiveChallengeTheme.focusRecovery,
            CompetitiveChallengeTheme.focusSteps
        ]

        var membersBlocked: Set<String> = []
        // A member is "blocked" if they appear as a participant in any pending_accepts/active competitive challenge.
        do {
            let existing = try await dataManager.fetchCompetitiveChallengesForFamily()
            for c in existing where c.status == CompetitiveChallengeStatus.pendingAccepts.rawValue
                || c.status == CompetitiveChallengeStatus.active.rawValue {
                // For each open challenge, we need the participant list; cheaper to call detail.
                if let detail = try? await dataManager.fetchCompetitiveChallengeDetail(challengeId: c.id) {
                    for row in detail {
                        membersBlocked.insert(row.participant_user_id.lowercased())
                    }
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ CompetitiveComposer: failed to compute blocked members: \(error)")
            #endif
        }

        do {
            let records = try await dataManager.fetchFamilyMembers(familyId: familyId)
            let youInitials: String = {
                guard let myId,
                      let myRecord = records.first(where: { $0.userId?.uuidString.lowercased() == myId }) else {
                    return "ME"
                }
                return CompetitiveChallengeParticipant.initials(from: myRecord.firstName)
            }()
            let filtered = records
                .compactMap { rec -> (String, String)? in
                    guard rec.inviteStatus.lowercased() == "accepted",
                          let uidRaw = rec.userId?.uuidString.lowercased(),
                          !uidRaw.isEmpty else { return nil }
                    if let myId, uidRaw == myId { return nil }
                    return (uidRaw, rec.firstName)
                }
                .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
                .enumerated()
                .map { (idx, pair) -> CompetitiveChallengePickableMember in
                    let tint = palette[idx % palette.count]
                    return CompetitiveChallengePickableMember(
                        userId: pair.0,
                        displayName: pair.1,
                        initials: CompetitiveChallengeParticipant.initials(from: pair.1),
                        avatarTint: tint,
                        isInActiveChallenge: membersBlocked.contains(pair.0)
                    )
                }
            return LoadedMembers(members: filtered, youInitials: youInitials)
        } catch {
            #if DEBUG
            print("⚠️ CompetitiveComposer: failed to load members: \(error)")
            #endif
            return LoadedMembers(members: [], youInitials: "ME")
        }
    }
}
