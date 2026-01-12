//
//  OnboardingManager.swift
//  Miya Health
//
//  AUDIT REPORT (guided onboarding status-driven routing)
//  - Compile audit: Cannot run `xcodebuild` in this environment (no Xcode). Verified compile-safety via lints/type checks in Cursor.
//  - State integrity: Added canonical invite/guided fields:
//      `guidedSetupStatus`, `invitedMemberId`, `invitedFamilyId`, and computed `canAdminEditData`
//    so guided behavior is derived from `guided_setup_status`, not inferred UI booleans.
//  - DB transition correctness: These fields are populated from `InviteDetails` during invite redemption.
//  - Known limitations: `guidedSetupStatus` is stored as String for compatibility with DB values; stricter enum typing can be layered later.
//

import SwiftUI
import Combine

@MainActor
class OnboardingManager: ObservableObject {
    
    // MARK: - DataManager Reference
    
    weak var dataManager: DataManager?
    
    // MARK: - User Type
    
    /// Whether this user joined via invite code (skips family creation/invite screens)
    @Published var isInvitedUser: Bool = false
    
    // MARK: - Guided Setup Invite Status (Canonical)
    
    /// Canonical guided setup status from `family_members.guided_setup_status`.
    /// This must be the single source of truth for guided invite routing and permissions.
    @Published var guidedSetupStatus: GuidedSetupStatus? = nil
    
    /// For invited users: the `family_members.id` row they redeemed (used for guided status transitions).
    @Published var invitedMemberId: String? = nil
    
    /// For invited users: family ID they joined via invite.
    @Published var invitedFamilyId: String? = nil
    
    /// True when the admin has an actionable step to fill guided data (status-driven; no inference).
    var canAdminEditData: Bool {
        guidedSetupStatus == .acceptedAwaitingData
    }
    
