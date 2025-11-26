//
//  Models.swift
//  Miya Health
//
//  These are "blueprints" for our data.
//  Each struct matches a table in Supabase.
//  "Codable" means Swift can convert these to/from JSON automatically.
//

import Foundation

// MARK: - Family (matches 'families' table)

struct Family: Codable, Identifiable {
    let id: UUID?
    let name: String
    let sizeCategory: String      // 'twoToFour', 'fourToEight', 'ninePlus'
    let createdBy: UUID?
    let createdAt: Date?
    
    // This tells Swift how to convert between Swift names and database column names
    // Swift uses camelCase, but database uses snake_case
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sizeCategory = "size_category"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

// MARK: - Family Member (matches 'family_members' table)

struct FamilyMember: Codable, Identifiable {
    let id: UUID?
    let userId: UUID?
    let familyId: UUID
    let role: String              // 'superadmin', 'admin', 'member'
    let relationship: String?     // 'Partner', 'Parent', 'Child', etc.
    let firstName: String
    let inviteCode: String?
    let inviteStatus: String?     // 'pending', 'accepted'
    let onboardingType: String?   // 'Guided Setup', 'Self Setup'
    let joinedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case familyId = "family_id"
        case role
        case relationship
        case firstName = "first_name"
        case inviteCode = "invite_code"
        case inviteStatus = "invite_status"
        case onboardingType = "onboarding_type"
        case joinedAt = "joined_at"
    }
}

// MARK: - User Profile (matches 'user_profiles' table)

struct UserProfile: Codable, Identifiable {
    let id: UUID?
    let userId: UUID
    let gender: String?           // 'Male', 'Female'
    let dateOfBirth: Date?
    let ethnicity: String?        // 'White', 'Black', 'Asian', 'Hispanic', 'Other'
    let smokingStatus: String?    // 'Never', 'Former', 'Current'
    let heightCm: Double?
    let weightKg: Double?
    let nutritionQuality: Int?    // 1-5
    let createdAt: Date?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case gender
        case dateOfBirth = "date_of_birth"
        case ethnicity
        case smokingStatus = "smoking_status"
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case nutritionQuality = "nutrition_quality"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Health Condition (matches 'health_conditions' table)

struct HealthCondition: Codable, Identifiable {
    let id: UUID?
    let userId: UUID
    let conditionType: String     // 'hypertension', 'diabetes', etc.
    let sourceStep: String        // 'heart_health', 'medical_history'
    let createdAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case conditionType = "condition_type"
        case sourceStep = "source_step"
        case createdAt = "created_at"
    }
}

// MARK: - Connected Wearable (matches 'connected_wearables' table)

struct ConnectedWearable: Codable, Identifiable {
    let id: UUID?
    let userId: UUID
    let wearableType: String      // 'appleWatch', 'whoop', 'oura', 'fitbit'
    let isConnected: Bool
    let connectedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case wearableType = "wearable_type"
        case isConnected = "is_connected"
        case connectedAt = "connected_at"
    }
}

// MARK: - Privacy Settings (matches 'privacy_settings' table)

struct PrivacySettings: Codable, Identifiable {
    let id: UUID?
    let userId: UUID
    let tier1Visibility: String   // 'meOnly', 'family', 'custom'
    let tier2Visibility: String   // 'meOnly', 'custom'
    let backupContactName: String?
    let backupContactPhone: String?
    let backupContactEmail: String?
    let createdAt: Date?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case tier1Visibility = "tier1_visibility"
        case tier2Visibility = "tier2_visibility"
        case backupContactName = "backup_contact_name"
        case backupContactPhone = "backup_contact_phone"
        case backupContactEmail = "backup_contact_email"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

