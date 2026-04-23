//
//  AuthenticatedLaunchHydration.swift
//  Miya Health
//
//  Single post-auth hydration path (cold launch, Sign in with Apple, email login).
//  Session readiness, bounded retries on transient failures, avoids drift between entry points.

import Foundation
import Supabase

enum AuthenticatedLaunchHydration {
    // MARK: - Session readiness (after signInWithIdToken / signIn)

    /// Polls until `auth.session` reads successfully or attempts exhausted. Fixes rare races where
    /// DB calls run before the client finishes persisting the new session.
    @MainActor
    static func awaitSupabaseSessionReady(
        maxAttempts: Int = 10,
        delayNanoseconds: UInt64 = 150_000_000
    ) async {
        for attempt in 0..<maxAttempts {
            do {
                _ = try await SupabaseConfig.client.auth.session
                return
            } catch {
                if attempt == maxAttempts - 1 {
                    print("⚠️ AuthenticatedLaunchHydration: session still unreadable after \(maxAttempts) attempts — \(error.localizedDescription)")
                    return
                }
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }
    }

    // MARK: - Transient error detection

    static func isTransientFailure(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet,
                 NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorInternationalRoamingOff,
                 NSURLErrorDataNotAllowed, NSURLErrorSecureConnectionFailed:
                return true
            default:
                break
            }
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("timeout") || text.contains("timed out") { return true }
        if text.contains("network") || text.contains("connection") { return true }
        if text.contains("503") || text.contains("502") || text.contains("504") { return true }
        return false
    }

    // MARK: - Retrying helpers

    private static func fetchFamilyDataWithRetries(dataManager: DataManager) async {
        for attempt in 0..<3 {
            do {
                try await dataManager.fetchFamilyData()
                return
            } catch {
                let last = attempt == 2
                if last || !isTransientFailure(error) {
                    print("⚠️ AuthenticatedLaunchHydration: fetchFamilyData failed — \(error.localizedDescription)")
                    return
                }
                try? await Task.sleep(nanoseconds: 400_000_000 * UInt64(attempt + 1))
            }
        }
    }

    /// Loads profile with retries; returns nil only when no row / unauthenticated, or after failures handled like launch.
    private static func loadUserProfileRetrying(dataManager: DataManager) async throws -> UserProfileData? {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await dataManager.loadUserProfile()
            } catch {
                lastError = error
                if attempt < 2, isTransientFailure(error) {
                    try? await Task.sleep(nanoseconds: 400_000_000 * UInt64(attempt + 1))
                    continue
                }
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    // MARK: - Core hydration (shared)

    /// Same behavior as the former `Miya_HealthApp.hydrateAuthenticatedLaunchState`: fetch family, load profile
    /// (max DB vs local step), guided context, AI consent. Call after `awaitSupabaseSessionReady()`.
    @MainActor
    static func hydrateAuthenticatedUser(
        dataManager: DataManager,
        onboardingManager: OnboardingManager
    ) async {
        await awaitSupabaseSessionReady()

        await fetchFamilyDataWithRetries(dataManager: dataManager)

        do {
            if let profile = try await loadUserProfileRetrying(dataManager: dataManager) {
                if let firstName = profile.first_name { onboardingManager.firstName = firstName }
                if let lastName = profile.last_name { onboardingManager.lastName = lastName }
                if let dobString = profile.date_of_birth, !dobString.isEmpty {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    onboardingManager.dateOfBirth = formatter.date(from: dobString)
                } else {
                    onboardingManager.dateOfBirth = nil
                }
                if let v = profile.gender { onboardingManager.gender = v }
                if let v = profile.ethnicity { onboardingManager.ethnicity = v }
                if let v = profile.smoking_status { onboardingManager.smokingStatus = v }
                if let v = profile.height_cm { onboardingManager.heightCm = v }
                if let v = profile.weight_kg { onboardingManager.weightKg = v }
                if let v = profile.blood_pressure_status { onboardingManager.bloodPressureStatus = v }
                if let v = profile.diabetes_status { onboardingManager.diabetesStatus = v }
                if let v = profile.has_prior_heart_attack { onboardingManager.hasPriorHeartAttack = v }
                if let v = profile.has_prior_stroke { onboardingManager.hasPriorStroke = v }
                if let v = profile.family_heart_disease_early { onboardingManager.familyHeartDiseaseEarly = v }
                if let v = profile.family_stroke_early { onboardingManager.familyStrokeEarly = v }
                if let v = profile.family_type2_diabetes { onboardingManager.familyType2Diabetes = v }
                if let v = profile.risk_band { onboardingManager.riskBand = v }
                if let v = profile.risk_points { onboardingManager.riskPoints = v }
                if let v = profile.optimal_vitality_target { onboardingManager.optimalVitalityTarget = v }
                onboardingManager.isOnboardingComplete = profile.onboarding_complete ?? false
                let dbStep = profile.onboarding_step ?? 1
                let localStep = onboardingManager.loadPersistedStep()
                let bestStep = max(dbStep, localStep)
                onboardingManager.setCurrentStep(bestStep)
#if DEBUG
                print("🔎 AuthenticatedLaunchHydration: profile hydrated, complete=\(onboardingManager.isOnboardingComplete), dbStep=\(dbStep), localStep=\(localStep), bestStep=\(bestStep)")
#endif
            } else {
                let localStep = onboardingManager.loadPersistedStep()
                onboardingManager.setCurrentStep(localStep)
                onboardingManager.isOnboardingComplete = false
            }
        } catch {
            print("⚠️ AuthenticatedLaunchHydration: failed to load user profile — \(error.localizedDescription)")
        }

        do {
            let types = try await dataManager.fetchConnectedWearableTypesForCurrentUser()
            onboardingManager.connectedWearables = types
        } catch {
#if DEBUG
            print("⚠️ AuthenticatedLaunchHydration: connected wearables — \(error.localizedDescription)")
#endif
        }

        await onboardingManager.refreshGuidedContextFromDB(dataManager: dataManager)
        await dataManager.refreshAIThirdPartyConsentFromServer()
    }
}
