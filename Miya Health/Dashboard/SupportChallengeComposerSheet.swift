import SwiftUI

struct SupportChallengeComposerSheet: View {
    let item: FamilyNotificationItem
    let alert: ConsolidatedMemberAlert
    let presentation: AlertSupportPresentation
    let onConfirm: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isStarting = false
    @State private var errorMessage: String?

    private var pillarName: String {
        item.pillar.dashboardDisplayName
    }

    private var reason: String {
        DashboardAlertSupportPolicy.supportReason(for: item, firstName: alert.firstName)
    }

    private var inviteMessage: String {
        "Want to try a 7-day \(pillarName.lowercased()) reset together? \(presentation.challengeGoal)"
    }

    private var pillarIconName: String {
        switch item.pillar {
        case .sleep:
            return "moon.fill"
        case .movement:
            return "figure.walk"
        case .stress:
            return "sun.max.fill"
        }
    }

    private var pillarAccentColor: Color {
        switch item.pillar {
        case .sleep:
            return .miyaSleepAccent
        case .movement:
            return .miyaActivityAccent
        case .stress:
            return .miyaRecoveryAccent
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: pillarIconName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(pillarAccentColor)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(pillarAccentColor.opacity(0.14)))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start a support challenge")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.miyaDashboardTextPrimary)
                        Text("\(alert.firstName) · \(pillarName)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.miyaDashboardTextSecond)
                    }
                }

                infoBlock(title: "Why Miya suggests this", body: reason)
                infoBlock(title: "7-day goal", body: presentation.challengeGoal)
                infoBlock(title: "Invite message", body: inviteMessage)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    startChallenge()
                } label: {
                    HStack {
                        if isStarting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isStarting ? "Starting..." : "Start support challenge")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.miyaPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(isStarting)
            }
            .padding(20)
            .navigationTitle("Support challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .disabled(isStarting)
                }
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.miyaSurfaceGrey.opacity(0.55))
        )
    }

    private func startChallenge() {
        isStarting = true
        errorMessage = nil
        Task {
            let success = await onConfirm()
            await MainActor.run {
                isStarting = false
                if success {
                    dismiss()
                } else {
                    errorMessage = "Could not start this support challenge. Please try again."
                }
            }
        }
    }
}
