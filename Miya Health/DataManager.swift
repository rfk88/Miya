//
//  DataManager.swift
//  Miya Health
//
//  This handles saving and loading data from Supabase database.
//  It works with the Models we defined (Family, UserProfile, etc.)
//

import Foundation
import Combine
import Supabase

// MARK: - Data Manager

@MainActor
class DataManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    // Store the current family and user data during onboarding
    @Published var currentFamily: Family? = nil
    @Published var currentFamilyMember: FamilyMember? = nil
    
    // MARK: - Create Family (Step 2)
    
    /// Creates a new family in the database
    /// - Parameters:
    ///   - name: Family name (e.g., "The Johnson Family")
    ///   - sizeCategory: Size category ('twoToFour', 'fourToEight', 'ninePlus')
    ///   - createdBy: The user ID of the superadmin creating the family
    /// - Returns: The created Family object
    func createFamily(name: String, sizeCategory: String, createdBy: UUID) async throws -> Family {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            // Create the family record
            let newFamily = Family(
                id: nil,  // Database will generate this
                name: name,
                sizeCategory: sizeCategory,
                createdBy: createdBy,
                createdAt: nil  // Database will set this
            )
            
            // Insert into Supabase and get the created record back
            let createdFamily: Family = try await supabase
                .from("families")
                .insert(newFamily)
                .select()
                .single()
                .execute()
                .value
            
            self.currentFamily = createdFamily
            print("✅ Family created: \(createdFamily.name)")
            return createdFamily
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("❌ Create family error: \(error)")
            throw error
        }
    }
    
    // MARK: - Create Family Member
    
    /// Adds a member to a family (used for superadmin and invited members)
    /// - Parameters:
    ///   - userId: The user's auth ID (nil for pending invites)
    ///   - familyId: The family they're joining
    ///   - role: Their role ('superadmin', 'admin', 'member')
    ///   - firstName: Their first name
    ///   - relationship: Their relationship to the family (nil for superadmin)
    ///   - inviteCode: Invite code for pending members
    ///   - inviteStatus: 'pending' or 'accepted'
    ///   - onboardingType: 'Guided Setup' or 'Self Setup'
    func createFamilyMember(
        userId: UUID?,
        familyId: UUID,
        role: String,
        firstName: String,
        relationship: String? = nil,
        inviteCode: String? = nil,
        inviteStatus: String = "accepted",
        onboardingType: String? = nil
    ) async throws -> FamilyMember {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            let newMember = FamilyMember(
                id: nil,
                userId: userId,
                familyId: familyId,
                role: role,
                relationship: relationship,
                firstName: firstName,
                inviteCode: inviteCode,
                inviteStatus: inviteStatus,
                onboardingType: onboardingType,
                joinedAt: nil
            )
            
            let createdMember: FamilyMember = try await supabase
                .from("family_members")
                .insert(newMember)
                .select()
                .single()
                .execute()
                .value
            
            self.currentFamilyMember = createdMember
            print("✅ Family member created: \(createdMember.firstName)")
            return createdMember
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("❌ Create family member error: \(error)")
            throw error
        }
    }
    
    // MARK: - Save Connected Wearables (Step 3)
    
    /// Saves the wearables a user has connected
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - wearableTypes: Array of wearable type strings ('appleWatch', 'whoop', etc.)
    func saveConnectedWearables(userId: UUID, wearableTypes: [String]) async throws {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            // Create a record for each wearable
            for wearableType in wearableTypes {
                let wearable = ConnectedWearable(
                    id: nil,
                    userId: userId,
                    wearableType: wearableType,
                    isConnected: true,
                    connectedAt: nil
                )
                
                try await supabase
                    .from("connected_wearables")
                    .insert(wearable)
                    .execute()
            }
            
            print("✅ Saved \(wearableTypes.count) wearable(s)")
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("❌ Save wearables error: \(error)")
            throw error
        }
    }
    
    // MARK: - Save User Profile (Step 4)
    
    /// Saves the user's health profile
    func saveUserProfile(
        userId: UUID,
        gender: String?,
        dateOfBirth: Date?,
        ethnicity: String?,
        smokingStatus: String?,
        heightCm: Double?,
        weightKg: Double?,
        nutritionQuality: Int?
    ) async throws {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            let profile = UserProfile(
                id: nil,
                userId: userId,
                gender: gender,
                dateOfBirth: dateOfBirth,
                ethnicity: ethnicity,
                smokingStatus: smokingStatus,
                heightCm: heightCm,
                weightKg: weightKg,
                nutritionQuality: nutritionQuality,
                createdAt: nil,
                updatedAt: nil
            )
            
            try await supabase
                .from("user_profiles")
                .insert(profile)
                .execute()
            
            print("✅ User profile saved")
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("❌ Save profile error: \(error)")
            throw error
        }
    }
    
    // MARK: - Save Health Conditions (Steps 5 & 6)
    
    /// Saves the user's health conditions
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - conditions: Array of condition type strings
    ///   - sourceStep: Which step this came from ('heart_health' or 'medical_history')
    func saveHealthConditions(userId: UUID, conditions: [String], sourceStep: String) async throws {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        // Only save if there are conditions to save
        guard !conditions.isEmpty else {
            print("ℹ️ No health conditions to save for \(sourceStep)")
            return
        }
        
        do {
            for conditionType in conditions {
                let condition = HealthCondition(
                    id: nil,
                    userId: userId,
                    conditionType: conditionType,
                    sourceStep: sourceStep,
                    createdAt: nil
                )
                
                try await supabase
                    .from("health_conditions")
                    .insert(condition)
                    .execute()
            }
            
            print("✅ Saved \(conditions.count) health condition(s) for \(sourceStep)")
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("❌ Save health conditions error: \(error)")
            throw error
        }
    }
    
    // MARK: - Save Privacy Settings (Step 7)
    
    /// Saves the user's privacy preferences
    func savePrivacySettings(
        userId: UUID,
        tier1Visibility: String,
        tier2Visibility: String,
        backupContactName: String? = nil,
        backupContactPhone: String? = nil,
        backupContactEmail: String? = nil
    ) async throws {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            let settings = PrivacySettings(
                id: nil,
                userId: userId,
                tier1Visibility: tier1Visibility,
                tier2Visibility: tier2Visibility,
                backupContactName: backupContactName,
                backupContactPhone: backupContactPhone,
                backupContactEmail: backupContactEmail,
                createdAt: nil,
                updatedAt: nil
            )
            
            try await supabase
                .from("privacy_settings")
                .insert(settings)
                .execute()
            
            print("✅ Privacy settings saved")
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("❌ Save privacy settings error: \(error)")
            throw error
        }
    }
    
    // MARK: - Find Family by Invite Code
    
    /// Looks up a family member record by invite code
    /// - Parameter code: The invite code (e.g., "MIYA-AB12")
    /// - Returns: The family member record if found
    func findFamilyMemberByInviteCode(code: String) async throws -> FamilyMember? {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            let members: [FamilyMember] = try await supabase
                .from("family_members")
                .select()
                .eq("invite_code", value: code)
                .eq("invite_status", value: "pending")
                .execute()
                .value
            
            return members.first
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("❌ Find by invite code error: \(error)")
            throw error
        }
    }
}

