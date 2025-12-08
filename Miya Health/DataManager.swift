//
//  DataManager.swift
//  Miya Health
//
//  Manages data persistence and synchronization.
//

import SwiftUI
import Combine
import Supabase
import Foundation

@MainActor
class DataManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether data is currently being loaded
    @Published var isLoading: Bool = false
    
    /// The current family data
    @Published var familyName: String?
    
    /// Family members
    @Published var familyMembers: [FamilyMemberData] = []
    
    /// Current family ID (set after family creation)
    @Published var currentFamilyId: String? {
        didSet {
            // Persist to UserDefaults whenever it changes
            if let familyId = currentFamilyId {
                UserDefaults.standard.set(familyId, forKey: "currentFamilyId")
                print("💾 DataManager: Saved currentFamilyId to UserDefaults: \(familyId)")
            } else {
                UserDefaults.standard.removeObject(forKey: "currentFamilyId")
                print("💾 DataManager: Removed currentFamilyId from UserDefaults")
            }
        }
    }
    
    // MARK: - Supabase Client
    
    private let supabase = SupabaseConfig.client
    
    // MARK: - Initialization
    
    init() {
        // Restore currentFamilyId from UserDefaults on init
        // We'll set it after initialization to avoid issues
    }
    
    /// Call this after initialization to restore persisted state
    func restorePersistedState() {
        if let savedFamilyId = UserDefaults.standard.string(forKey: "currentFamilyId") {
            // Temporarily disable didSet by using a flag, or just set it
            // Since didSet will save it again, that's fine - it ensures consistency
            currentFamilyId = savedFamilyId
            print("💾 DataManager: Restored currentFamilyId from UserDefaults: \(savedFamilyId)")
        }
    }
    
    // MARK: - Current User ID
    
    /// Get current user ID from auth session
    private var currentUserId: String? {
        get async {
            do {
                let session = try await supabase.auth.session
                return session.user.id.uuidString
            } catch {
                return nil
            }
        }
    }
    
    // MARK: - Onboarding Progress Tracking
    
    /// Save onboarding progress to database
    func saveOnboardingProgress(step: Int, complete: Bool = false) async throws {
        guard let userId = await currentUserId else {
            print("⚠️ DataManager: Cannot save onboarding progress - not authenticated")
            return
        }
        
        do {
            let data: [String: AnyJSON] = [
                "onboarding_step": .integer(step),
                "onboarding_complete": .bool(complete)
            ]
            
            try await supabase
                .from("user_profiles")
                .update(data)
                .eq("user_id", value: userId)
                .execute()
            
            print("💾 DataManager: Saved onboarding step \(step) to database")
            
        } catch {
            // Don't throw - this is a background save, we don't want to interrupt the user
            print("❌ DataManager: Failed to save onboarding progress: \(error.localizedDescription)")
        }
    }
    
    /// Load user profile and onboarding progress from database
    func loadUserProfile() async throws -> UserProfileData? {
        guard let userId = await currentUserId else {
            print("⚠️ DataManager: Cannot load user profile - not authenticated")
            return nil
        }
        
        do {
            let response: [UserProfileData] = try await supabase
                .from("user_profiles")
                .select()
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            
            if let profile = response.first {
                print("📥 DataManager: Loaded user profile from database")
                print("   - Step: \(profile.onboarding_step ?? 1)")
                print("   - Name: \(profile.first_name ?? "nil")")
                print("   - Risk Band: \(profile.risk_band ?? "nil")")
                return profile
            } else {
                print("ℹ️ DataManager: No user profile found in database")
                return nil
            }
            
        } catch {
            print("❌ DataManager: Failed to load user profile: \(error.localizedDescription)")
            throw DataError.databaseError("Failed to load user profile")
        }
    }
    
    /// Create initial minimal user profile immediately after signup
    /// This ensures onboarding_step is tracked even if user abandons before completing full profile
    /// - Parameters:
    ///   - userId: User's ID from auth
    ///   - firstName: User's first name (stored in OnboardingManager, added later via saveUserProfile)
    ///   - step: Initial onboarding step (default 1 for new signups, 2 for invited users)
    func createInitialProfile(userId: String, firstName: String, step: Int = 1) async throws {
        do {
            // Only insert bare minimum columns that exist in all database versions
            let profileData: [String: AnyJSON] = [
                "user_id": .string(userId),
                "onboarding_step": .integer(step),
                "onboarding_complete": .bool(false)
            ]
            
            try await supabase
                .from("user_profiles")
                .insert(profileData)
                .execute()
            
            print("✅ DataManager: Created initial profile for user \(userId) at step \(step)")
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Failed to create initial profile: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    // MARK: - Data Operations
    
    /// Save family information and create superadmin member record
    /// Uses UPSERT: Updates existing family if user already has one, otherwise creates new
    /// - Parameters:
    ///   - name: Family name
    ///   - size: Family size category (must match enum rawValue)
    ///   - firstName: Superadmin's first name
    func saveFamily(name: String, size: String, firstName: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        do {
            // Validate size category matches database constraint
            guard ["twoToFour", "fourToEight", "ninePlus"].contains(size) else {
                throw DataError.invalidData("Invalid family size category")
            }
            
            // Calculate max_members based on size category (for subscription tiers)
            // twoToFour = up to 4 members, fourToEight = up to 8 members, ninePlus = up to 15 members (capped)
            let maxMembers: Int
            switch size {
            case "twoToFour": maxMembers = 4
            case "fourToEight": maxMembers = 8
            case "ninePlus": maxMembers = 15  // Capped at 15, not unlimited
            default: maxMembers = 4
            }
            
            // Check if user already has a family
            let existingFamilies: [FamilyRecord] = try await supabase
                .from("families")
                .select()
                .eq("created_by", value: userId)
                .execute()
                .value
            
            let familyId: String
            
            if let existingFamily = existingFamilies.first {
                // UPDATE existing family
                familyId = existingFamily.id.uuidString
                
                let updateData: [String: AnyJSON] = [
                    "name": .string(name),
                    "size_category": .string(size),
                    "max_members": .integer(maxMembers)
                ]
                
                try await supabase
                    .from("families")
                    .update(updateData)
                    .eq("id", value: familyId)
                    .execute()
                
                print("✅ DataManager: Family '\(name)' updated with ID: \(familyId)")
                
            } else {
                // INSERT new family
                let insertData: [String: AnyJSON] = [
                    "name": .string(name),
                    "size_category": .string(size),
                    "max_members": .integer(maxMembers),
                    "created_by": .string(userId)
                ]
                
                let familyResponse: [FamilyRecord] = try await supabase
                    .from("families")
                    .insert(insertData)
                    .select()
                    .execute()
                    .value
                
                guard let family = familyResponse.first else {
                    throw DataError.databaseError("Failed to create family")
                }
                
                familyId = family.id.uuidString
                
                // Create superadmin member record (only for new families)
                let memberData: [String: AnyJSON] = [
                    "user_id": .string(userId),
                    "family_id": .string(familyId),
                    "role": .string("superadmin"),
                    "first_name": .string(firstName),
                    "invite_status": .string("accepted")
                ]
                
                try await supabase
                    .from("family_members")
                    .insert(memberData)
                    .execute()
                
                print("✅ DataManager: Family '\(name)' created with ID: \(familyId)")
            }
            
            // Update local state
            currentFamilyId = familyId
            familyName = name
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save family error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Save connected wearable device
    /// - Parameter wearableType: Type of wearable (must match enum rawValue)
    func saveWearable(wearableType: String) async throws {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        do {
            // Validate wearable type matches database constraint
            guard ["appleWatch", "whoop", "oura", "fitbit"].contains(wearableType) else {
                throw DataError.invalidData("Invalid wearable type")
            }
            
            // Use upsert to handle duplicates (per schema unique constraint)
            let wearableData: [String: AnyJSON] = [
                "user_id": .string(userId),
                "wearable_type": .string(wearableType),
                "is_connected": .bool(true)
            ]
            try await supabase
                .from("connected_wearables")
                .upsert(wearableData, onConflict: "user_id,wearable_type")
                .execute()
            
            print("✅ DataManager: Wearable '\(wearableType)' saved")
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save wearable error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Save user profile data from Step 4
    /// - Parameters:
    ///   - gender: User's gender
    ///   - dateOfBirth: User's date of birth
    ///   - ethnicity: User's ethnicity
    ///   - smokingStatus: User's smoking status (Never, Former, Current)
    ///   - heightCm: Height in centimeters
    ///   - weightKg: Weight in kilograms
    ///   - nutritionQuality: Nutrition quality rating (1-5)
    ///   - bloodPressureStatus: BP status (normal, elevated_untreated, elevated_treated, unknown)
    ///   - diabetesStatus: Diabetes status (none, pre_diabetic, type_1, type_2, unknown)
    ///   - hasPriorHeartAttack: Has had a heart attack
    ///   - hasPriorStroke: Has had a stroke
    ///   - familyHeartDiseaseEarly: Family history of heart disease before age 60
    ///   - familyStrokeEarly: Family history of stroke before age 60
    ///   - familyType2Diabetes: Family history of Type 2 diabetes
    func saveUserProfile(
        lastName: String? = nil,
        gender: String?,
        dateOfBirth: Date?,
        ethnicity: String?,
        smokingStatus: String?,
        heightCm: Double?,
        weightKg: Double?,
        nutritionQuality: Int?,
        bloodPressureStatus: String? = nil,
        diabetesStatus: String? = nil,
        hasPriorHeartAttack: Bool? = nil,
        hasPriorStroke: Bool? = nil,
        familyHeartDiseaseEarly: Bool? = nil,
        familyStrokeEarly: Bool? = nil,
        familyType2Diabetes: Bool? = nil,
        onboardingStep: Int? = nil
    ) async throws {
        guard let userId = await currentUserId else {
            print("❌ DataManager: saveUserProfile - No user ID found (not authenticated)")
            throw DataError.notAuthenticated
        }
        
        print("🔄 DataManager: saveUserProfile called for user \(userId)")
        
        do {
            // Validate enum values
            if let gender = gender, !["Male", "Female"].contains(gender) {
                print("❌ DataManager: Validation failed - Invalid gender: \(gender)")
                throw DataError.invalidData("Invalid gender value: \(gender)")
            }
            
            // Validate ethnicity (simplified)
            let validEthnicities = ["White", "Asian", "Black", "Hispanic", "Other"]
            if let ethnicity = ethnicity, !validEthnicities.contains(ethnicity) {
                print("❌ DataManager: Validation failed - Invalid ethnicity: \(ethnicity ?? "nil")")
                throw DataError.invalidData("Invalid ethnicity value: \(ethnicity ?? "nil")")
            }
            
            // Validate smoking status (simplified for WHO: Never, Former, Current)
            let validSmokingStatuses = ["Never", "Former", "Current"]
            if let smokingStatus = smokingStatus, !validSmokingStatuses.contains(smokingStatus) {
                print("❌ DataManager: Validation failed - Invalid smoking status: \(smokingStatus)")
                throw DataError.invalidData("Invalid smoking status value: \(smokingStatus)")
            }
            
            // Validate blood pressure status
            let validBPStatuses = ["normal", "elevated_untreated", "elevated_treated", "unknown"]
            if let bpStatus = bloodPressureStatus, !validBPStatuses.contains(bpStatus) {
                print("❌ DataManager: Validation failed - Invalid BP status: \(bpStatus)")
                throw DataError.invalidData("Invalid blood pressure status value: \(bpStatus)")
            }
            
            // Validate diabetes status
            let validDiabetesStatuses = ["none", "pre_diabetic", "type_1", "type_2", "unknown"]
            if let diabStatus = diabetesStatus, !validDiabetesStatuses.contains(diabStatus) {
                print("❌ DataManager: Validation failed - Invalid diabetes status: \(diabStatus)")
                throw DataError.invalidData("Invalid diabetes status value: \(diabStatus)")
            }
            
            if let nutritionQuality = nutritionQuality, nutritionQuality < 1 || nutritionQuality > 5 {
                throw DataError.invalidData("Nutrition quality must be between 1 and 5")
            }
            
            // Format date for PostgreSQL DATE type
            var dateString: String? = nil
            if let date = dateOfBirth {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                dateString = formatter.string(from: date)
            }
            
            // Build profile data dictionary
            var profileData: [String: AnyJSON] = [
                "user_id": .string(userId)
            ]
            
            if let lastName = lastName, !lastName.isEmpty { profileData["last_name"] = .string(lastName) }
            if let gender = gender { profileData["gender"] = .string(gender) }
            if let dateString = dateString { profileData["date_of_birth"] = .string(dateString) }
            if let ethnicity = ethnicity { profileData["ethnicity"] = .string(ethnicity) }
            if let smokingStatus = smokingStatus { profileData["smoking_status"] = .string(smokingStatus) }
            if let heightCm = heightCm { profileData["height_cm"] = .double(heightCm) }
            if let weightKg = weightKg { profileData["weight_kg"] = .double(weightKg) }
            if let nutritionQuality = nutritionQuality { profileData["nutrition_quality"] = .integer(nutritionQuality) }
            
            // WHO Risk fields
            if let bpStatus = bloodPressureStatus { profileData["blood_pressure_status"] = .string(bpStatus) }
            if let diabStatus = diabetesStatus { profileData["diabetes_status"] = .string(diabStatus) }
            if let heartAttack = hasPriorHeartAttack { profileData["has_prior_heart_attack"] = .bool(heartAttack) }
            if let stroke = hasPriorStroke { profileData["has_prior_stroke"] = .bool(stroke) }
            if let familyHeart = familyHeartDiseaseEarly { profileData["family_heart_disease_early"] = .bool(familyHeart) }
            if let familyStroke = familyStrokeEarly { profileData["family_stroke_early"] = .bool(familyStroke) }
            if let familyDiabetes = familyType2Diabetes { profileData["family_type2_diabetes"] = .bool(familyDiabetes) }
            
            // Onboarding progress
            if let step = onboardingStep { profileData["onboarding_step"] = .integer(step) }
            
            // ALWAYS UPDATE (profile was created on signup via createInitialProfile)
            // Remove user_id from update data since it's used in the WHERE clause
            profileData.removeValue(forKey: "user_id")
            
            try await supabase
                .from("user_profiles")
                .update(profileData)
                .eq("user_id", value: userId)
                .execute()
            
            print("✅ DataManager: User profile UPDATED for user \(userId)")
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save profile error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Save health conditions from Step 5 (Heart Health) or Step 6 (Medical History)
    /// - Parameters:
    ///   - conditions: Dictionary mapping condition type to boolean
    ///   - sourceStep: Either "heart_health" or "medical_history"
    func saveHealthConditions(conditions: [String: Bool], sourceStep: String) async throws {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        guard ["heart_health", "medical_history"].contains(sourceStep) else {
            throw DataError.invalidData("Invalid source step")
        }
        
        do {
            print("📝 DataManager: Saving health conditions for \(sourceStep)")
            print("   User ID: \(userId)")
            print("   Conditions: \(conditions)")
            
            // First, delete ALL existing conditions for this source step
            print("   Deleting existing conditions for source_step: \(sourceStep)...")
            try await supabase
                .from("health_conditions")
                .delete()
                .eq("user_id", value: userId)
                .eq("source_step", value: sourceStep)
                .execute()
            print("   ✅ Delete successful")
            
            // Build condition records for selected conditions
            var conditionRecords: [[String: AnyJSON]] = []
            
            for (conditionType, isSelected) in conditions where isSelected {
                print("   Adding condition: \(conditionType)")
                conditionRecords.append([
                    "user_id": .string(userId),
                    "condition_type": .string(conditionType),
                    "source_step": .string(sourceStep)
                ])
            }
            
            // Insert selected conditions
            if !conditionRecords.isEmpty {
                print("   Inserting \(conditionRecords.count) conditions...")
                try await supabase
                    .from("health_conditions")
                    .insert(conditionRecords)
                    .execute()
                print("   ✅ Insert successful")
            } else {
                print("   No conditions to insert (all false)")
            }
            
            print("✅ DataManager: Health conditions saved for \(sourceStep)")
            
        } catch {
            print("❌ DataManager: Save health conditions FAILED")
            print("   Error: \(error)")
            print("   Localized: \(error.localizedDescription)")
            let userMessage = mapDataError(error)
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Save privacy settings from Step 7
    /// - Parameters:
    ///   - tier1Visibility: Tier 1 sharing option
    ///   - tier2Visibility: Tier 2 sharing option
    ///   - backupContactName: Optional backup contact name
    ///   - backupContactPhone: Optional backup contact phone
    ///   - backupContactEmail: Optional backup contact email
    func savePrivacySettings(
        tier1Visibility: String,
        tier2Visibility: String,
        backupContactName: String? = nil,
        backupContactPhone: String? = nil,
        backupContactEmail: String? = nil
    ) async throws {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        do {
            // Validate enum values
            guard ["meOnly", "family", "custom"].contains(tier1Visibility) else {
                throw DataError.invalidData("Invalid tier1 visibility value")
            }
            
            guard ["meOnly", "custom"].contains(tier2Visibility) else {
                throw DataError.invalidData("Invalid tier2 visibility value")
            }
            
            var privacyData: [String: AnyJSON] = [
                "user_id": .string(userId),
                "tier1_visibility": .string(tier1Visibility),
                "tier2_visibility": .string(tier2Visibility)
            ]
            
            if let name = backupContactName { privacyData["backup_contact_name"] = .string(name) }
            if let phone = backupContactPhone { privacyData["backup_contact_phone"] = .string(phone) }
            if let email = backupContactEmail { privacyData["backup_contact_email"] = .string(email) }
            
            // Use upsert for privacy settings (ON CONFLICT user_id DO UPDATE)
            try await supabase
                .from("privacy_settings")
                .upsert(privacyData, onConflict: "user_id")
                .execute()
            
            print("✅ DataManager: Privacy settings saved")
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save privacy settings error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    // MARK: - WHO Risk Functions
    
    /// Save calculated risk assessment to user profile
    /// - Parameters:
    ///   - riskBand: Risk band (low, moderate, high, very_high, critical)
    ///   - riskPoints: Total risk points calculated
    ///   - optimalTarget: Optimal vitality target score
    func saveRiskAssessment(riskBand: String, riskPoints: Int, optimalTarget: Int) async throws {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        do {
            // Validate risk band
            guard ["low", "moderate", "high", "very_high", "critical"].contains(riskBand) else {
                throw DataError.invalidData("Invalid risk band value")
            }
            
            let riskData: [String: AnyJSON] = [
                "risk_band": .string(riskBand),
                "risk_points": .integer(riskPoints),
                "optimal_vitality_target": .integer(optimalTarget),
                "risk_calculated_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            
            try await supabase
                .from("user_profiles")
                .update(riskData)
                .eq("user_id", value: userId)
                .execute()
            
            print("✅ DataManager: Risk assessment saved - Band: \(riskBand), Points: \(riskPoints)")
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save risk assessment error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Save daily vitality scores (batch upsert)
    /// - Parameter scores: Array of daily scores with date, total, components
    func saveVitalityScores(_ scores: [(date: Date, total: Int, sleep: Int, movement: Int, stress: Int, source: String)]) async throws {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        // Validate source
        let validSources = ["csv", "wearable", "manual"]
        
        // Prepare rows
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        let payload: [[String: AnyJSON]] = scores.map { row in
            let sourceValue = validSources.contains(row.source) ? row.source : "csv"
            return [
                "user_id": .string(userId),
                "score_date": .string(dateFormatter.string(from: row.date)),
                "total_score": .integer(row.total),
                "sleep_points": .integer(row.sleep),
                "movement_points": .integer(row.movement),
                "stress_points": .integer(row.stress),
                "source": .string(sourceValue)
            ]
        }
        
        do {
            try await supabase
                .from("vitality_scores")
                .upsert(payload, onConflict: "user_id,score_date")
                .execute()
            
            // Update snapshot with the latest score_date
            if let latest = scores.max(by: { $0.date < $1.date }) {
                let snapshotData: [String: AnyJSON] = [
                    "vitality_score_current": .integer(latest.total),
                    "vitality_score_source": .string(validSources.contains(latest.source) ? latest.source : "csv"),
                    "vitality_score_updated_at": .string(ISO8601DateFormatter().string(from: latest.date))
                ]
                try await supabase
                    .from("user_profiles")
                    .update(snapshotData)
                    .eq("user_id", value: userId)
                    .execute()
            }
            
            print("✅ DataManager: Vitality scores saved (batch size: \(scores.count))")
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save vitality scores error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Save champion (health advocate) settings
    /// - Parameters:
    ///   - name: Champion's name
    ///   - email: Champion's email
    ///   - phone: Champion's phone
    ///   - enabled: Whether champion notifications are enabled
    func saveChampionSettings(name: String?, email: String?, phone: String?, enabled: Bool) async throws {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        do {
            var championData: [String: AnyJSON] = [
                "champion_enabled": .bool(enabled)
            ]
            
            if let name = name { championData["champion_name"] = .string(name) }
            if let email = email { championData["champion_email"] = .string(email) }
            if let phone = phone { championData["champion_phone"] = .string(phone) }
            
            try await supabase
                .from("user_profiles")
                .update(championData)
                .eq("user_id", value: userId)
                .execute()
            
            print("✅ DataManager: Champion settings saved - Enabled: \(enabled)")
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save champion settings error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Save alert/notification preferences
    /// - Parameters:
    ///   - notifyInApp: Enable in-app notifications
    ///   - notifyPush: Enable push notifications
    ///   - notifyEmail: Enable email notifications
    ///   - championEmail: Enable champion email alerts
    ///   - championSms: Enable champion SMS alerts
    ///   - quietStart: Quiet hours start time (HH:mm format)
    ///   - quietEnd: Quiet hours end time (HH:mm format)
    ///   - quietApplyCritical: Apply quiet hours to critical alerts
    func saveAlertPreferences(
        notifyInApp: Bool,
        notifyPush: Bool,
        notifyEmail: Bool,
        championEmail: Bool,
        championSms: Bool,
        quietStart: String,
        quietEnd: String,
        quietApplyCritical: Bool
    ) async throws {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        do {
            let alertData: [String: AnyJSON] = [
                "notify_inapp": .bool(notifyInApp),
                "notify_push": .bool(notifyPush),
                "notify_email": .bool(notifyEmail),
                "champion_notify_email": .bool(championEmail),
                "champion_notify_sms": .bool(championSms),
                "quiet_hours_start": .string(quietStart),
                "quiet_hours_end": .string(quietEnd),
                "quiet_hours_apply_critical": .bool(quietApplyCritical)
            ]
            
            try await supabase
                .from("user_profiles")
                .update(alertData)
                .eq("user_id", value: userId)
                .execute()
            
            print("✅ DataManager: Alert preferences saved")
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save alert preferences error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Set baseline start date when wearable is connected
    func setBaselineStartDate() async throws {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        do {
            let baselineData: [String: AnyJSON] = [
                "baseline_start_date": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            
            try await supabase
                .from("user_profiles")
                .update(baselineData)
                .eq("user_id", value: userId)
                .execute()
            
            print("✅ DataManager: Baseline start date set")
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Set baseline date error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Update family member alert level
    /// - Parameters:
    ///   - memberId: Family member record ID
    ///   - alertLevel: Alert level (full, day14_plus, dashboard_only)
    func updateMemberAlertLevel(memberId: String, alertLevel: String) async throws {
        do {
            guard ["full", "day14_plus", "dashboard_only"].contains(alertLevel) else {
                throw DataError.invalidData("Invalid alert level")
            }
            
            let updateData: [String: AnyJSON] = [
                "alert_level": .string(alertLevel)
            ]
            
            try await supabase
                .from("family_members")
                .update(updateData)
                .eq("id", value: memberId)
                .execute()
            
            print("✅ DataManager: Member alert level updated to \(alertLevel)")
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Update member alert level error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Generate a unique invite code
    /// - Returns: Unique invite code in format "MIYA-XXXX"
    func generateInviteCode() async throws -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var attempts = 0
        let maxAttempts = 5
        
        while attempts < maxAttempts {
            // Generate random code
            let randomCode = String((0..<4).compactMap { _ in characters.randomElement() })
            let inviteCode = "MIYA-\(randomCode)"
            
            // Check if code already exists
            let existing: [FamilyMemberRecord] = try await supabase
                .from("family_members")
                .select()
                .eq("invite_code", value: inviteCode)
                .execute()
                .value
            
            if existing.isEmpty {
                return inviteCode
            }
            
            attempts += 1
        }
        
        throw DataError.databaseError("Failed to generate unique invite code after \(maxAttempts) attempts")
    }
    
    /// Save family member invitation
    /// - Parameters:
    ///   - firstName: Member's first name
    ///   - relationship: Relationship to family (must match enum rawValue)
    ///   - onboardingType: Onboarding type (must match enum rawValue)
    /// - Returns: Generated invite code
    func saveFamilyMemberInvite(
        firstName: String,
        relationship: String,
        onboardingType: String
    ) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        // Get family ID - should be set from UserDefaults on init
        var resolvedFamilyId = currentFamilyId
        
        // If not set, try to fetch it
        if resolvedFamilyId == nil {
            print("⚠️ DataManager: currentFamilyId is nil, fetching from database...")
            
            let families: [FamilyRecord] = try await supabase
                .from("families")
                .select()
                .eq("created_by", value: userId)
                .execute()
                .value
            
            if let family = families.first {
                resolvedFamilyId = family.id.uuidString
                currentFamilyId = resolvedFamilyId
                familyName = family.name
                print("✅ DataManager: Found family: \(family.name) (\(resolvedFamilyId ?? ""))")
            } else {
                print("❌ DataManager: No family found for user \(userId)")
                throw DataError.databaseError("No family found. Please create a family first.")
            }
        }
        
        guard let familyId = resolvedFamilyId else {
            throw DataError.databaseError("No family found. Please create a family first.")
        }
        
        do {
            // Validate enum values
            guard ["Partner", "Parent", "Child", "Sibling", "Grandparent", "Other"].contains(relationship) else {
                throw DataError.invalidData("Invalid relationship value")
            }
            
            guard ["Guided Setup", "Self Setup"].contains(onboardingType) else {
                throw DataError.invalidData("Invalid onboarding type value")
            }
            
            // Generate unique invite code
            let inviteCode = try await generateInviteCode()
            
            print("📝 DataManager: Inserting family member invite with family_id: \(familyId)")
            
            // Insert family member with pending status
            let insertData: [String: AnyJSON] = [
                "family_id": .string(familyId),
                "first_name": .string(firstName),
                "relationship": .string(relationship),
                "onboarding_type": .string(onboardingType),
                "invite_code": .string(inviteCode),
                "invite_status": .string("pending"),
                "role": .string("member")
            ]
            
            print("📝 DataManager: Insert data: \(insertData)")
            
            try await supabase
                .from("family_members")
                .insert(insertData)
                .execute()
            
            print("✅ DataManager: Family member invite saved successfully!")
            print("   - Name: \(firstName)")
            print("   - Relationship: \(relationship)")
            print("   - Onboarding: \(onboardingType)")
            print("   - Code: \(inviteCode)")
            print("   - Family ID: \(familyId)")
            
            return inviteCode
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save family member invite error: \(error)")
            print("   Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("   Domain: \(nsError.domain), Code: \(nsError.code)")
                print("   UserInfo: \(nsError.userInfo)")
            }
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Save a new family member invite and return both invite code and member ID
    /// Used when admin needs to fill out guided data immediately
    func saveFamilyMemberInviteWithId(
        firstName: String,
        relationship: String,
        onboardingType: String,
        guidedSetupStatus: String? = nil
    ) async throws -> (inviteCode: String, memberId: String) {
        isLoading = true
        defer { isLoading = false }
        
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        // Get family ID
        var resolvedFamilyId = currentFamilyId
        
        if resolvedFamilyId == nil {
            let families: [FamilyRecord] = try await supabase
                .from("families")
                .select()
                .eq("created_by", value: userId)
                .execute()
                .value
            
            if let family = families.first {
                resolvedFamilyId = family.id.uuidString
                currentFamilyId = resolvedFamilyId
            }
        }
        
        guard let familyId = resolvedFamilyId else {
            throw DataError.databaseError("No family found. Please create a family first.")
        }
        
        do {
            // Generate unique invite code
            let inviteCode = try await generateInviteCode()
            
            // Build insert data - DO NOT include guided_setup_status (column may not exist yet)
            // The guided_setup_status will be set via separate update if needed
            let insertData: [String: AnyJSON] = [
                "family_id": .string(familyId),
                "first_name": .string(firstName),
                "relationship": .string(relationship),
                "onboarding_type": .string(onboardingType),
                "invite_code": .string(inviteCode),
                "invite_status": .string("pending"),
                "role": .string("member")
            ]
            
            // Insert and get the ID back
            struct InsertResponse: Codable {
                let id: UUID
            }
            
            let response: [InsertResponse] = try await supabase
                .from("family_members")
                .insert(insertData)
                .select("id")
                .execute()
                .value
            
            guard let memberId = response.first?.id.uuidString else {
                throw DataError.databaseError("Failed to get member ID after insert")
            }
            
            print("✅ DataManager: Family member invite saved with ID: \(memberId)")
            
            // Try to set guided_setup_status if provided (may fail if column doesn't exist - that's OK)
            if let status = guidedSetupStatus {
                do {
                    try await updateGuidedSetupStatus(memberId: memberId, status: status)
                } catch {
                    // Silently ignore - column may not exist yet
                    print("⚠️ DataManager: Could not set guided_setup_status (migration may not be run)")
                }
            }
            
            return (inviteCode, memberId)
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save family member invite error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    // MARK: - Invite Code Redemption
    
    /// Look up an invite code and return the invitation details
    /// - Parameter code: The invite code (e.g., "MIYA-AB12")
    /// - Returns: InviteDetails containing family name, first name, and onboarding type
    func lookupInviteCode(code: String) async throws -> InviteDetails {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Look up the invite code in family_members
            let invites: [FamilyMemberRecord] = try await supabase
                .from("family_members")
                .select()
                .eq("invite_code", value: code.uppercased())
                .execute()
                .value
            
            guard let invite = invites.first else {
                throw DataError.invalidData("Invalid invite code. Please check and try again.")
            }
            
            // Check if already redeemed
            if invite.inviteStatus == "accepted" {
                throw DataError.invalidData("This invite code has already been used.")
            }
            
            // Check if user_id is already set (shouldn't happen if status is pending, but safety check)
            if invite.userId != nil {
                throw DataError.invalidData("This invite has already been claimed.")
            }
            
            // Note: We NO LONGER block guided setup invites without data.
            // User can accept the invite and admin fills data later.
            
            // Fetch the family name
            guard let familyId = invite.familyId else {
                throw DataError.databaseError("Invalid invitation - no family associated.")
            }
            
            let families: [FamilyRecord] = try await supabase
                .from("families")
                .select()
                .eq("id", value: familyId.uuidString)
                .execute()
                .value
            
            guard let family = families.first else {
                throw DataError.databaseError("Family not found for this invitation.")
            }
            
            print("✅ DataManager: Found valid invite for '\(invite.firstName)' to join '\(family.name)'")
            
            let hasGuidedData = invite.guidedDataComplete ?? false
            
            return InviteDetails(
                inviteId: invite.id.uuidString,
                familyId: familyId.uuidString,
                familyName: family.name,
                firstName: invite.firstName,
                relationship: invite.relationship ?? "",
                onboardingType: invite.onboardingType ?? "Self Setup",
                isGuidedSetup: invite.onboardingType == "Guided Setup",
                guidedSetupStatus: invite.guidedSetupStatus,
                hasGuidedData: hasGuidedData
            )
            
        } catch let error as DataError {
            throw error
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Lookup invite code error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Complete the invite redemption by linking the new user to the family
    /// - Parameters:
    ///   - code: The invite code
    ///   - userId: The newly created user's ID
    func completeInviteRedemption(code: String, userId: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Update the family_members record
            let updateData: [String: AnyJSON] = [
                "user_id": .string(userId),
                "invite_status": .string("accepted")
            ]
            
            try await supabase
                .from("family_members")
                .update(updateData)
                .eq("invite_code", value: code.uppercased())
                .execute()
            
            // Fetch and set the family info for this session
            let invites: [FamilyMemberRecord] = try await supabase
                .from("family_members")
                .select()
                .eq("invite_code", value: code.uppercased())
                .execute()
                .value
            
            if let invite = invites.first, let familyId = invite.familyId {
                currentFamilyId = familyId.uuidString
                
                // Fetch family name
                let families: [FamilyRecord] = try await supabase
                    .from("families")
                    .select()
                    .eq("id", value: familyId.uuidString)
                    .execute()
                    .value
                
                if let family = families.first {
                    familyName = family.name
                }
            }
            
            print("✅ DataManager: Invite redeemed successfully for user \(userId)")
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Complete invite redemption error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Add a family member (local state)
    func addFamilyMember(_ member: FamilyMemberData) {
        familyMembers.append(member)
        print("✅ DataManager: Added family member '\(member.firstName)'")
    }
    
    // MARK: - Guided Setup Functions
    
    /// Load guided health data for a specific family member
    /// - Parameter memberId: The family_members record ID
    /// - Returns: Decoded guided health data or nil if not found/empty
    func loadGuidedHealthData(memberId: String) async throws -> GuidedHealthData? {
        do {
            struct GuidedDataRow: Decodable {
                let guided_health_data: GuidedHealthDataJSON?
            }
            
            let response: [GuidedDataRow] = try await supabase
                .from("family_members")
                .select("guided_health_data")
                .eq("id", value: memberId)
                .limit(1)
                .execute()
                .value
            
            if let row = response.first, let jsonData = row.guided_health_data {
                print("📥 DataManager: Loaded guided health data for member \(memberId)")
                return GuidedHealthData(from: jsonData)
            } else {
                print("ℹ️ DataManager: No guided health data found for member \(memberId)")
                return nil
            }
            
        } catch {
            print("❌ DataManager: Failed to load guided health data: \(error.localizedDescription)")
            throw DataError.databaseError("Failed to load guided health data")
        }
    }
    
    /// Save guided health data entered by superadmin
    /// - Parameters:
    ///   - memberId: The family_members record ID
    ///   - healthData: The health data to save
    func saveGuidedHealthData(memberId: String, healthData: GuidedHealthData) async throws {
        do {
            // Convert to JSON structure (AnyJSON)
            let jsonData = healthData.toJSON()
            
            let updateData: [String: AnyJSON] = [
                "guided_health_data": .object(jsonData),
                "guided_data_complete": .bool(true)
            ]
            
            try await supabase
                .from("family_members")
                .update(updateData)
                .eq("id", value: memberId)
                .execute()
            
            print("✅ DataManager: Guided health data saved for member \(memberId)")
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Failed to save guided health data: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Update guided setup status for a family member
    /// - Parameters:
    ///   - memberId: The family_members record ID
    ///   - status: New status value
    /// - Note: This function may fail silently if the guided_setup_status column doesn't exist
    func updateGuidedSetupStatus(memberId: String, status: String) async throws {
        do {
            // Try simple update first (just the status)
            let updateData: [String: AnyJSON] = [
                "guided_setup_status": .string(status)
            ]
            
            try await supabase
                .from("family_members")
                .update(updateData)
                .eq("id", value: memberId)
                .execute()
            
            print("✅ DataManager: Updated guided setup status to '\(status)' for member \(memberId)")
            
            // Try to update timestamps (may fail if columns don't exist)
            if status == "data_complete_pending_review" || status == "reviewed_complete" {
                let now = ISO8601DateFormatter().string(from: Date())
                let timestampField = status == "data_complete_pending_review" ? "guided_data_filled_at" : "guided_data_reviewed_at"
                
                do {
                    try await supabase
                        .from("family_members")
                        .update([timestampField: AnyJSON.string(now)])
                        .eq("id", value: memberId)
                        .execute()
                } catch {
                    // Silently ignore timestamp update failures
                    print("⚠️ DataManager: Could not set timestamp \(timestampField)")
                }
            }
            
        } catch {
            print("❌ DataManager: Failed to update guided setup status: \(error.localizedDescription)")
            throw error  // Re-throw so caller knows it failed
        }
    }
    
    /// Get family members waiting for guided data entry
    /// - Parameter familyId: The family ID
    /// - Returns: Array of members with status 'accepted_awaiting_data'
    /// - Note: Returns empty array if guided_setup_status column doesn't exist
    func getPendingGuidedSetups(familyId: String) async throws -> [FamilyMemberRecord] {
        do {
            let members: [FamilyMemberRecord] = try await supabase
                .from("family_members")
                .select()
                .eq("family_id", value: familyId)
                .eq("guided_setup_status", value: "accepted_awaiting_data")
                .execute()
                .value
            
            print("📥 DataManager: Found \(members.count) members awaiting guided data entry")
            return members
            
        } catch {
            // If the column doesn't exist, just return empty array
            print("⚠️ DataManager: Could not query pending guided setups (column may not exist): \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch pending family invites (invite_status = pending) for display in the add-member screen
    func fetchPendingFamilyInvites(familyId: String) async throws -> [FamilyMemberRecord] {
        do {
            let members: [FamilyMemberRecord] = try await supabase
                .from("family_members")
                .select()
                .eq("family_id", value: familyId)
                .eq("invite_status", value: "pending")
                .execute()
                .value
            
            print("📥 DataManager: Found \(members.count) pending family invites")
            return members
        } catch {
            print("❌ DataManager: Failed to fetch pending invites: \(error.localizedDescription)")
            throw DataError.databaseError("Failed to load pending invites")
        }
    }
    
    /// User confirms their guided data after review
    /// - Parameter memberId: The family_members record ID
    func confirmGuidedDataReview(memberId: String) async throws {
        try await updateGuidedSetupStatus(memberId: memberId, status: "reviewed_complete")
        print("✅ DataManager: User confirmed guided data review for member \(memberId)")
    }
    
    /// Switch from Guided Setup to Self Setup (user chose to fill their own data)
    /// - Parameter memberId: The family_members record ID
    func switchToSelfSetup(memberId: String) async throws {
        do {
            // Try to update both fields
            let updateData: [String: AnyJSON] = [
                "onboarding_type": .string("Self Setup"),
                "guided_setup_status": .null
            ]
            
            try await supabase
                .from("family_members")
                .update(updateData)
                .eq("id", value: memberId)
                .execute()
            
            print("✅ DataManager: Switched member \(memberId) to Self Setup")
            
        } catch let error as PostgrestError {
            // If guided_setup_status column doesn't exist, retry without it
            if error.message.contains("guided_setup_status") {
                print("⚠️ DataManager: guided_setup_status column missing, updating onboarding_type only")
                
                let fallbackData: [String: AnyJSON] = [
                    "onboarding_type": .string("Self Setup")
                ]
                
                try await supabase
                    .from("family_members")
                    .update(fallbackData)
                    .eq("id", value: memberId)
                    .execute()
                
                print("✅ DataManager: Switched member \(memberId) to Self Setup (fallback)")
            } else {
                print("❌ DataManager: Failed to switch to self setup: \(error.localizedDescription)")
                throw DataError.databaseError("Failed to switch to self setup")
            }
        } catch {
            print("❌ DataManager: Failed to switch to self setup: \(error.localizedDescription)")
            throw DataError.databaseError("Failed to switch to self setup")
        }
    }
    
    /// Accept guided setup invite (user accepted, waiting for admin to fill data)
    /// - Parameter memberId: The family_members record ID
    func acceptGuidedSetup(memberId: String) async throws {
        try await updateGuidedSetupStatus(memberId: memberId, status: "accepted_awaiting_data")
        print("✅ DataManager: User accepted guided setup for member \(memberId)")
    }
    
    /// Fetch family data
    func fetchFamilyData() async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        do {
            // Fetch user's family membership
            let memberships: [FamilyMemberRecord] = try await supabase
                .from("family_members")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value as [FamilyMemberRecord]
            
            if let membership = memberships.first, let familyId = membership.familyId {
                // Fetch family details
                let families: [FamilyRecord] = try await supabase
                    .from("families")
                    .select()
                    .eq("id", value: familyId.uuidString)
                    .execute()
                    .value as [FamilyRecord]
                
                if let family = families.first {
                    let familyIdString = family.id.uuidString
                    currentFamilyId = familyIdString
                    familyName = family.name
                    print("✅ DataManager: Restored family from membership: \(family.name) (ID: \(familyIdString))")
                }
            }
            
            print("✅ DataManager: Family data fetched, currentFamilyId: \(currentFamilyId ?? "nil")")
            
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Fetch family data error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    // MARK: - Error Mapping
    
    /// Map database errors to user-friendly messages
    private func mapDataError(_ error: Error) -> String {
        let errorString = error.localizedDescription.lowercased()
        
        // ALWAYS log the full error for debugging
        print("🔴 FULL ERROR: \(error)")
        print("🔴 ERROR STRING: \(errorString)")
        
        if errorString.contains("network") || errorString.contains("connection") {
            return "Please check your internet connection and try again."
        }
        
        // Check constraint violations - means invalid enum value
        if errorString.contains("check") && errorString.contains("constraint") {
            print("🔴 CHECK CONSTRAINT VIOLATION - invalid value being inserted")
            return "Invalid data value. Please contact support."
        }
        
        // Unique constraint violations - means duplicate data
        if errorString.contains("unique") || errorString.contains("duplicate") {
            print("🔴 UNIQUE CONSTRAINT VIOLATION - duplicate data")
            return "This information already exists. Please check your data."
        }
        
        if errorString.contains("foreign key") || errorString.contains("reference") {
            return "Invalid data reference. Please try again."
        }
        
        if errorString.contains("not authenticated") || errorString.contains("unauthorized") {
            return "Please sign in to continue."
        }
        
        // Default - show actual error for debugging
        return "Error: \(error.localizedDescription)"
    }
}

// MARK: - Data Models

struct FamilyMemberData: Identifiable {
    let id = UUID()
    let firstName: String
    let relationship: String
    let inviteCode: String
    let isOnboarded: Bool
}

/// Details returned when looking up an invite code
struct InviteDetails {
    let inviteId: String
    let familyId: String
    let familyName: String
    let firstName: String
    let relationship: String
    let onboardingType: String
    let isGuidedSetup: Bool  // true = "Guided Setup", false = "Self Setup"
    let guidedSetupStatus: String?  // nil, pending_acceptance, accepted_awaiting_data, data_complete_pending_review, reviewed_complete
    let hasGuidedData: Bool  // true if admin has already filled the data
}

// MARK: - Database Record Types

struct FamilyRecord: Codable {
    let id: UUID
    let name: String
    let sizeCategory: String
    let maxMembers: Int?
    let createdBy: UUID?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sizeCategory = "size_category"
        case maxMembers = "max_members"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct FamilyMemberRecord: Codable {
    let id: UUID
    let userId: UUID?
    let familyId: UUID?
    let role: String
    let relationship: String?
    let firstName: String
    let inviteCode: String?
    let inviteStatus: String
    let onboardingType: String?
    let guidedDataComplete: Bool?
    let guidedSetupStatus: String?
    
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
        case guidedDataComplete = "guided_data_complete"
        case guidedSetupStatus = "guided_setup_status"
    }
}

struct UserProfileData: Codable {
    let user_id: String?
    let first_name: String?
    let last_name: String?
    let date_of_birth: String?
    let gender: String?
    let ethnicity: String?
    let smoking_status: String?
    let height_cm: Double?
    let weight_kg: Double?
    let blood_pressure_status: String?
    let diabetes_status: String?
    let has_prior_heart_attack: Bool?
    let has_prior_stroke: Bool?
    let family_heart_disease_early: Bool?
    let family_stroke_early: Bool?
    let family_type2_diabetes: Bool?
    let onboarding_step: Int?
    let onboarding_complete: Bool?
    let risk_band: String?
    let risk_points: Int?
    let optimal_vitality_target: Int?
    let vitality_score_current: Int?
}

// MARK: - Guided Setup Data Models

/// Raw JSON structure from database (JSONB column)
/// Using AnyJSON to keep it encodable/decodable with Supabase client
typealias GuidedHealthDataJSON = [String: AnyJSON]

/// Structured guided health data for superadmin-filled user profiles
struct GuidedHealthData {
    let aboutYou: AboutYouData
    let heartHealth: HeartHealthData
    let medicalHistory: MedicalHistoryData
    
    struct AboutYouData {
        let gender: String
        let dateOfBirth: String  // yyyy-MM-dd format
        let heightCm: Double
        let weightKg: Double
        let ethnicity: String
        let smokingStatus: String
    }
    
    struct HeartHealthData {
        let bloodPressureStatus: String
        let diabetesStatus: String
        let hasPriorHeartAttack: Bool
        let hasPriorStroke: Bool
        let hasChronicKidneyDisease: Bool
        let hasAtrialFibrillation: Bool
        let hasHighCholesterol: Bool
    }
    
    struct MedicalHistoryData {
        let familyHeartDiseaseEarly: Bool
        let familyStrokeEarly: Bool
        let familyType2Diabetes: Bool
    }
    
    /// Direct initializer for building from UI input
    init(aboutYou: AboutYouData, heartHealth: HeartHealthData, medicalHistory: MedicalHistoryData) {
        self.aboutYou = aboutYou
        self.heartHealth = heartHealth
        self.medicalHistory = medicalHistory
    }
    
    /// Convert from JSON dictionary (from database)
    /// We convert AnyJSON -> Data -> [String: Any] for straightforward parsing
    init?(from json: GuidedHealthDataJSON) {
        do {
            let data = try JSONEncoder().encode(json)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let aboutYouDict = root["about_you"] as? [String: Any],
                  let heartHealthDict = root["heart_health"] as? [String: Any],
                  let medicalHistoryDict = root["medical_history"] as? [String: Any] else {
                return nil
            }
            
            // Parse About You
            guard let gender = aboutYouDict["gender"] as? String,
                  let dob = aboutYouDict["date_of_birth"] as? String,
                  let height = aboutYouDict["height_cm"] as? Double,
                  let weight = aboutYouDict["weight_kg"] as? Double,
                  let ethnicity = aboutYouDict["ethnicity"] as? String,
                  let smoking = aboutYouDict["smoking_status"] as? String else {
                return nil
            }
            
            self.aboutYou = AboutYouData(
                gender: gender,
                dateOfBirth: dob,
                heightCm: height,
                weightKg: weight,
                ethnicity: ethnicity,
                smokingStatus: smoking
            )
            
            // Parse Heart Health
            guard let bpStatus = heartHealthDict["blood_pressure_status"] as? String,
                  let diabStatus = heartHealthDict["diabetes_status"] as? String,
                  let heartAttack = heartHealthDict["has_prior_heart_attack"] as? Bool,
                  let stroke = heartHealthDict["has_prior_stroke"] as? Bool,
                  let ckd = heartHealthDict["has_chronic_kidney_disease"] as? Bool,
                  let af = heartHealthDict["has_atrial_fibrillation"] as? Bool,
                  let cholesterol = heartHealthDict["has_high_cholesterol"] as? Bool else {
                return nil
            }
            
            self.heartHealth = HeartHealthData(
                bloodPressureStatus: bpStatus,
                diabetesStatus: diabStatus,
                hasPriorHeartAttack: heartAttack,
                hasPriorStroke: stroke,
                hasChronicKidneyDisease: ckd,
                hasAtrialFibrillation: af,
                hasHighCholesterol: cholesterol
            )
            
            // Parse Medical History
            guard let familyHeart = medicalHistoryDict["family_heart_disease_early"] as? Bool,
                  let familyStroke = medicalHistoryDict["family_stroke_early"] as? Bool,
                  let familyDiabetes = medicalHistoryDict["family_type2_diabetes"] as? Bool else {
                return nil
            }
            
            self.medicalHistory = MedicalHistoryData(
                familyHeartDiseaseEarly: familyHeart,
                familyStrokeEarly: familyStroke,
                familyType2Diabetes: familyDiabetes
            )
            
        } catch {
            return nil
        }
    }
    
    /// Convert to JSON dictionary (for database)
    func toJSON() -> GuidedHealthDataJSON {
        return [
            "about_you": .object([
                "gender": .string(aboutYou.gender),
                "date_of_birth": .string(aboutYou.dateOfBirth),
                "height_cm": .double(aboutYou.heightCm),
                "weight_kg": .double(aboutYou.weightKg),
                "ethnicity": .string(aboutYou.ethnicity),
                "smoking_status": .string(aboutYou.smokingStatus)
            ]),
            "heart_health": .object([
                "blood_pressure_status": .string(heartHealth.bloodPressureStatus),
                "diabetes_status": .string(heartHealth.diabetesStatus),
                "has_prior_heart_attack": .bool(heartHealth.hasPriorHeartAttack),
                "has_prior_stroke": .bool(heartHealth.hasPriorStroke),
                "has_chronic_kidney_disease": .bool(heartHealth.hasChronicKidneyDisease),
                "has_atrial_fibrillation": .bool(heartHealth.hasAtrialFibrillation),
                "has_high_cholesterol": .bool(heartHealth.hasHighCholesterol)
            ]),
            "medical_history": .object([
                "family_heart_disease_early": .bool(medicalHistory.familyHeartDiseaseEarly),
                "family_stroke_early": .bool(medicalHistory.familyStrokeEarly),
                "family_type2_diabetes": .bool(medicalHistory.familyType2Diabetes)
            ])
        ]
    }
}

// MARK: - Custom Error Types

enum DataError: LocalizedError {
    case notAuthenticated
    case invalidData(String)
    case databaseError(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to continue."
        case .invalidData(let message):
            return message
        case .databaseError(let message):
            return message
        }
    }
}
