import SwiftUI

// AUDIT REPORT (legacy mock invite entry)
// - Compile audit: Cannot run `xcodebuild` in this environment (no Xcode). Verified compile-safety via lints/type checks in Cursor.
// - State integrity: This view is NOT the production invite flow (production uses `EnterCodeView` in `ContentView.swift`).
//   Updated to avoid inferring guided state from booleans; it now routes based on `InviteInfo.guidedSetupStatus` when present.
// - Known limitations: Uses mock `InviteInfo.mockFrom(code:)` (no DB), so status is only as accurate as the mock.

// Simple stage enum for this screen
private enum InviteFlowStage {
    case enterCode
    case welcome
}

struct InviteCodeEntryView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var inviteCode: String = ""
    @State private var errorMessage: String? = nil
    @State private var stage: InviteFlowStage = .enterCode
    @State private var activeInvite: InviteInfo? = nil
    
    // Can we press Continue on step 1?
    private var canSubmitCode: Bool {
        !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text(stage == .enterCode ? "Join a family" : "You're almost in")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text(subtitleText)
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
                
                // Main content
                Group {
                    switch stage {
                    case .enterCode:
                        enterCodeContent
                    case .welcome:
                        if let invite = activeInvite {
                            welcomeContent(invite: invite)
                        } else {
                            Text("Something went wrong. Please try again.")
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
                
                // Bottom buttons
                HStack(spacing: 12) {
                    // Back / Cancel
                    Button {
                        if stage == .welcome {
                            // Go back to code entry, keep code pre-filled
                            stage = .enterCode
                            errorMessage = nil
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text(stage == .enterCode ? "Cancel" : "Back")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.clear)
                            .foregroundColor(.miyaTextSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.miyaBackground, lineWidth: 1)
                            )
                    }
                    
                    if stage == .enterCode {
                        // CONTINUE (step 1)
                        Button {
                            handleContinue()
                        } label: {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    canSubmitCode
                                    ? Color.miyaPrimary
                                    : Color.miyaPrimary.opacity(0.5)
                                )
                                .foregroundColor(.white)
                                .cornerRadius(16)
                        }
                        .disabled(!canSubmitCode)
                        
                    } else if let invite = activeInvite {
                        // START SELF / GUIDED SETUP (step 2)
                        NavigationLink {
                            destination(for: invite)
                        } label: {
                            Text(
                                invite.onboardingType == .guided
                                ? "Start guided setup"
                                : "Start self setup"
                            )
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
    }
    
    // MARK: - Subviews
    
    private var enterCodeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invite code")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)
            
            TextField("e.g. MIYA-1234", text: $inviteCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                )
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private func welcomeContent(invite: InviteInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hey \(invite.invitedName), welcome to Miya 👋")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.miyaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Invited by \(invite.inviterName)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.miyaTextSecondary)
                
                Text("\(invite.familyName) Family")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.miyaTextSecondary)
            }
            
            Text(
                invite.onboardingType == .guided
                ? "We'll guide your setup step by step so you don't have to think about anything."
                : "You'll set yourself up in a few quick steps, then we'll keep you accountable."
            )
            .font(.system(size: 14))
            .foregroundColor(.miyaTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
        }
    }
    
    // MARK: - Logic
    
    private var subtitleText: String {
        switch stage {
        case .enterCode:
            return "Paste your invite code to join your family's health hub."
        case .welcome:
            return "You're now linked to your family. Next we'll set up how you want to use Miya."
        }
    }
    
    private func handleContinue() {
        let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter your invite code."
            return
        }
        
        if let invite = InviteInfo.mockFrom(code: trimmed) {
            errorMessage = nil
            activeInvite = invite
            stage = .welcome   // switch to welcome screen
        } else {
            errorMessage = "That code doesn't look right. Please check it and try again."
        }
    }
    
    @ViewBuilder
    private func destination(for invite: InviteInfo) -> some View {
        if invite.onboardingType == .guided {
            switch invite.guidedSetupStatus {
            case .pendingAcceptance, .none:
                GuidedSetupAcceptancePrompt(
                    memberName: invite.invitedName,
                    adminName: invite.familyName,
                    onAcceptGuidedSetup: {},
                    onFillMyself: {}
                )
            case .acceptedAwaitingData:
                GuidedWaitingForAdminView(adminName: invite.familyName)
            case .dataCompletePendingReview:
                // Legacy mock flow doesn't have InviteDetails; route to wearables as a safe default.
                WearableSelectionView(isGuidedSetupInvite: true)
            case .reviewedComplete:
                WearableSelectionView(isGuidedSetupInvite: true)
            }
        } else {
            WearableSelectionView(isGuidedSetupInvite: false)
        }
    }
}

#Preview {
    NavigationStack {
        InviteCodeEntryView()
    }
}
