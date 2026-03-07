import SwiftUI

// MARK: - Challenge Invite Sheet
// Shown when a member taps a challenge_invite bell notification. Accept or Maybe later.

struct ChallengeInviteSheet: View {
    let challengeId: String
    let pillar: VitalityPillar
    let senderName: String
    let dataManager: DataManager
    
    @Environment(\.dismiss) private var dismiss
    @State private var isResponding = false
    @State private var errorMessage: String?
    
    private var pillarIcon: String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.run"
        case .stress: return "heart.fill"
        }
    }
    
    private var bodyCopy: String {
        switch pillar {
        case .sleep:
            return "Small wins each night. Miya will track your progress."
        case .movement:
            return "Small steps add up. Miya will track your progress."
        case .stress:
            return "A few minutes of calm each day. Miya will track your progress."
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)
                
                Image(systemName: pillarIcon)
                    .font(.system(size: 48))
                    .foregroundStyle(Color.miyaPrimary)
                
                Text("\(senderName) started a 7-day \(pillar.displayName) challenge for you.")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text(bodyCopy)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                VStack(spacing: 12) {
                    Button {
                        acceptTapped()
                    } label: {
                        Text("Accept")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(isResponding)
                    
                    Button {
                        maybeLaterTapped()
                    } label: {
                        Text("Maybe later")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .disabled(isResponding)
                    
                    Button {
                        declineTapped()
                    } label: {
                        Text("Decline")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.red.opacity(0.9))
                    }
                    .disabled(isResponding)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                
                Spacer()
            }
            .navigationTitle("Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                        .disabled(isResponding)
                }
            }
        }
    }
    
    private func acceptTapped() {
        isResponding = true
        errorMessage = nil
        Task {
            do {
                let success = try await dataManager.respondToChallenge(challengeId: challengeId, action: "accept")
                await MainActor.run {
                    isResponding = false
                    if success { dismiss() }
                    else { errorMessage = "Something went wrong. Please try again." }
                }
            } catch {
                await MainActor.run {
                    isResponding = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func maybeLaterTapped() {
        isResponding = true
        errorMessage = nil
        Task {
            do {
                let success = try await dataManager.respondToChallenge(challengeId: challengeId, action: "snooze")
                await MainActor.run {
                    isResponding = false
                    if success { dismiss() }
                    else { errorMessage = "Something went wrong. Please try again." }
                }
            } catch {
                await MainActor.run {
                    isResponding = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func declineTapped() {
        isResponding = true
        errorMessage = nil
        Task {
            do {
                let success = try await dataManager.respondToChallenge(challengeId: challengeId, action: "decline")
                await MainActor.run {
                    isResponding = false
                    if success { dismiss() }
                    else { errorMessage = "Something went wrong. Please try again." }
                }
            } catch {
                await MainActor.run {
                    isResponding = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
