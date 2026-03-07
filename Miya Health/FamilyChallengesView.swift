import SwiftUI

// MARK: - Family Challenges View
// 3 tabs: Active (sent), My Challenges (received), Archive (completed/declined).

struct FamilyChallengesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: DataManager
    
    @State private var challenges: [FamilyChallenge] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab = 0
    @State private var activeBadgeCleared = false
    @State private var myChallengesBadgeCleared = false
    @State private var archiveBadgeCleared = false
    
    private var activeChallenges: [FamilyChallenge] {
        challenges.filter { $0.myRole == "challenger" && ["pending_invite", "active", "snoozed"].contains($0.status) }
    }
    
    private var myChallenges: [FamilyChallenge] {
        challenges.filter { $0.myRole == "challengee" && ["pending_invite", "active", "snoozed"].contains($0.status) }
    }
    
    private var archiveChallenges: [FamilyChallenge] {
        challenges.filter { ["completed_success", "completed_failed"].contains($0.status) }
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
                        
                        challengeList(myChallenges, emptyTitle: "No challenges for you", emptySubtitle: "Challenges others send you will appear here.")
                            .tabItem {
                                Label("My Challenges", systemImage: "person.fill")
                            }
                            .tag(1)
                            .onAppear { myChallengesBadgeCleared = true }
                        
                        challengeList(archiveChallenges, emptyTitle: "No archive yet", emptySubtitle: "Completed or declined challenges appear here.")
                            .tabItem {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tag(2)
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
            .task {
                await loadChallenges()
            }
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
}