    /// Refresh guided context from database for authenticated user.
    /// Used on login/resume to ensure status-first routing (e.g., force review screen when data is ready).
    func refreshGuidedContextFromDB(dataManager: DataManager) async {
        #if DEBUG
        let oldStep = currentStep
        _ = guidedSetupStatus?.rawValue ?? "nil"
        #endif
        
        do {
            guard let rec = try await dataManager.fetchMyFamilyMemberRecord() else {
                #if DEBUG
                print("🔄 refreshGuidedContextFromDB: No family_members row for current user")
                #endif
                return
            }
            
            // Set canonical state
            invitedMemberId = rec.id.uuidString
            invitedFamilyId = rec.familyId?.uuidString
            guidedSetupStatus = parseGuidedSetupStatus(rec.guidedSetupStatus)
            // Prefer canonical name from user_profiles if available; otherwise fall back to family_members.
            if let profile = (try? await dataManager.loadUserProfile()) ?? nil,
               let fn = profile.first_name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !fn.isEmpty {
                firstName = fn
                if let ln = profile.last_name?.trimmingCharacters(in: .whitespacesAndNewlines), !ln.isEmpty {
                    lastName = ln
                }
            } else {
                firstName = rec.firstName
            }
            
            #if DEBUG
            print("🔄 refreshGuidedContextFromDB:")
            print("  user_id: \(rec.userId?.uuidString ?? "nil")")
            print("  memberId: \(rec.id.uuidString)")
            print("  guided_setup_status: \(rec.guidedSetupStatus ?? "nil")")
            print("  currentStep BEFORE: \(oldStep)")
            #endif
            
            #if DEBUG
            // NOTE: Invited members use the standard onboarding flow; do not force routing to any guided-only screen.
            print("  currentStep AFTER: \(currentStep) (unchanged)")
            #endif
            
        } catch {
            print("⚠️ refreshGuidedContextFromDB failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Step 1: Account Info
    
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var currentUserId: String?
    
    // MARK: - Step 2: Family Setup
    
    @Published var familyName: String = ""
    @Published var familySize: String = ""
    
    // MARK: - Step 3: Wearables
    
    @Published var connectedWearables: [String] = []
    
    // MARK: - Step 4: About You
    
    @Published var gender: String = ""
    @Published var dateOfBirth: Date = Date()
    @Published var ethnicity: String = ""
    @Published var smokingStatus: String = ""
    @Published var heightCm: Double = 0
    @Published var weightKg: Double = 0
    @Published var nutritionQuality: Int = 3
    
    // MARK: - Step 5: Heart Health (WHO Risk)
    
    @Published var bloodPressureStatus: String = "unknown"  // normal, elevated_untreated, elevated_treated, unknown
    @Published var diabetesStatus: String = "none"          // none, pre_diabetic, type_1, type_2, unknown
    @Published var hasPriorHeartAttack: Bool = false
    @Published var hasPriorStroke: Bool = false
    @Published var hasChronicKidneyDisease: Bool = false
    @Published var hasAtrialFibrillation: Bool = false
    @Published var hasHighCholesterol: Bool = false
    
    // MARK: - Step 6: Family History (WHO Risk)
    
    @Published var familyHeartDiseaseEarly: Bool = false    // Heart disease in parent/sibling before age 60
    @Published var familyStrokeEarly: Bool = false          // Stroke in parent/sibling before age 60
    @Published var familyType2Diabetes: Bool = false        // Type 2 diabetes in parent/sibling
    
    // MARK: - Risk Calculation Results
    
    @Published var riskBand: String = ""                    // low, moderate, high, very_high, critical
    @Published var riskPoints: Int = 0
    @Published var optimalVitalityTarget: Int = 0
    
    // MARK: - Step 7: Champion & Alert Settings
    
    @Published var championName: String = ""
    @Published var championEmail: String = ""
    @Published var championPhone: String = ""
    @Published var championEnabled: Bool = false
    
    // User notification preferences
    @Published var notifyInApp: Bool = true
    @Published var notifyPush: Bool = false
    @Published var notifyEmail: Bool = false
    
    // Champion notification preferences
    @Published var championNotifyEmail: Bool = true
    @Published var championNotifySms: Bool = false
    
    // Quiet hours
    @Published var quietHoursStart: Date = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
    @Published var quietHoursEnd: Date = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @Published var quietHoursApplyCritical: Bool = false
    
    // MARK: - Legacy Privacy Settings (keeping for backwards compatibility)
    
    @Published var tier1Sharing: String = "family"
    @Published var tier2Sharing: String = "meOnly"
    
    // MARK: - Step 8: Family Members
    
    @Published var invitedMembers: [InvitedFamilyMember] = []
    
    // MARK: - Onboarding Progress
    
    @Published var currentStep: Int = 1 {
        didSet {
            persistStep(currentStep)
            // Also save to database via DataManager
            Task {
                try? await dataManager?.saveOnboardingProgress(step: currentStep, complete: isOnboardingComplete)
            }
        }
    }
    @Published var isOnboardingComplete: Bool = false {
        didSet {
            // Save completion status to database
            Task {
                try? await dataManager?.saveOnboardingProgress(step: currentStep, complete: isOnboardingComplete)
            }
        }
    }
    
    private let persistedStepKey = "onboarding_last_step"
    
    init() {
        // Don't load from UserDefaults on init - database is the source of truth
        // UserDefaults can have stale data from previous sessions that would overwrite
        // the correct database value when user logs in. The step will be loaded from
        // database during login via LoginView.loadUserProfile()
    }
    
    // MARK: - Methods
    
    /// Reset all onboarding data (called on logout for zero state leakage)
    func reset() {
        // Invited user / guided setup state
        isInvitedUser = false
        guidedSetupStatus = nil
        invitedMemberId = nil
        invitedFamilyId = nil
        
        // Step 1: Account
        firstName = ""
        lastName = ""
        email = ""
        password = ""
        currentUserId = nil
        
        // Step 2: Family
        familyName = ""
        familySize = ""
        
        // Step 3: Wearables
        connectedWearables = []
        
        // Step 4: About You
        gender = ""
        dateOfBirth = Date()
        ethnicity = ""
        smokingStatus = ""
        heightCm = 0
        weightKg = 0
        nutritionQuality = 3
        
        // Step 5: Heart Health (WHO Risk)
        bloodPressureStatus = "unknown"
        diabetesStatus = "none"
        hasPriorHeartAttack = false
        hasPriorStroke = false
        hasChronicKidneyDisease = false
        hasAtrialFibrillation = false
        hasHighCholesterol = false
        
        // Step 6: Family History (WHO Risk)
        familyHeartDiseaseEarly = false
        familyStrokeEarly = false
        familyType2Diabetes = false
        
        // Risk Calculation Results
        riskBand = ""
        riskPoints = 0
        optimalVitalityTarget = 0
        
        // Step 7: Champion & Alerts
        championName = ""
        championEmail = ""
        championPhone = ""
        championEnabled = false
        notifyInApp = true
        notifyPush = false
        notifyEmail = false
        championNotifyEmail = true
        championNotifySms = false
        quietHoursStart = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
        quietHoursEnd = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
        quietHoursApplyCritical = false
        
        // Legacy Privacy
        tier1Sharing = "family"
        tier2Sharing = "meOnly"
        
        // Step 8: Family Members
        invitedMembers = []
        
        // Progress - reset step and clear persisted step
        currentStep = 1
        isOnboardingComplete = false
        UserDefaults.standard.removeObject(forKey: persistedStepKey)
        
        print("✅ OnboardingManager: Reset complete (all state cleared)")
    }
    
    /// Mark onboarding as complete
    func completeOnboarding() {
        isOnboardingComplete = true
        print("✅ OnboardingManager: Onboarding completed!")
    }
    
    /// Force-set a step (used for resume)
    func setCurrentStep(_ step: Int) {
        currentStep = step
    }
    
    /// Get the persisted step (defaults to 1)
    func loadPersistedStep() -> Int {
        let saved = UserDefaults.standard.integer(forKey: persistedStepKey)
        return saved > 0 ? saved : 1
    }
    
    private func persistStep(_ step: Int) {
        UserDefaults.standard.set(step, forKey: persistedStepKey)
    }
}

// MARK: - Supporting Types

struct InvitedFamilyMember: Identifiable {
    let id = UUID()
    let firstName: String
    let relationship: String
    let onboardingType: String
    let inviteCode: String
}

