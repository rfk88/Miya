import SwiftUI

// MARK: - Family Challenges View
// 3 tabs: Active (sent), My Challenges (received), Archive (completed/declined).

struct FamilyChallengesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: DataManager
    
    @State private var challenges: [FamilyChallenge] = []
    @State private var competitiveChallenges: [DataManager.CompetitiveChallengeListRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab = 0
    @State private var hasAppliedInitialTab = false
    @State private var activeBadgeCleared = false
    @State private var myChallengesBadgeCleared = false
    @State private var archiveBadgeCleared = false
    @State private var showCompetitiveComposer = false
    @State private var openCompetitiveChallengeId: String?
    
    private var activeChallenges: [FamilyChallenge] {
        challenges.filter { $0.myRole == "challenger" && ["pending_invite", "active", "snoozed"].contains($0.status) }
    }
    
    private var myChallenges: [FamilyChallenge] {
        challenges.filter { $0.myRole == "challengee" && ["pending_invite", "active", "snoozed"].contains($0.status) }
    }
    
    private var archiveChallenges: [FamilyChallenge] {
        challenges.filter { ["completed_success", "completed_failed"].contains($0.status) }
    }
    
    private var competitiveOpen: [DataManager.CompetitiveChallengeListRow] {
        competitiveChallenges.filter {
            $0.status == CompetitiveChallengeStatus.pendingAccepts.rawValue
                || $0.status == CompetitiveChallengeStatus.active.rawValue
        }
    }

    private var competitiveDone: [DataManager.CompetitiveChallengeListRow] {
        competitiveChallenges.filter {
            $0.status == CompetitiveChallengeStatus.completed.rawValue
                || $0.status == CompetitiveChallengeStatus.cancelled.rawValue
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let msg = errorMessage {
                    Text(msg)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView(selection: $selectedTab) {
                        challengeList(activeChallenges, emptyTitle: "No active challenges", emptySubtitle: "Challenges you send will appear here.")
                            .tabItem {
                                Label("Active", systemImage: "figure.run")
                            }
                            .tag(0)
                            .onAppear { activeBadgeCleared = true }

                        competitiveSection
                            .tabItem {
                                Label("Competitive", systemImage: "trophy.fill")
                            }
                            .tag(1)

                        challengeList(myChallenges, emptyTitle: "No challenges for you", emptySubtitle: "Challenges others send you will appear here.")
                            .tabItem {
                                Label("My Challenges", systemImage: "person.fill")
                            }
                            .tag(2)
                            .onAppear { myChallengesBadgeCleared = true }

                        challengeList(archiveChallenges, emptyTitle: "No archive yet", emptySubtitle: "Completed or declined challenges appear here.")
                            .tabItem {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tag(3)
                            .onAppear { archiveBadgeCleared = true }
                    }
                }
            }
            .navigationTitle("Family Challenges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCompetitiveComposer) {
                CompetitiveChallengeComposerView { _ in
                    await loadCompetitive()
                    await MainActor.run { selectedTab = 1 }
                }
                .environmentObject(dataManager)
            }
            .sheet(item: Binding(
                get: { openCompetitiveChallengeId.map { CompetitiveChallengeIdRef(id: $0) } },
                set: { openCompetitiveChallengeId = $0?.id }
            )) { ref in
                competitiveDetailSheet(for: ref.id)
            }
            .task {
                await loadAll()
            }
        }
    }

    // Identifiable wrapper so we can use `.sheet(item:)` with a String.
    private struct CompetitiveChallengeIdRef: Identifiable {
        let id: String
    }

    /// Routes to the right detail screen based on the challenge's current status.
    @ViewBuilder
    private func competitiveDetailSheet(for id: String) -> some View {
        if let row = competitiveChallenges.first(where: { $0.id == id }) {
            switch row.status {
            case CompetitiveChallengeStatus.pendingAccepts.rawValue:
                CompetitiveChallengePendingView(challengeId: id) {
                    await loadCompetitive()
                }
                .environmentObject(dataManager)
            case CompetitiveChallengeStatus.active.rawValue:
                CompetitiveChallengeActiveView(challengeId: id)
                    .environmentObject(dataManager)
            case CompetitiveChallengeStatus.completed.rawValue,
                 CompetitiveChallengeStatus.cancelled.rawValue:
                CompetitiveChallengeResultView(challengeId: id) {
                    await loadCompetitive()
                }
                .environmentObject(dataManager)
            default:
                // Fall back to pending view; the embedded refresh covers state transitions.
                CompetitiveChallengePendingView(challengeId: id) {
                    await loadCompetitive()
                }
                .environmentObject(dataManager)
            }
        } else {
            // Unknown id — show pending view; it self-loads and surfaces its own error if missing.
            CompetitiveChallengePendingView(challengeId: id) {
                await loadCompetitive()
            }
            .environmentObject(dataManager)
        }
    }

    // MARK: Competitive section

    @ViewBuilder
    private var competitiveStartCTA: some View {
        Button {
            showCompetitiveComposer = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Start challenge with a family member")
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.miyaSecondary.opacity(0.16))
            .foregroundColor(Color.miyaSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.miyaSecondary.opacity(0.5), lineWidth: 1)
            )
        }
        .accessibilityLabel("Start challenge with a family member")
    }

    @ViewBuilder
    private var competitiveSection: some View {
        if competitiveOpen.isEmpty && competitiveDone.isEmpty {
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                Image(systemName: "trophy")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.miyaSecondary)
                Text("No competitive challenges yet")
                    .font(.headline)
                Text("Challenge someone head-to-head or rally the family in a brawl.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                competitiveStartCTA
                    .padding(.horizontal, 24)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if competitiveOpen.isEmpty {
            List {
                Section {
                    competitiveStartCTA
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                }
                if !competitiveDone.isEmpty {
                    Section("Finished") {
                        ForEach(competitiveDone, id: \.id) { row in
                            competitiveRow(row).onTapGesture {
                                openCompetitiveChallengeId = row.id
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        } else {
            List {
                if !competitiveOpen.isEmpty {
                    Section("In play") {
                        ForEach(competitiveOpen, id: \.id) { row in
                            competitiveRow(row).onTapGesture {
                                openCompetitiveChallengeId = row.id
                            }
                        }
                    }
                }
                if !competitiveDone.isEmpty {
                    Section("Finished") {
                        ForEach(competitiveDone, id: \.id) { row in
                            competitiveRow(row).onTapGesture {
                                openCompetitiveChallengeId = row.id
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func competitiveRow(_ row: DataManager.CompetitiveChallengeListRow) -> some View {
        let focus = ChallengeFocus(dbKey: row.focus)
        let modeText = (row.mode == ChallengeMode.headToHead.rawValue) ? "Head to head" : "Family brawl"
        return HStack(spacing: 12) {
            Image(systemName: focus?.sfSymbol ?? "trophy.fill")
                .foregroundColor(focus?.accent ?? .miyaSecondary)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 36, height: 36)
                .background((focus?.accent ?? .miyaSecondary).opacity(0.16))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(focus?.displayName ?? "Challenge") · \(modeText)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.miyaDashboardTextPrimary)
                Text(competitiveSubtitle(row))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.miyaDashboardTextSecond)
            }
            Spacer()
            competitiveBadge(for: row)
        }
        .contentShape(Rectangle())
    }

    private func competitiveSubtitle(_ row: DataManager.CompetitiveChallengeListRow) -> String {
        switch row.status {
        case CompetitiveChallengeStatus.pendingAccepts.rawValue:
            if row.pending_count == 0 {
                return "Starting…"
            }
            return "\(row.accepted_count)/\(row.participant_count) accepted · \(row.pending_count) waiting"
        case CompetitiveChallengeStatus.active.rawValue:
            return "Mon–Sun · \(row.participant_count) competing"
        case CompetitiveChallengeStatus.completed.rawValue:
            if row.tie_break_used == true { return "Decided by tie-break" }
            return "Completed"
        case CompetitiveChallengeStatus.cancelled.rawValue:
            return "Cancelled"
        default:
            return row.status
        }
    }

    @ViewBuilder
    private func competitiveBadge(for row: DataManager.CompetitiveChallengeListRow) -> some View {
        switch row.status {
        case CompetitiveChallengeStatus.pendingAccepts.rawValue:
            Text(row.my_invite_status == "pending" ? "Action needed" : "Pending")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(row.my_invite_status == "pending" ? .miyaSecondary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill((row.my_invite_status == "pending" ? Color.miyaSecondary : Color.gray).opacity(0.16))
                )
        case CompetitiveChallengeStatus.active.rawValue:
            Text("Live")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.miyaPrimary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.miyaPrimary.opacity(0.16)))
        case CompetitiveChallengeStatus.completed.rawValue:
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.miyaPrimary)
        case CompetitiveChallengeStatus.cancelled.rawValue:
            Image(systemName: "xmark.seal.fill")
                .foregroundColor(.secondary)
        default:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func challengeList(_ list: [FamilyChallenge], emptyTitle: String, emptySubtitle: String) -> some View {
        if list.isEmpty {
            VStack(spacing: 8) {
                Text(emptyTitle)
                    .font(.headline)
                Text(emptySubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(list) { c in
                challengeRow(c)
            }
            .listStyle(.plain)
        }
    }
    
    private func challengeRow(_ c: FamilyChallenge) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(c.memberName)
                    .font(.system(size: 16, weight: .semibold))
                pillarIcon(c.pillar)
                Spacer()
                statusPill(c.status)
            }
            HStack(spacing: 4) {
                Text("Day \(c.daysEvaluated) of 7 · \(c.daysSucceeded) days hit")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            if let metric = c.sourceAlertMetric, let days = c.sourceAlertDays {
                Text("From \(metricDisplay(metric)) alert · \(days)d")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            if c.challengerCount > 1 {
                Text("\(c.challengerCount) people cheering")
                    .font(.system(size: 12))
                    .foregroundColor(.miyaPrimary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func pillarIcon(_ pillar: String) -> some View {
        let (icon, _) = pillarInfo(pillar)
        return Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundColor(.miyaPrimary)
    }
    
    private func pillarInfo(_ pillar: String) -> (String, String) {
        switch pillar.lowercased() {
        case "sleep": return ("moon.stars.fill", "Sleep")
        case "movement": return ("figure.run", "Activity")
        case "stress": return ("heart.fill", "Recovery")
        default: return ("flag.checkered", pillar.capitalized)
        }
    }
    
    private func metricDisplay(_ metric: String) -> String {
        switch metric {
        case "steps": return "Movement"
        case "movement_minutes": return "Activity"
        case "sleep_minutes", "sleep_efficiency_pct", "deep_sleep_minutes": return "Sleep"
        case "hrv_ms", "resting_hr": return "Recovery"
        default: return metric
        }
    }
    
    private func statusPill(_ status: String) -> some View {
        let label: String
        switch status {
        case "pending_invite": label = "Pending"
        case "snoozed": label = "Maybe later"
        case "active": label = "Active"
        case "completed_success": label = "Completed"
        case "completed_failed": label = "Didn't quite get there"
        default: label = status
        }
        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(status == "active" ? .miyaPrimary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill((status == "active" ? Color.miyaPrimary : Color.gray).opacity(0.15)))
    }
    
    private func loadChallenges() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        #if DEBUG
        if ScreenshotDemoData.isScreenshotModeEnabled {
            await MainActor.run {
                challenges = ScreenshotDemoData.makeDemoFamilyChallenges()
            }
            return
        }
        #endif
        do {
            let list = try await dataManager.fetchFamilyChallenges()
            await MainActor.run {
                challenges = list
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadCompetitive() async {
        do {
            let rows = try await dataManager.fetchCompetitiveChallengesForFamily()
            await MainActor.run { competitiveChallenges = rows }
        } catch {
            #if DEBUG
            print("⚠️ FamilyChallengesView: failed to load competitive challenges: \(error)")
            #endif
        }
    }

    private func loadAll() async {
        async let a: () = loadChallenges()
        async let b: () = loadCompetitive()
        _ = await (a, b)
        await applyInitialTabSelectionIfNeeded()
    }

    /// On first open, land on Competitive when there is nothing in play so members can start a challenge.
    @MainActor
    private func applyInitialTabSelectionIfNeeded() {
        guard !hasAppliedInitialTab else { return }
        hasAppliedInitialTab = true
        guard errorMessage == nil else { return }

        if !competitiveOpen.isEmpty {
            selectedTab = 1
        } else if !activeChallenges.isEmpty {
            selectedTab = 0
        } else if !myChallenges.isEmpty {
            selectedTab = 2
        } else {
            selectedTab = 1
        }
    }
}
