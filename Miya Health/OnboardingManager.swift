//
//  OnboardingManager.swift
//  Miya Health
//
//  Manages onboarding state and data collection across steps.
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
        let savedStep = UserDefaults.standard.integer(forKey: persistedStepKey)
        if savedStep > 0 {
            currentStep = savedStep
        }
    }
    
    // MARK: - Methods
    
    /// Reset all onboarding data
    func reset() {
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
        
        // Progress
        currentStep = 1
        isOnboardingComplete = false
        UserDefaults.standard.set(1, forKey: persistedStepKey)
        
        print("✅ OnboardingManager: Reset complete")
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

