import SwiftUI

/// Manual 7-day pillar challenge from Family Challenges (no linked pattern alert).
struct ManualChallengeComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: DataManager

    var onFinished: () async -> Void

    @State private var pickableMembers: [PickableMember] = []
    @State private var selectedMemberId: String?
    @State private var selectedPillar: VitalityPillar = .sleep
    @State private var isLoadingMembers = true
    @State private var isStarting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.miyaPrimary)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.miyaPrimary.opacity(0.14)))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start a 7-day focus week")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.miyaDashboardTextPrimary)
                        Text("Pick who and which lane — they’ll get the same invite as other challenges.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.miyaDashboardTextSecond)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if isLoadingMembers {
                    ProgressView("Loading family…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if pickableMembers.isEmpty {
                    Text("No onboarded family members yet. When someone joins, you can start a challenge for them here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Who")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.miyaDashboardTextSecond)
                        Picker("Member", selection: $selectedMemberId) {
                            ForEach(pickableMembers) { m in
                                Text(m.firstName).tag(Optional(m.userId))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Focus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.miyaDashboardTextSecond)
                        Picker("Pillar", selection: $selectedPillar) {
                            ForEach(VitalityPillar.allCases, id: \.self) { p in
                                Text(p.dashboardDisplayName).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    infoBlock(
                        title: "What happens",
                        body: "They get a push and in-app invite. The week uses their daily \(selectedPillar.dashboardDisplayName.lowercased()) score — same rules as challenges started from insights."
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    Task { await startChallenge() }
                } label: {
                    HStack {
                        if isStarting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isStarting ? "Starting…" : "Send challenge")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.miyaPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(isStarting || pickableMembers.isEmpty || selectedMemberId == nil)
            }
            .padding(20)
            .navigationTitle("Start challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .disabled(isStarting)
                }
            }
            .task {
                await loadMembers()
            }
        }
    }

    private func infoBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.miyaDashboardTextSecond)
            Text(body)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.miyaDashboardTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadMembers() async {
        isLoadingMembers = true
        errorMessage = nil
        defer { isLoadingMembers = false }
        guard let familyId = dataManager.currentFamilyId else {
            await MainActor.run { pickableMembers = [] }
            return
        }
        do {
            let myId = await dataManager.currentUserIdString
            let records = try await dataManager.fetchFamilyMembers(familyId: familyId)
            let filtered: [PickableMember] = records.compactMap { rec in
                guard rec.inviteStatus.lowercased() == "accepted",
                      let uid = rec.userId?.uuidString.lowercased(),
                      !uid.isEmpty else { return nil }
                if let myId, uid == myId.lowercased() { return nil }
                return PickableMember(userId: uid, firstName: rec.firstName)
            }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
            await MainActor.run {
                pickableMembers = filtered
                selectedMemberId = filtered.first?.userId
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                pickableMembers = []
            }
        }
    }

    private func startChallenge() async {
        guard let memberId = selectedMemberId else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }
        let pillarKey: String
        switch selectedPillar {
        case .sleep: pillarKey = "sleep"
        case .movement: pillarKey = "movement"
        case .stress: pillarKey = "stress"
        }
        do {
            let result = try await dataManager.createChallengeForMember(
                memberUserId: memberId,
                pillar: pillarKey,
                sourceAlertStateId: nil
            )
            if result.success {
                await onFinished()
                await MainActor.run { dismiss() }
            } else {
                await MainActor.run {
                    errorMessage = Self.friendlyMessage(for: result.error)
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func friendlyMessage(for code: String?) -> String {
        switch code?.lowercased() {
        case "active_challenge_exists":
            return "That family member already has an active, snoozed, or pending challenge. Try again when it finishes or is declined."
        case "member_not_in_same_family", "member not in same family":
            return "That person isn’t in your family anymore."
        default:
            if let code, !code.isEmpty {
                return "Couldn’t start the challenge (\(code)). Please try again."
            }
            return "Couldn’t start the challenge. Please try again."
        }
    }

    struct PickableMember: Identifiable {
        var id: String { userId }
        let userId: String
        let firstName: String
    }
}
