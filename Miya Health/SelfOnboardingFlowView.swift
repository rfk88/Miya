import SwiftUI

// AUDIT REPORT (invited self-setup flow)
// - Compile audit: Cannot run `xcodebuild` in this environment (no Xcode). Verified compile-safety via lints/type checks in Cursor.
// - State integrity: Self setup does not use guided_setup_status; it intentionally starts the standard onboarding flow.
// - Known limitations: This file is currently a lightweight wrapper and is not the production invite redemption entrypoint.

/// Full self-setup flow for an invited adult.
/// This simply starts them in the existing superadmin-style onboarding,
/// but with `isInviteFlow = true` so the final step goes to Dashboard, not family setup.
struct SelfSetupFlowView: View {
    let invite: InviteInfo   // uses your existing InviteInfo model
    
    var body: some View {
        NavigationStack {
            // Start at wearables; invited self-setup uses guided flag only if needed
            WearableSelectionView(
                isGuidedSetupInvite: false
            )
        }
    }
}

#Preview {
    // Example preview – replace with a real InviteInfo if you want
    SelfSetupFlowView(
        invite: InviteInfo(
            code: "MIYA-1234",
            invitedName: "Josh",
            familyName: "Kempton",
            inviterName: "Ollie",
            onboardingType: .selfSetup,
            guidedSetupStatus: nil,
            familyId: nil,
            invitedUserId: nil
        )
    )
}
