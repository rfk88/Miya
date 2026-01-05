import SwiftUI

/// Consent screen for guided onboarding.
/// Shown AFTER wearables are connected in the guided flow.
struct GuidedAccountControlView: View {
    @Environment(\.dismiss) private var dismiss
    
    let familyName: String
    let isInviteFlow: Bool   // so we can keep behaviour consistent with other steps
    
    @State private var hasConsented: Bool = false
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Title + intro
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account control preferences")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Your family administrator needs your permission to help manage your health journey.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // What does this mean?
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What does this mean?")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                bullet("View your health metrics and progress")
                                bullet("Help you set and adjust health goals")
                                bullet("Manage notification preferences on your behalf")
                                bullet("Access your health data for family insights")
                            }
                        }
                        
                        // Privacy section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your privacy matters")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("You can revoke this permission at any time from your account settings. You'll maintain full control over your personal health data and can adjust sharing preferences whenever you need.")
                                .font(.system(size: 14))
                                .foregroundColor(.miyaTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        // Consent checkbox
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                hasConsented.toggle()
                            } label: {
                                Image(systemName: hasConsented ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 20))
                                    .foregroundColor(hasConsented ? .miyaPrimary : .miyaTextSecondary)
                            }
                            
                            Text("I consent to allow the family administrator to manage my account settings and access my health information as described above.")
                                .font(.system(size: 14))
                                .foregroundColor(.miyaTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 4)
                }
                
                // Buttons
                VStack(spacing: 12) {
                    // 1) Let them switch to self onboarding
                    NavigationLink {
                        AboutYouView()
                    } label: {
                        Text("Complete onboarding by myself")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.clear)
                            .foregroundColor(.miyaPrimary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.miyaPrimary, lineWidth: 1)
                            )
                    }
                    
                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Back")
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
                        
                        // 2) Continue with guided support → go to dashboard
                        NavigationLink {
                            DashboardView(familyName: familyName)
                        } label: {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    hasConsented
                                    ? Color.miyaPrimary
                                    : Color.miyaPrimary.opacity(0.5)
                                )
                                .foregroundColor(.white)
                                .cornerRadius(16)
                        }
                        .disabled(!hasConsented)
                    }
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
    }
    
    // MARK: - Helpers
    
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 14, weight: .bold))
            Text(text)
                .font(.system(size: 14))
        }
        .foregroundColor(.miyaTextSecondary)
    }
}

#Preview {
    NavigationStack {
        GuidedAccountControlView(
            familyName: "Kempton",
            isInviteFlow: true
        )
    }
}
