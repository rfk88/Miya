//
//  DataManager.swift
//  Miya Health
//
//  Manages data persistence and synchronization.
//
//  AUDIT REPORT (guided onboarding status transitions)
//  - Compile audit: Cannot run `xcodebuild` in this environment (no Xcode). Verified compile-safety via lints/type checks in Cursor.
//  - State integrity: `guided_setup_status` is treated as the single source of truth for guided invite state.
//  - Transition correctness (intended state machine):
//      pending_acceptance -> (invitee accepts) accepted_awaiting_data
//      accepted_awaiting_data -> (admin fills guided data) data_complete_pending_review
//      data_complete_pending_review -> (invitee confirms) reviewed_complete
//      guided -> self: onboarding_type set to "Self Setup" and guided_setup_status cleared
//  - Known limitations: If guided_setup_status columns are missing (migration not run), some functions fall back or return empty results.

import SwiftUI
import Combine
import Supabase
import Foundation

@MainActor
class DataManager: ObservableObject {
    
    // MARK: - Guided setup schema gating (runtime)
    
    private var guidedSetupSchemaAvailableCache: Bool? = nil
    
    // MARK: - user_profiles schema gating (runtime)
    //
    // We have seen environments where `user_profiles` exists but is missing WHO-risk columns like
    // `blood_pressure_status` / `diabetes_status`. In that case PostgREST will reject updates with
    // "Could not find the '<col>' column of 'user_profiles' in the schema cache".
    //
    // Definitive product fix is to apply `PATCH_user_profiles.sql` to the connected Supabase project.
    // App-side fix here: never hard-fail the guided member on confirm; retry with only base columns.
    private var userProfilesSchemaHasWHORiskColumnsCache: Bool? = nil
    
    private func errorLooksLikeMissingColumn(_ error: Error) -> Bool {
        let desc = String(describing: error).lowercased()
        return desc.contains("schema cache") && desc.contains("could not find") && desc.contains("column") && desc.contains("user_profiles")
    }
    
    private func detectUserProfilesWHORiskColumnsAvailability() async -> Bool {
        if let cached = userProfilesSchemaHasWHORiskColumnsCache { return cached }
        do {
            _ = try await supabase
                .from("user_profiles")
                .select("blood_pressure_status,diabetes_status")
                .limit(1)
                .execute()
            userProfilesSchemaHasWHORiskColumnsCache = true
            return true
        } catch {
            if errorLooksLikeMissingColumn(error) {
                #if DEBUG
                print("🧪 UserProfilesSchemaProbe FAILED (WHO risk columns missing):", error)
                #endif
                userProfilesSchemaHasWHORiskColumnsCache = false
                return false
            }
            // Unknown error (RLS/network). Don't cache as missing; let writes attempt.
            #if DEBUG
            print("🧪 UserProfilesSchemaProbe FAILED (non-schema):", error)
            #endif
            return true
        }
    }
    
    /// Internal detector (do not call directly from UI).
    private func detectGuidedSetupSchemaAvailability() async -> Bool {
        if let cached = guidedSetupSchemaAvailableCache { return cached }
        do {
            _ = try await supabase
                .from("family_members")
                .select("guided_setup_status,guided_data_filled_at,guided_data_reviewed_at")
                .limit(1)
                .execute()
            guidedSetupSchemaAvailableCache = true
            return true
        } catch {
            // Only treat *undefined column* as "schema missing".
            // Other errors (RLS/permissions/transient network issues) must NOT be cached as schema-missing,
            // otherwise we will incorrectly no-op guided flows for the entire session.
            let desc = String(describing: error).lowercased()
            let isUndefinedColumn =
                desc.contains("42703") ||
                desc.contains("undefined_column") ||
                (desc.contains("column") && desc.contains("does not exist"))
            
            #if DEBUG
            print("🧪 GuidedSchemaProbe FAILED (undefined_column=\(isUndefinedColumn)):", error)
            #endif
            
            if isUndefinedColumn {
                guidedSetupSchemaAvailableCache = false
                return false
            }
            
            // Don't cache; assume schema exists so writes can attempt and surface real failures.
            return true
        }
    }

    /// DEBUG-only diagnostic: prints whether guided onboarding columns exist in the connected Supabase database.
    ///
    /// Requirements:
    /// - Logs which columns exist / are missing for `family_members`.
    /// - Logs the connected Supabase URL + anon key suffix.
    /// - Logs a final `GUIDED_SCHEMA_PRESENT = true|false`.
    ///
    /// Notes:
    /// - Uses direct `SELECT <column>` probes only.
    /// - No silent failures: any probe error is printed to console.
    func debugPrintGuidedSchemaState() async {
        let url = SupabaseConfig.supabaseURL
        let anonSuffix = String(SupabaseConfig.supabaseAnonKey.suffix(6))
        print("🧪 GuidedSchemaCheck | SUPABASE_URL=\(url) | ANON_KEY_SUFFIX=\(anonSuffix)")

        let targetColumns = [
            "guided_setup_status",
            "guided_data_filled_at",
            "guided_data_reviewed_at"
        ]

        var present: Set<String> = []
        var missing: Set<String> = []

        // Probe: direct select probes, one column at a time.
        for col in targetColumns {
            do {
                _ = try await supabase
                    .from("family_members")
                    .select(col)
                    .limit(1)
                    .execute()
                present.insert(col)
            } catch {
                print("🧪 GuidedSchemaCheck | probe FAILED for column '\(col)': \(error)")
                missing.insert(col)
            }
        }

        for col in targetColumns {
            let state = present.contains(col) ? "PRESENT" : "MISSING"
            print("🧪 GuidedSchemaCheck | family_members.\(col) = \(state)")
        }

        let guidedSchemaPresent = missing.isEmpty
        print("🧪 GuidedSchemaCheck | GUIDED_SCHEMA_PRESENT = \(guidedSchemaPresent)")
    }
    
    /// Hard gate: detect whether guided setup columns exist in Supabase.
    /// Cached in-memory for the session to avoid repeated checks.
    /// Note: This must never be used to alter invitee UX (guided setup is a product flow, not a capability feature).
    func guidedSetupSchemaIsAvailable() async -> Bool {
        await detectGuidedSetupSchemaAvailability()
    }
    
    #if DEBUG
    private func traceGuidedStatus(memberId: String, old: GuidedSetupStatus?, new: GuidedSetupStatus?, callsite: String) {
        let oldStr = old?.rawValue ?? "nil"
        let newStr = new?.rawValue ?? "nil"
        print("🧭 GuidedStatusTracer | memberId=\(memberId) | \(oldStr) -> \(newStr) | callsite=\(callsite)")
    }
    #endif
    
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
    
    private let lastAuthUserIdDefaultsKey = "lastAuthUserId"
    
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
    
