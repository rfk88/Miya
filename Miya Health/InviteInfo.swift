/// MARK: - INVITE MODEL
///
/// AUDIT REPORT (guided onboarding status-driven routing)
/// - Compile audit: Cannot run `xcodebuild` in this environment (no Xcode). Verified compile-safety via lints/type checks in Cursor.
/// - State integrity: `InviteInfo` now includes the canonical `guidedSetupStatus` plus identifiers (`familyId`, `invitedUserId`)
///   so any UI that still uses this model can be migrated to status-first routing (no inferred flags).
/// - Known limitations: This file is currently used only for mock/demo invite flows (`InviteCodeEntryView` / previews).
///   Production invite redemption uses `InviteDetails` returned by `DataManager.lookupInviteCode(...)`.

import Foundation

// MARK: - ONBOARDING TYPE
enum OnboardingType {
    case selfSetup    // Full onboarding flow
    case guided       // Guided by admin
}

// MARK: - INVITE INFO MODEL
struct InviteInfo: Identifiable {
    let id = UUID()
    
    let code: String           // the invite code e.g. MIYA-1234
    let invitedName: String    // who the invite is for
    let familyName: String     // family name
    let inviterName: String    // the admin who sent it
    let onboardingType: OnboardingType
    
    // Canonical status + identifiers (optional for mock/local flows)
    let guidedSetupStatus: GuidedSetupStatus?
    let familyId: String?
    let invitedUserId: String?
}

// MARK: - TEMP MOCK LOOKUP
extension InviteInfo {
    /// Temporary mock lookup until backend is connected.
    static func mockFrom(code: String) -> InviteInfo? {
        let normalised = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        
        switch normalised {
        
        case "MIYA-1234":
            return InviteInfo(
                code: normalised,
                invitedName: "Josh",
                familyName: "Kempton",
                inviterName: "Ollie",
                onboardingType: .selfSetup,
                guidedSetupStatus: nil,
                familyId: nil,
                invitedUserId: nil
            )
            
        case "MIYA-1233":
            return InviteInfo(
                code: normalised,
                invitedName: "Sarah",
                familyName: "Kempton",
                inviterName: "Ollie",
                onboardingType: .guided,
                guidedSetupStatus: .pendingAcceptance,
                familyId: nil,
                invitedUserId: nil
            )
            
        default:
            return nil
        }
    }
}

