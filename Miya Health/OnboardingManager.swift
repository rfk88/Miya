//
//  OnboardingManager.swift
//  Miya Health
//
//  This holds ALL the data being collected during onboarding.
//  It persists across all 8 steps so data isn't lost when navigating.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Onboarding Manager

@MainActor
class OnboardingManager: ObservableObject {
    
    // MARK: - Step 1: Account
    @Published var firstName: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    
    // MARK: - Step 2: Family
    @Published var familyName: String = ""
    @Published var familySize: String? = nil  // 'twoToFour', 'fourToEight', 'ninePlus'
    
    // MARK: - Step 3: Wearables
    @Published var connectedWearables: Set<String> = []  // 'appleWatch', 'whoop', etc.
    
    // MARK: - Step 4: About You
    @Published var gender: String? = nil
    @Published var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @Published var ethnicity: String? = nil
    @Published var smokingStatus: String? = nil
    @Published var heightCm: String = ""
    @Published var weightKg: String = ""
    @Published var nutritionQuality: Int = 3
    
    // MARK: - Step 5: Heart Health
    @Published var hasHypertension: Bool = false
    @Published var hasDiabetes: Bool = false
    @Published var hasCholesterol: Bool = false
    @Published var hasPriorHeartStroke: Bool = false
    @Published var heartHealthUnsure: Bool = false
    
    // MARK: - Step 6: Medical History
    @Published var hasCKD: Bool = false
    @Published var hasAF: Bool = false
    @Published var hasFamilyHistoryHeart: Bool = false
    @Published var medicalHistoryUnsure: Bool = false
    
    // MARK: - Step 7: Privacy
    @Published var tier1Visibility: String = "family"  // 'meOnly', 'family', 'custom'
    @Published var tier2Visibility: String = "meOnly"  // 'meOnly', 'custom'
    @Published var backupContactName: String = ""
    @Published var backupContactPhone: String = ""
    
    // MARK: - Step 8: Invited Members
    @Published var invitedMembers: [InvitedMemberData] = []
    
    // MARK: - State
    @Published var currentUserId: UUID? = nil
    @Published var currentFamilyId: UUID? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    // MARK: - Helper Methods
    
    /// Get heart health conditions as array of strings
    func getHeartHealthConditions() -> [String] {
        var conditions: [String] = []
        if hasHypertension { conditions.append("hypertension") }
        if hasDiabetes { conditions.append("diabetes") }
        if hasCholesterol { conditions.append("cholesterol") }
        if hasPriorHeartStroke { conditions.append("prior_heart_stroke") }
        if heartHealthUnsure { conditions.append("heart_health_unsure") }
        return conditions
    }
    
    /// Get medical history conditions as array of strings
    func getMedicalHistoryConditions() -> [String] {
        var conditions: [String] = []
        if hasCKD { conditions.append("ckd") }
        if hasAF { conditions.append("atrial_fibrillation") }
        if hasFamilyHistoryHeart { conditions.append("family_history_heart") }
        if medicalHistoryUnsure { conditions.append("medical_history_unsure") }
        return conditions
    }
    
    /// Reset all data (for starting fresh)
    func reset() {
        firstName = ""
        email = ""
        password = ""
        familyName = ""
        familySize = nil
        connectedWearables = []
        gender = nil
        dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
        ethnicity = nil
        smokingStatus = nil
        heightCm = ""
        weightKg = ""
        nutritionQuality = 3
        hasHypertension = false
        hasDiabetes = false
        hasCholesterol = false
        hasPriorHeartStroke = false
        heartHealthUnsure = false
        hasCKD = false
        hasAF = false
        hasFamilyHistoryHeart = false
        medicalHistoryUnsure = false
        tier1Visibility = "family"
        tier2Visibility = "meOnly"
        backupContactName = ""
        backupContactPhone = ""
        invitedMembers = []
        currentUserId = nil
        currentFamilyId = nil
        isLoading = false
        errorMessage = nil
    }
}

// MARK: - Invited Member Data

struct InvitedMemberData: Identifiable {
    let id = UUID()
    let firstName: String
    let relationship: String  // 'Partner', 'Parent', etc.
    let onboardingType: String  // 'Guided Setup', 'Self Setup'
    let inviteCode: String
}