    /// Clears cached/persisted family state if the authenticated user changes.
    /// Fixes "same family across two super admins" by preventing cross-auth contamination.
    func clearFamilyCachesIfAuthChanged() async {
        let authedUserId = await currentUserId
        let lastUserId = UserDefaults.standard.string(forKey: lastAuthUserIdDefaultsKey)
        
        // If the user changed (or we don't have a stored user yet), clear cached family state.
        if authedUserId != lastUserId {
            #if DEBUG
            print("🧹 DataManager: Auth user changed; clearing family caches. old=\(lastUserId ?? "nil") new=\(authedUserId ?? "nil")")
            #endif
            
            await MainActor.run {
                self.currentFamilyId = nil
                self.familyName = nil
                self.familyMembers = []
            }
            
            // Persist the new user id (or clear if signed out)
            if let authedUserId = authedUserId {
                UserDefaults.standard.set(authedUserId, forKey: lastAuthUserIdDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastAuthUserIdDefaultsKey)
            }
        }
    }
    
    /// Hard-reset all cached state (called on explicit logout for zero state leakage).
    /// Unlike `clearFamilyCachesIfAuthChanged`, this unconditionally clears everything.
    func resetCaches() {
        #if DEBUG
        print("🧹 DataManager: resetCaches() - clearing all cached state")
        #endif
        
        // Clear in-memory state
        currentFamilyId = nil
        familyName = nil
        familyMembers = []
        guidedSetupSchemaAvailableCache = nil
        
        // Clear persisted state
        UserDefaults.standard.removeObject(forKey: "currentFamilyId")
        UserDefaults.standard.removeObject(forKey: lastAuthUserIdDefaultsKey)
        
        print("✅ DataManager: resetCaches() complete")
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
    
    /// Public accessor for current authenticated user ID (async)
    var currentUserIdString: String? {
        get async {
            await currentUserId
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
    
    /// Check Rook API connection status for an API-based data source
    /// - Parameters:
    ///   - userId: Authenticated user's ID
    ///   - dataSource: Rook data source identifier (e.g., "whoop", "oura", "fitbit")
    /// - Returns: true if connected, false otherwise
    func checkRookAPIConnectionStatus(userId: String, dataSource: String) async throws -> Bool {
        do {
            let isConnected = try await RookAPIService.shared.checkConnectionStatus(
                dataSource: dataSource,
                userId: userId
            )
            print("📊 DataManager: Rook API connection status for \(dataSource): \(isConnected ? "connected" : "disconnected")")
            return isConnected
        } catch {
            print("❌ DataManager: Error checking Rook API connection status: \(error.localizedDescription)")
            throw DataError.databaseError("Failed to check connection status: \(error.localizedDescription)")
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
                print("❌ DataManager: Validation failed - Invalid ethnicity: \(ethnicity)")
                throw DataError.invalidData("Invalid ethnicity value: \(ethnicity)")
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
            
            do {
                try await supabase
                    .from("user_profiles")
                    .update(profileData)
                    .eq("user_id", value: userId)
                    .execute()
            } catch {
                // If the environment is missing WHO-risk columns, retry with base columns only.
                // This unblocks guided member confirmation immediately and still persists core profile fields.
                if errorLooksLikeMissingColumn(error) {
                    #if DEBUG
                    print("⚠️ DataManager: saveUserProfile initial UPDATE failed due to missing column(s). Retrying base columns only. error=\(error)")
                    #endif
                    
                    // Cache that WHO-risk columns are missing so future writes can avoid failing first.
                    userProfilesSchemaHasWHORiskColumnsCache = false
                    
                    // Keep only base columns that older schemas are expected to have.
                    let baseKeys: Set<String> = [
                        "last_name",
                        "gender",
                        "date_of_birth",
                        "ethnicity",
                        "smoking_status",
                        "height_cm",
                        "weight_kg",
                        "nutrition_quality",
                        "onboarding_step"
                    ]
                    let filtered = profileData.filter { baseKeys.contains($0.key) }
                    
                    try await supabase
                        .from("user_profiles")
                        .update(filtered)
                        .eq("user_id", value: userId)
                        .execute()
                    
                    #if DEBUG
                    print("✅ DataManager: saveUserProfile retry succeeded (base columns only).")
                    print("   Missing WHO-risk columns in DB; apply PATCH_user_profiles.sql for full guided profile persistence.")
                    #endif
                } else {
                    throw error
                }
            }
            
            print("✅ DataManager: User profile UPDATED for user \(userId)")

            #if DEBUG
            // Task validation helper: fetch the row back so you can confirm Supabase updated.
            if let refreshed = try? await loadUserProfile() {
                func s(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }
                print("🧪 UserProfileRefresh | user_id=\(userId)")
                print("  blood_pressure_status=\(s(refreshed.blood_pressure_status))")
                print("  diabetes_status=\(s(refreshed.diabetes_status))")
                print("  onboarding_step=\(s(refreshed.onboarding_step))")
            }
            #endif
            
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
            // Best-effort: if risk columns aren't present yet, don't block the UI flow.
            if errorLooksLikeMissingColumn(error) {
                #if DEBUG
                print("⚠️ DataManager: saveRiskAssessment skipped (user_profiles missing risk columns). Apply PATCH_user_profiles.sql. error=\(error)")
                #endif
                return
            }
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save risk assessment error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Save daily vitality scores (batch upsert)
    /// - Parameter scores: Array of daily scores with date, total, components
    func saveVitalityScores(
        _ scores: [(date: Date, total: Int, sleep: Int, movement: Int, stress: Int, source: String)],
        snapshot: VitalitySnapshot? = nil
    ) async throws {
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
                var snapshotData: [String: AnyJSON] = [
                    "vitality_score_current": .integer(latest.total),
                    "vitality_score_source": .string(validSources.contains(latest.source) ? latest.source : "csv"),
                    "vitality_score_updated_at": .string(ISO8601DateFormatter().string(from: latest.date))
                ]
                
                // If a new-engine snapshot was provided, also persist pillar scores (0–100).
                if let snap = snapshot {
                    let sleepPillar = snap.pillarScores.first(where: { $0.pillar == .sleep })?.score
                    let movementPillar = snap.pillarScores.first(where: { $0.pillar == .movement })?.score
                    let stressPillar = snap.pillarScores.first(where: { $0.pillar == .stress })?.score
                    
                    if let sleepPillar { snapshotData["vitality_sleep_pillar_score"] = .integer(sleepPillar) }
                    if let movementPillar { snapshotData["vitality_movement_pillar_score"] = .integer(movementPillar) }
                    if let stressPillar { snapshotData["vitality_stress_pillar_score"] = .integer(stressPillar) }
                }
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

    /// Save daily (per-date) pillar scores (0–100) into `vitality_scores` for day-over-day trends.
    /// - Note: Uses UTC day keys ("YYYY-MM-DD") as `score_date`.
    /// - Parameter clearExisting: If true, deletes all existing daily scores for this user before inserting (prevents overlapping uploads).
    func saveDailyVitalityPillarScores(
        _ daily: [(dayKey: String, snapshot: VitalitySnapshot)],
        source: String = "manual",
        clearExisting: Bool = false
    ) async throws {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        try await saveDailyVitalityPillarScores(daily, source: source, forUserId: userId, clearExisting: clearExisting)
    }

    /// Clear all daily vitality scores for a specific user (debug/admin tooling).
    /// Used before re-uploading to avoid overlapping/duplicate data.
    func clearDailyVitalityScores(forUserId userId: String) async throws {
        do {
            try await supabase
                .from("vitality_scores")
                .delete()
                .eq("user_id", value: userId)
                .execute()
            
            print("✅ DataManager: Cleared all daily vitality scores for user \(userId)")
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Clear daily vitality scores error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Save daily pillar scores for a specific user (debug/admin tooling).
    /// - Important: This is used for testing flows where an admin uploads a dataset on behalf of a family member.
    /// - Parameter clearExisting: If true, deletes all existing daily scores for this user before inserting (prevents overlapping uploads).
    func saveDailyVitalityPillarScores(
        _ daily: [(dayKey: String, snapshot: VitalitySnapshot)],
        source: String = "manual",
        forUserId userId: String,
        clearExisting: Bool = false
    ) async throws {
        
        guard !daily.isEmpty else {
            print("⚠️ DataManager: saveDailyVitalityPillarScores called with empty daily array")
            return
        }
        
        do {
            // Clear existing rows if requested (for debug uploads to avoid overlapping data)
            if clearExisting {
                try await clearDailyVitalityScores(forUserId: userId)
            }
            
            let payload: [[String: AnyJSON]] = daily.map { row in
                let sleepPillar = row.snapshot.pillarScores.first(where: { $0.pillar == .sleep })?.score
                let movementPillar = row.snapshot.pillarScores.first(where: { $0.pillar == .movement })?.score
                let stressPillar = row.snapshot.pillarScores.first(where: { $0.pillar == .stress })?.score
                
                var out: [String: AnyJSON] = [
                    "user_id": .string(userId),
                    "score_date": .string(row.dayKey),
                    "total_score": .integer(row.snapshot.totalScore),
                    "source": .string(source)
                ]
                
                out["vitality_sleep_pillar_score"] = sleepPillar.map { AnyJSON.integer($0) } ?? .null
                out["vitality_movement_pillar_score"] = movementPillar.map { AnyJSON.integer($0) } ?? .null
                out["vitality_stress_pillar_score"] = stressPillar.map { AnyJSON.integer($0) } ?? .null
                
                return out
            }
            
            try await supabase
                .from("vitality_scores")
                .upsert(payload, onConflict: "user_id,score_date")
                .execute()
            
            print("✅ DataManager: Saved daily vitality pillar scores (days: \(daily.count), source: \(source), user: \(userId))")
            #if DEBUG
            let dateRange = "\(daily.first?.dayKey ?? "nil") to \(daily.last?.dayKey ?? "nil")"
            print("  📅 Date range: \(dateRange)")
            #endif
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save daily vitality pillar scores error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }

    /// Save a "current vitality" snapshot for the authenticated user.
    /// Used for temporary/manual testing flows (e.g. ROOK export JSON import) where we don't persist a full per-day series.
    /// - Note: Sets `vitality_score_updated_at` to NOW so "recent data" filters can include it.
    func saveVitalitySnapshot(currentScore: Int, source: String = "manual") async throws {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        do {
            let snapshotData: [String: AnyJSON] = [
                "vitality_score_current": .integer(currentScore),
                "vitality_score_source": .string(source),
                "vitality_score_updated_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            
            try await supabase
                .from("user_profiles")
                .update(snapshotData)
                .eq("user_id", value: userId)
                .execute()
            
            print("✅ DataManager: Vitality snapshot saved (score: \(currentScore), source: \(source))")
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save vitality snapshot error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    // MARK: - Vitality Score History (for Trends)
    
    /// A single day's vitality scores for trend analysis.
    struct DailyVitalityScore: Decodable {
        let dayKey: String
        let totalScore: Int
        let sleepPoints: Int?
        let movementPoints: Int?
        let stressPoints: Int?
        
        enum CodingKeys: String, CodingKey {
            case dayKey = "score_date"
            case totalScore = "total_score"
            case sleepPoints = "vitality_sleep_pillar_score"
            case movementPoints = "vitality_movement_pillar_score"
            case stressPoints = "vitality_stress_pillar_score"
        }
    }

    // MARK: - Wearable Daily Metrics (ROOK -> webhook -> Supabase)
    struct WearableDailyMetricRow: Decodable {
        let metricDate: String
        let steps: Int?
        let sleepMinutes: Int?
        let hrvMs: Double?
        let restingHr: Double?
        let source: String?

        enum CodingKeys: String, CodingKey {
            case metricDate = "metric_date"
            case steps = "steps"
            case sleepMinutes = "sleep_minutes"
            case hrvMs = "hrv_ms"
            case restingHr = "resting_hr"
            case source = "source"
        }
    }

    /// Fetch recent daily metrics extracted from ROOK webhooks.
    /// - Note: `rook_user_id` is the same UUID we pass as the ROOK user (auth user id).
    func fetchWearableDailyMetrics(days: Int = 14) async throws -> [WearableDailyMetricRow] {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let cutoff = df.string(from: cutoffDate)

        do {
            let rows: [WearableDailyMetricRow] = try await supabase
                .from("wearable_daily_metrics")
                .select("metric_date, steps, sleep_minutes, hrv_ms, resting_hr, source")
                .eq("rook_user_id", value: userId)
                .gte("metric_date", value: cutoff)
                .order("metric_date", ascending: true)
                .execute()
                .value

            #if DEBUG
            print("✅ DataManager: Fetched wearable_daily_metrics rows=\(rows.count) (cutoff=\(cutoff))")
            #endif
            return rows
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: fetchWearableDailyMetrics error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Fetch recent daily metrics extracted from ROOK webhooks for a specific user.
    /// - Parameters:
    ///   - userId: User UUID to fetch metrics for (used as rook_user_id)
    ///   - days: Number of days to look back (default 21)
    /// - Returns: Array of WearableDailyMetricRow sorted by date
    func fetchWearableDailyMetricsForUser(userId: String, days: Int = 21) async throws -> [WearableDailyMetricRow] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let cutoff = df.string(from: cutoffDate)

        do {
            let rows: [WearableDailyMetricRow] = try await supabase
                .from("wearable_daily_metrics")
                .select("metric_date, steps, sleep_minutes, hrv_ms, resting_hr, source")
                .eq("rook_user_id", value: userId)
                .gte("metric_date", value: cutoff)
                .order("metric_date", ascending: true)
                .execute()
                .value

            #if DEBUG
            print("✅ DataManager: Fetched wearable_daily_metrics rows=\(rows.count) for user \(userId) (cutoff=\(cutoff))")
            #endif
            return rows
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: fetchWearableDailyMetricsForUser error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Fetch member age from user_profiles table.
    /// - Parameter userId: User UUID to fetch age for
    /// - Returns: Age in years, or nil if date_of_birth is missing
    func fetchMemberAge(userId: String) async throws -> Int? {
        struct DOBRow: Decodable {
            let date_of_birth: String?
        }
        
        do {
            let rows: [DOBRow] = try await supabase
                .from("user_profiles")
                .select("date_of_birth")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            
            guard let dobString = rows.first?.date_of_birth, !dobString.isEmpty else {
                #if DEBUG
                print("⚠️ DataManager: No date_of_birth found for user \(userId)")
                #endif
                return nil
            }
            
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            
            guard let dob = df.date(from: dobString) else {
                #if DEBUG
                print("⚠️ DataManager: Invalid date_of_birth format for user \(userId): \(dobString)")
                #endif
                return nil
            }
            
            let calendar = Calendar(identifier: .gregorian)
            let now = Date()
            let age = calendar.dateComponents([.year], from: dob, to: now).year ?? nil
            
            #if DEBUG
            if let age = age {
                print("✅ DataManager: Calculated age \(age) for user \(userId)")
            }
            #endif
            
            return age
        } catch {
            print("❌ DataManager: fetchMemberAge error: \(error.localizedDescription)")
            throw DataError.databaseError("Failed to fetch member age")
        }
    }
    
    /// Fetch vitality score history for a single user and specific pillar.
    /// - Parameters:
    ///   - userId: User UUID to fetch history for.
    ///   - pillar: The pillar to extract (sleep, movement, or stress).
    ///   - days: Number of days to look back (default 21).
    /// - Returns: Array of daily pillar scores (date + value) sorted ascending by date.
    func fetchUserPillarHistory(
        userId: String,
        pillar: VitalityPillar,
        days: Int = 21
    ) async throws -> [(date: String, value: Int?)] {
        // Calculate cutoff date
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let cutoffString = dateFormatter.string(from: cutoffDate)
        
        do {
            let rows: [DailyVitalityScore] = try await supabase
                .from("vitality_scores")
                .select("score_date, total_score, vitality_sleep_pillar_score, vitality_movement_pillar_score, vitality_stress_pillar_score")
                .eq("user_id", value: userId)
                .gte("score_date", value: cutoffString)
                .order("score_date", ascending: true)
                .execute()
                .value
            
            // Extract the specific pillar score for each day
            let pillarScores = rows.map { row -> (date: String, value: Int?) in
                let pillarValue: Int?
                switch pillar {
                case .sleep:
                    pillarValue = row.sleepPoints
                case .movement:
                    pillarValue = row.movementPoints
                case .stress:
                    pillarValue = row.stressPoints
                }
                return (date: row.dayKey, value: pillarValue)
            }
            
            #if DEBUG
            print("📊 DataManager: Fetched \(pillarScores.count) \(pillar.rawValue) pillar scores for user \(userId)")
            #endif
            
            return pillarScores
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: fetchUserPillarHistory error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Fetch vitality score history for multiple users (for family trend analysis).
    /// - Parameters:
    ///   - userIds: Array of user UUIDs to fetch history for.
    ///   - days: Number of days to look back (default 14).
    /// - Returns: Dictionary mapping userId → array of DailyVitalityScore (sorted ascending by date).
    func fetchMemberVitalityScoreHistory(
        userIds: [String],
        days: Int = 14
    ) async throws -> [String: [DailyVitalityScore]] {
        guard !userIds.isEmpty else {
            return [:]
        }
        
        // Calculate cutoff date
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let cutoffString = dateFormatter.string(from: cutoffDate)
        
        var result: [String: [DailyVitalityScore]] = [:]
        
        // Query each user individually (reliable approach)
        for userId in userIds {
            do {
                let rows: [DailyVitalityScore] = try await supabase
                    .from("vitality_scores")
                    .select("score_date, total_score, vitality_sleep_pillar_score, vitality_movement_pillar_score, vitality_stress_pillar_score")
                    .eq("user_id", value: userId)
                    .gte("score_date", value: cutoffString)
                    .order("score_date", ascending: true)
                    .execute()
                    .value
                
                result[userId.lowercased()] = rows
                #if DEBUG
                print("📊 DataManager: Fetched \(rows.count) vitality_scores rows for user \(userId) (cutoff: \(cutoffString))")
                if rows.isEmpty {
                    print("  ⚠️ No rows found for this user in window")
                } else {
                    print("  📅 Date range: \(rows.first?.dayKey ?? "nil") to \(rows.last?.dayKey ?? "nil")")
                }
                #endif
            } catch {
                print("⚠️ DataManager: Failed to fetch vitality history for user \(userId): \(error.localizedDescription)")
                result[userId.lowercased()] = []
            }
        }
        
        #if DEBUG
        let totalRows = result.values.reduce(0) { $0 + $1.count }
        print("✅ DataManager: Fetched vitality history for \(userIds.count) users (days: \(days), total rows: \(totalRows))")
        #endif
        return result
    }

    /// Save a "current vitality" snapshot (total + pillar scores) for the authenticated user.
    /// - Parameters:
    ///   - snapshot: Output from `VitalityScoringEngine` (source of truth for pillar scores).
    ///   - source: 'manual' for testing; later should be 'wearable' when ROOK is live.
    /// - Note: Sets `vitality_score_updated_at` to NOW so "recent data" filters can include it.
    func saveVitalitySnapshot(snapshot: VitalitySnapshot, source: String = "manual") async throws {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        try await saveVitalitySnapshot(snapshot: snapshot, source: source, forUserId: userId)
    }

    /// Save a "current vitality" snapshot for a specific user (debug/admin tooling).
    /// - Important: Used when uploading a dataset on behalf of a family member.
    func saveVitalitySnapshot(snapshot: VitalitySnapshot, source: String = "manual", forUserId userId: String) async throws {
        
        let sleepPillar = snapshot.pillarScores.first(where: { $0.pillar == .sleep })?.score
        let movementPillar = snapshot.pillarScores.first(where: { $0.pillar == .movement })?.score
        let stressPillar = snapshot.pillarScores.first(where: { $0.pillar == .stress })?.score
        
        do {
            var snapshotData: [String: AnyJSON] = [
                "vitality_score_current": .integer(snapshot.totalScore),
                "vitality_score_source": .string(source),
                "vitality_score_updated_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            
            snapshotData["vitality_sleep_pillar_score"] = sleepPillar.map { AnyJSON.integer($0) } ?? .null
            snapshotData["vitality_movement_pillar_score"] = movementPillar.map { AnyJSON.integer($0) } ?? .null
            snapshotData["vitality_stress_pillar_score"] = stressPillar.map { AnyJSON.integer($0) } ?? .null
            
            try await supabase
                .from("user_profiles")
                .update(snapshotData)
                .eq("user_id", value: userId)
                .execute()
            
            print("✅ DataManager: Saved vitality snapshot for user \(userId) – total: \(snapshot.totalScore), sleep: \(sleepPillar ?? -1), movement: \(movementPillar ?? -1), stress: \(stressPillar ?? -1)")
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Save vitality snapshot error: \(error.localizedDescription)")
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
        
        struct InviteCodeRow: Decodable { let invite_code: String? }
        
        while attempts < maxAttempts {
            // Generate random code
            let randomCode = String((0..<4).compactMap { _ in characters.randomElement() })
            let inviteCode = "MIYA-\(randomCode)"
            
            // Check if code already exists
            let existing: [InviteCodeRow] = try await supabase
                .from("family_members")
                .select("invite_code")
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
    
    /// Check if family is at max member limit before adding a new invite.
    /// - Parameter familyId: The family UUID string
    /// - Throws: DataError if at or over limit
    private func checkFamilyMemberLimit(familyId: String) async throws {
        // Fetch family's max_members
        struct FamilyLimitRow: Decodable {
            let max_members: Int?
        }
        
        let familyRows: [FamilyLimitRow] = try await supabase
            .from("families")
            .select("max_members")
            .eq("id", value: familyId)
            .limit(1)
            .execute()
            .value
        
        guard let family = familyRows.first, let maxMembers = family.max_members else {
            // If max_members is NULL, allow (backward compatibility)
            return
        }
        
        // Count all current members (pending + accepted) for this family
        struct MemberIdRow: Decodable { let id: UUID }
        let currentMembers: [MemberIdRow] = try await supabase
            .from("family_members")
            .select("id")
            .eq("family_id", value: familyId)
            .execute()
            .value
        
        let currentCount = currentMembers.count
        
        if currentCount >= maxMembers {
            throw DataError.databaseError("Family member limit reached. Your family plan allows up to \(maxMembers) members. Please remove a member before adding another.")
        }
        
        print("✅ DataManager: Family member limit check passed (current: \(currentCount)/\(maxMembers))")
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
        await MainActor.run { self.isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }
        
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
            // Check family member limit BEFORE creating invite
            try await checkFamilyMemberLimit(familyId: familyId)
            
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
                "user_id": .null, // must remain NULL until the invite is redeemed by the invited user
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
        guidedSetupStatus: GuidedSetupStatus? = nil
    ) async throws -> (inviteCode: String, memberId: String) {
        await MainActor.run { self.isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }
        
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
        
        // Admin intent should always be allowed: invites can be created even if guided schema isn't available.
        // We only write guided_setup_status when the schema supports it.
        let guidedSchemaSupported = await detectGuidedSetupSchemaAvailability()
        
        do {
            // Check family member limit BEFORE creating invite
            try await checkFamilyMemberLimit(familyId: familyId)
            
            // Generate unique invite code
            let inviteCode = try await generateInviteCode()
            
            // Build insert data - DO NOT include guided_setup_status (column may not exist yet)
            // The guided_setup_status will be set via separate update if needed
            let insertData: [String: AnyJSON] = [
                "user_id": .null, // must remain NULL until the invite is redeemed by the invited user
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
            
            // Set guided_setup_status if provided and supported (DB mutation boundary).
            if let status = guidedSetupStatus, guidedSchemaSupported {
                try await updateGuidedSetupStatus(memberId: memberId, status: status)
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
        await MainActor.run { self.isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }
        
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        do {
            // Look up the invite code in family_members
            let invites: [FamilyMemberRecord] = try await supabase
                .from("family_members")
                .select()
                .eq("invite_code", value: normalizedCode)
                .limit(1)
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
            let guidedStatus = parseGuidedSetupStatus(invite.guidedSetupStatus)
            #if DEBUG
            let statusStr = guidedStatus?.rawValue ?? "nil"
            print("GUIDED_STATUS_READ: memberId=\(invite.id.uuidString) onboardingType=\(invite.onboardingType ?? "nil") status=\(statusStr)")
            #endif
            
            #if DEBUG
            traceGuidedStatus(
                memberId: invite.id.uuidString,
                old: nil,
                new: guidedStatus,
                callsite: "\(#function)"
            )
            #endif
            
            return InviteDetails(
                memberId: invite.id.uuidString,
                familyId: familyId.uuidString,
                familyName: family.name,
                firstName: invite.firstName,
                relationship: invite.relationship ?? "",
                onboardingType: invite.onboardingType ?? "Self Setup",
                isGuidedSetup: invite.onboardingType == "Guided Setup",
                guidedSetupStatus: guidedStatus,
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
        await MainActor.run { self.isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }
        
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        do {
            // Update the family_members record.
            // NOTE: We only mark invite_status accepted and link user_id here.
            // guided_setup_status transitions are handled explicitly by:
            //  - acceptGuidedSetup (pending_acceptance -> accepted_awaiting_data)
            //  - GuidedHealthDataEntryFlow (-> data_complete_pending_review)
            //  - confirmGuidedDataReview (-> reviewed_complete)
            let updateData: [String: AnyJSON] = [
                "user_id": .string(userId),
                "invite_status": .string("accepted")
            ]
            
            try await supabase
                .from("family_members")
                .update(updateData)
                .eq("invite_code", value: normalizedCode)
                .execute()
            
            // Fetch and set the family info for this session
            let invites: [FamilyMemberRecord] = try await supabase
                .from("family_members")
                .select()
                .eq("invite_code", value: normalizedCode)
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
    /// Update guided setup status for a family member (schema-gated; no silent fallback).
    func updateGuidedSetupStatus(memberId: String, status: GuidedSetupStatus) async throws {
        let supported = await detectGuidedSetupSchemaAvailability()
        guard supported else {
            // Do not expose schema/capability messaging to invitees.
            // Admin-facing callers may surface a generic failure.
            throw DataError.databaseError("Failed to update guided setup status.")
        }
        do {
            #if DEBUG
            // Fetch old status for tracing.
            struct GuidedStatusRow: Decodable { let guided_setup_status: String? }
            let existing: [GuidedStatusRow] = try await supabase
                .from("family_members")
                .select("guided_setup_status")
                .eq("id", value: memberId)
                .limit(1)
                .execute()
                .value
            let old = parseGuidedSetupStatus(existing.first?.guided_setup_status)
            let oldStr = old?.rawValue ?? "nil"
            let newStr = status.rawValue
            #endif
            
            // Try simple update first (just the status)
            let updateData: [String: AnyJSON] = [
                "guided_setup_status": .string(status.rawValue)
            ]
            
            try await supabase
                .from("family_members")
                .update(updateData)
                .eq("id", value: memberId)
                .execute()
            
            print("✅ DataManager: Updated guided setup status to '\(status.rawValue)' for member \(memberId)")
            #if DEBUG
            print("GUIDED_STATUS_WRITE: memberId=\(memberId) old=\(oldStr) new=\(newStr) fn=\(#function)")
            traceGuidedStatus(memberId: memberId, old: old, new: status, callsite: "\(#function)")
            #endif
            
            // Update timestamps (schema-gated; should exist if schema is available)
            if status == .dataCompletePendingReview || status == .reviewedComplete {
                let now = ISO8601DateFormatter().string(from: Date())
                let timestampField = status == .dataCompletePendingReview ? "guided_data_filled_at" : "guided_data_reviewed_at"
                
                try await supabase
                    .from("family_members")
                    .update([timestampField: AnyJSON.string(now)])
                    .eq("id", value: memberId)
                    .execute()
            }
            
        } catch {
            print("❌ DataManager: Failed to update guided setup status: \(error.localizedDescription)")
            throw error  // Re-throw so caller knows it failed
        }
    }
    
    /// Get family members waiting for guided data entry
    /// - Parameter familyId: The family ID
    /// - Returns: Array of members with status 'accepted_awaiting_data'
    func getPendingGuidedSetups(familyId: String) async throws -> [FamilyMemberRecord] {
        let supported = await detectGuidedSetupSchemaAvailability()
        guard supported else {
            throw DataError.databaseError("Failed to load guided setup members.")
        }
        do {
            let members: [FamilyMemberRecord] = try await supabase
                .from("family_members")
                .select()
                .eq("family_id", value: familyId)
                .eq("guided_setup_status", value: GuidedSetupStatus.acceptedAwaitingData.rawValue)
                .execute()
                .value
            
            print("📥 DataManager: Found \(members.count) members awaiting guided data entry")
            #if DEBUG
            for m in members {
                traceGuidedStatus(
                    memberId: m.id.uuidString,
                    old: nil,
                    new: parseGuidedSetupStatus(m.guidedSetupStatus),
                    callsite: "\(#function)"
                )
            }
            #endif
            return members
            
        } catch {
            print("❌ DataManager: Could not query pending guided setups: \(error.localizedDescription)")
            throw DataError.databaseError("Failed to load pending guided setups")
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
    
    /// Fetch all family members for a given family (including pending)
    func fetchFamilyMembers(familyId: String) async throws -> [FamilyMemberRecord] {
        do {
            let members: [FamilyMemberRecord] = try await supabase
                .from("family_members")
                .select()
                .eq("family_id", value: familyId)
                .execute()
                .value
            
            print("📥 DataManager: Found \(members.count) family members for family \(familyId)")
            return members
        } catch {
            // Important: allow SwiftUI task cancellation to propagate without turning it into a user-visible error.
            // Cancellation can come through as CancellationError, URLError with cancelled code, or wrapped in error messages.
            let errorDesc = error.localizedDescription.lowercased()
            if error is CancellationError || 
               (error as? URLError)?.code == .cancelled ||
               errorDesc.contains("cancelled") || 
               errorDesc.contains("cancel") {
                print("ℹ️ DataManager: fetchFamilyMembers cancelled (type: \(type(of: error)))")
                throw error
            }
            print("❌ DataManager: Failed to fetch family members: \(error.localizedDescription)")
            throw DataError.databaseError("Failed to load family members")
        }
    }
    
    /// Update the current user's display name in family_members.
    /// Names are ONLY stored in family_members.first_name (not in user_profiles).
    /// Works for both superadmins and members.
    func updateMyMemberName(firstName newName: String) async throws {
        // 1) Copy the string immediately to a local constant (prevents deallocation issues)
        let safeName = String(newName)
        
        // 2) Get current user id
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        let safeUserId = String(userId)
        
        // 3) Build update payload
        let payload: [String: AnyJSON] = ["first_name": .string(safeName)]
        
        // 4) Run the update directly by user_id
        do {
            try await supabase
                .from("family_members")
                .update(payload)
                .eq("user_id", value: safeUserId)
                .execute()
            
            print("✅ DataManager: Updated family_members.first_name for user \(safeUserId) -> \(safeName)")
        } catch {
            print("❌ DataManager: Failed to update member name: \(error.localizedDescription)")
            throw DataError.databaseError("Failed to update name. Please try again.")
        }
    }
    
    /// Update family name (admin/superadmin only, non-destructive).
    func updateFamilyName(familyId: String, name: String) async throws {
        do {
            try await supabase
                .from("families")
                .update(["name": AnyJSON.string(name)])
                .eq("id", value: familyId)
                .execute()
            print("✅ DataManager: Updated family name to \(name) for family \(familyId)")
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Failed to update family name: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Update a family member's role (e.g., member -> admin). Non-destructive.
    func updateFamilyMemberRole(memberId: String, role: String) async throws {
        guard ["superadmin", "admin", "member"].contains(role) else {
            throw DataError.invalidData("Invalid role")
        }
        do {
            try await supabase
                .from("family_members")
                .update(["role": AnyJSON.string(role)])
                .eq("id", value: memberId)
                .execute()
            print("✅ DataManager: Updated member role to \(role) for member \(memberId)")
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Update member role failed: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Remove a family member from the family.
    /// Implementation: delete the `family_members` row (revokes access / removes membership),
    /// while preserving user data in `user_profiles` and score history.
    func softRemoveFamilyMember(memberId: String) async throws {
        do {
            try await supabase
                .from("family_members")
                .delete()
                .eq("id", value: memberId)
                .execute()
            print("✅ DataManager: Removed member \(memberId) (deleted family_members row)")
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Soft remove failed: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// User confirms their guided data after review
    /// - Parameter memberId: The family_members record ID
    func confirmGuidedDataReview(memberId: String) async throws {
        // Member confirm must:
        // 1) write user_profiles from guided data
        // 2) transition guided_setup_status -> reviewed_complete
        let supported = await detectGuidedSetupSchemaAvailability()
        guard supported else {
            // Do not mention schema/migrations to invited users.
            throw DataError.databaseError("Couldn't complete guided setup. Please try again.")
        }
        
        guard let _ = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        guard let guided = try await loadGuidedHealthData(memberId: memberId) else {
            throw DataError.databaseError("Couldn't load your guided profile data. Please ask your admin to try again.")
        }
        
        // Parse yyyy-MM-dd (stored in guided JSON) to Date for `saveUserProfile`.
        let dob: Date? = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(secondsFromGMT: 0)
            return f.date(from: guided.aboutYou.dateOfBirth)
        }()
        
        // Upsert profile fields for the authenticated user (user_profiles row is created at signup).
        try await saveUserProfile(
            lastName: nil,
            gender: guided.aboutYou.gender,
            dateOfBirth: dob,
            ethnicity: guided.aboutYou.ethnicity,
            smokingStatus: guided.aboutYou.smokingStatus,
            heightCm: guided.aboutYou.heightCm,
            weightKg: guided.aboutYou.weightKg,
            nutritionQuality: nil,
            bloodPressureStatus: guided.heartHealth.bloodPressureStatus,
            diabetesStatus: guided.heartHealth.diabetesStatus,
            hasPriorHeartAttack: guided.heartHealth.hasPriorHeartAttack,
            hasPriorStroke: guided.heartHealth.hasPriorStroke,
            familyHeartDiseaseEarly: guided.medicalHistory.familyHeartDiseaseEarly,
            familyStrokeEarly: guided.medicalHistory.familyStrokeEarly,
            familyType2Diabetes: guided.medicalHistory.familyType2Diabetes,
            onboardingStep: nil
        )
        
        // Transition: data_complete_pending_review -> reviewed_complete (+ guided_data_reviewed_at)
        try await updateGuidedSetupStatus(memberId: memberId, status: .reviewedComplete)
        print("✅ DataManager: User confirmed guided data review for member \(memberId) (user_profiles updated)")
    }
    
    /// Switch from Guided Setup to Self Setup (user chose to fill their own data)
    /// - Parameter memberId: The family_members record ID
    func switchToSelfSetup(memberId: String) async throws {
        do {
            let supported = await detectGuidedSetupSchemaAvailability()
            #if DEBUG
            // Best-effort read of old status for tracing (only meaningful when schema is present).
            var oldStr = "nil"
            if supported {
                struct GuidedStatusRow: Decodable { let guided_setup_status: String? }
                let existing: [GuidedStatusRow] = try await supabase
                    .from("family_members")
                    .select("guided_setup_status")
                    .eq("id", value: memberId)
                    .limit(1)
                    .execute()
                    .value
                oldStr = existing.first?.guided_setup_status ?? "nil"
            }
            #endif
            let updateData: [String: AnyJSON] = supported
                ? ["onboarding_type": .string("Self Setup"), "guided_setup_status": .null]
                : ["onboarding_type": .string("Self Setup")]
            
            try await supabase
                .from("family_members")
                .update(updateData)
                .eq("id", value: memberId)
                .execute()
            
            print("✅ DataManager: Switched member \(memberId) to Self Setup")
            #if DEBUG
            print("GUIDED_STATUS_WRITE: memberId=\(memberId) old=\(oldStr) new=nil fn=\(#function)")
            #endif
            
        } catch {
            print("❌ DataManager: Failed to switch to self setup: \(error.localizedDescription)")
            throw DataError.databaseError("Failed to switch to self setup")
        }
    }
    
    /// Accept guided setup invite (user accepted, waiting for admin to fill data)
    /// - Parameter memberId: The family_members record ID
    func acceptGuidedSetup(memberId: String) async throws {
        let supported = await detectGuidedSetupSchemaAvailability()
        guard supported else {
            #if DEBUG
            print("⚠️ DataManager: acceptGuidedSetup blocked (guided schema missing) memberId=\(memberId)")
            #endif
            // Do not mention schema/migrations to invited users.
            throw DataError.databaseError("Couldn't accept guided setup. Please try again.")
        }
        
        // Transition: pending_acceptance -> accepted_awaiting_data
        try await updateGuidedSetupStatus(memberId: memberId, status: .acceptedAwaitingData)
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

    // MARK: - Family Vitality
    
    /// Fetch the family vitality summary (via Supabase RPC `get_family_vitality`).
    /// - Returns: Summary containing score + counts + last updated time.
    func fetchFamilyVitalitySummary() async throws -> FamilyVitalitySummary {
        guard let familyId = currentFamilyId else {
            throw DataError.databaseError("No family ID available to compute vitality.")
        }
        
        struct RPCRow: Decodable {
            let family_vitality_score: Int?
            let members_with_data: Int
            let members_total: Int
            let last_updated_at: String?
            let has_recent_data: Bool
            let family_progress_score: Int?
        }
        
        let rows: [RPCRow] = try await supabase
            .rpc("get_family_vitality", params: ["family_id": AnyJSON.string(familyId)])
            .execute()
            .value
        
        guard let row = rows.first else {
            throw DataError.databaseError("Family vitality RPC returned no rows.")
        }
        
        let lastUpdatedAt: Date? = {
            guard let s = row.last_updated_at else { return nil }
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fmt.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }()
        
        let summary = FamilyVitalitySummary(
            score: row.family_vitality_score,
            progressScore: row.family_progress_score,
            membersWithData: row.members_with_data,
            membersTotal: row.members_total,
            lastUpdatedAt: lastUpdatedAt
        )
        
        print("FamilyVitality RPC result: score=\(summary.score ?? -1), membersWithData=\(summary.membersWithData), membersTotal=\(summary.membersTotal)")
        return summary
    }
    
    /// Convenience wrapper: returns only the score (nil if no recent data).
    func fetchFamilyVitalityScore() async throws -> Int? {
        try await fetchFamilyVitalitySummary().score
    }
    
    /// Fetch the current user's `family_members` row (if any).
    /// Used for guided invite gating on login/resume (status-first routing).
    func fetchMyFamilyMemberRecord() async throws -> FamilyMemberRecord? {
        guard let userId = await currentUserId else {
            throw DataError.notAuthenticated
        }
        
        do {
            let memberships: [FamilyMemberRecord] = try await supabase
                .from("family_members")
                .select()
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            
            return memberships.first
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Failed to fetch my family member record: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Fetch a specific family member record by memberId.
    /// Used by GuidedSetupReviewView to load display info for the invited member.
    func fetchFamilyMemberRecord(memberId: String) async throws -> FamilyMemberRecord? {
        do {
            let members: [FamilyMemberRecord] = try await supabase
                .from("family_members")
                .select()
                .eq("id", value: memberId)
                .limit(1)
                .execute()
                .value
            
            return members.first
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: Failed to fetch family member record (memberId=\(memberId)): \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Fetch family name by familyId.
    /// Used by GuidedSetupReviewView to load family display name.
    func fetchFamilyName(familyId: UUID) async throws -> String? {
        struct FamilyRow: Decodable { let name: String }
        let rows: [FamilyRow] = try await supabase
            .from("families")
            .select("name")
            .eq("id", value: familyId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first?.name
    }
    
    #if DEBUG
    /// DEBUG-only: Dump the complete guided setup state for a given invite code or memberId.
    func debugDumpGuidedState(inviteCodeOrMemberId: String) async {
        print("🔍 DEBUG_DUMP_GUIDED_STATE: query=\(inviteCodeOrMemberId)")
        
        do {
            // Try as memberId first (UUID format)
            var members: [FamilyMemberRecord] = []
            if UUID(uuidString: inviteCodeOrMemberId) != nil {
                members = try await supabase
                    .from("family_members")
                    .select()
                    .eq("id", value: inviteCodeOrMemberId)
                    .limit(1)
                    .execute()
                    .value
            }
            
            // If not found, try as invite_code
            if members.isEmpty {
                members = try await supabase
                    .from("family_members")
                    .select()
                    .eq("invite_code", value: inviteCodeOrMemberId.uppercased())
                    .limit(1)
                    .execute()
                    .value
            }
            
            guard let member = members.first else {
                print("🔍 DEBUG_DUMP: NOT FOUND")
                return
            }
            
            print("🔍 DEBUG_DUMP:")
            print("  memberId: \(member.id.uuidString)")
            print("  invite_code: \(member.inviteCode ?? "nil")")
            print("  user_id: \(member.userId?.uuidString ?? "nil")")
            print("  onboarding_type: \(member.onboardingType ?? "nil")")
            print("  invite_status: \(member.inviteStatus)")
            print("  guided_setup_status: \(member.guidedSetupStatus ?? "nil")")
            print("  guided_data_complete: \(member.guidedDataComplete?.description ?? "nil")")
            print("  guided_data_filled_at: \(member.guidedDataFilledAt ?? "nil")")
            print("  guided_data_reviewed_at: \(member.guidedDataReviewedAt ?? "nil")")
            
        } catch {
            print("🔍 DEBUG_DUMP: ERROR: \(error.localizedDescription)")
        }
    }
    #endif
    
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

// MARK: - Family Badges (Weekly persisted; Daily computed client-side)

extension DataManager {
    struct FamilyVitalityScoreRow: Decodable {
        let userId: String
        let scoreDate: String
        let totalScore: Int?
        let progressScore: Int?
        let sleepPillar: Int?
        let movementPillar: Int?
        let stressPillar: Int?
        
        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case scoreDate = "score_date"
            case totalScore = "total_score"
            case progressScore = "progress_score"
            case sleepPillar = "vitality_sleep_pillar_score"
            case movementPillar = "vitality_movement_pillar_score"
            case stressPillar = "vitality_stress_pillar_score"
        }
    }
    
    struct FamilyBadgeRow: Decodable {
        let familyId: String
        let badgeWeekStart: String
        let badgeWeekEnd: String
        let badgeType: String
        let winnerUserId: String
        let metadata: [String: AnyJSON]?
        
        enum CodingKeys: String, CodingKey {
            case familyId = "family_id"
            case badgeWeekStart = "badge_week_start"
            case badgeWeekEnd = "badge_week_end"
            case badgeType = "badge_type"
            case winnerUserId = "winner_user_id"
            case metadata
        }
    }
    
    /// Fetch all members' `vitality_scores` rows for the family over a date range (UTC day keys).
    func fetchFamilyVitalityScores(
        familyId: String,
        startDate: String,
        endDate: String
    ) async throws -> [FamilyVitalityScoreRow] {
        do {
            let rows: [FamilyVitalityScoreRow] = try await supabase
                .rpc(
                    "get_family_vitality_scores",
                    params: [
                        "family_id": AnyJSON.string(familyId),
                        "start_date": AnyJSON.string(startDate),
                        "end_date": AnyJSON.string(endDate)
                    ]
                )
                .execute()
                .value
            return rows
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: fetchFamilyVitalityScores error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }

    /// Fallback path (used if RPC isn't deployed yet): fetch `vitality_scores` per user and combine.
    /// This keeps Champions usable even before backend schema cache refresh.
    func fetchFamilyVitalityScoresFallbackByUserIds(
        userIds: [String],
        startDate: String,
        endDate: String
    ) async throws -> [FamilyVitalityScoreRow] {
        guard !userIds.isEmpty else { return [] }
        do {
            struct Row: Decodable {
                let score_date: String
                let total_score: Int?
                let vitality_sleep_pillar_score: Int?
                let vitality_movement_pillar_score: Int?
                let vitality_stress_pillar_score: Int?
            }
            
            var out: [FamilyVitalityScoreRow] = []
            for uid in userIds {
                let rows: [Row] = try await supabase
                    .from("vitality_scores")
                    .select("score_date, total_score, vitality_sleep_pillar_score, vitality_movement_pillar_score, vitality_stress_pillar_score")
                    .eq("user_id", value: uid)
                    .gte("score_date", value: startDate)
                    .lte("score_date", value: endDate)
                    .order("score_date", ascending: true)
                    .execute()
                    .value
                
                out.append(contentsOf: rows.map { r in
                    FamilyVitalityScoreRow(
                        userId: uid,
                        scoreDate: r.score_date,
                        totalScore: r.total_score,
                        progressScore: nil,
                        sleepPillar: r.vitality_sleep_pillar_score,
                        movementPillar: r.vitality_movement_pillar_score,
                        stressPillar: r.vitality_stress_pillar_score
                    )
                })
            }
            
            return out
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: fetchFamilyVitalityScoresFallbackByUserIds error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Fetch persisted weekly badges for a given family and weekStart (UTC date string).
    func fetchFamilyBadges(
        familyId: String,
        weekStart: String
    ) async throws -> [FamilyBadgeRow] {
        do {
            let rows: [FamilyBadgeRow] = try await supabase
                .from("family_badges")
                .select("family_id, badge_week_start, badge_week_end, badge_type, winner_user_id, metadata")
                .eq("family_id", value: familyId)
                .eq("badge_week_start", value: weekStart)
                .execute()
                .value
            return rows
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: fetchFamilyBadges error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
    }
    
    /// Upsert weekly badge winners for a family/week.
    func upsertFamilyBadges(
        familyId: String,
        weekStart: String,
        weekEnd: String,
        winners: [BadgeEngine.Winner]
    ) async throws {
        guard !winners.isEmpty else {
            #if DEBUG
            print("ℹ️ DataManager: upsertFamilyBadges skipped (no winners). weekStart=\(weekStart)")
            #endif
            return
        }
        do {
            let payload: [[String: AnyJSON]] = winners.map { w in
                // Convert metadata to AnyJSON (best-effort)
                var meta: [String: AnyJSON] = [:]
                for (k, v) in w.metadata {
                    if let i = v as? Int { meta[k] = .integer(i) }
                    else if let d = v as? Double { meta[k] = .double(d) }
                    else if let s = v as? String { meta[k] = .string(s) }
                    else if let b = v as? Bool { meta[k] = .bool(b) }
                }
                
                return [
                    "family_id": .string(familyId),
                    "badge_week_start": .string(weekStart),
                    "badge_week_end": .string(weekEnd),
                    "badge_type": .string(w.badgeType),
                    "winner_user_id": .string(w.winnerUserId),
                    "metadata": .object(meta)
                ]
            }
            
            try await supabase
                .from("family_badges")
                .upsert(payload, onConflict: "family_id,badge_week_start,badge_type")
                .execute()
            
            #if DEBUG
            print("✅ DataManager: Upserted weekly family badges (count=\(winners.count), weekStart=\(weekStart))")
            #endif
        } catch {
            let userMessage = mapDataError(error)
            print("❌ DataManager: upsertFamilyBadges error: \(error.localizedDescription)")
            throw DataError.databaseError(userMessage)
        }
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
    /// `family_members.id` for the invited member row (used for guided status transitions).
    let memberId: String
    let familyId: String
    let familyName: String
    let firstName: String
    let relationship: String
    let onboardingType: String
    let isGuidedSetup: Bool  // true = "Guided Setup", false = "Self Setup"
    let guidedSetupStatus: GuidedSetupStatus?
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
    let guidedDataFilledAt: String?
    let guidedDataReviewedAt: String?
    
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
        case guidedDataFilledAt = "guided_data_filled_at"
        case guidedDataReviewedAt = "guided_data_reviewed_at"
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
    let vitality_progress_score_current: Int?
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

// MARK: - Family Vitality Types

struct FamilyVitalitySummary {
    let score: Int?              // nil if no recent data
    let progressScore: Int?      // nil if cannot compute / no recent data
    let membersWithData: Int
    let membersTotal: Int
    let lastUpdatedAt: Date?
}
