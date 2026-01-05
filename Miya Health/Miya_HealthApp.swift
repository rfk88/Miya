//
//  Miya_HealthApp.swift
//  Miya Health
//
//  The main entry point of the app.
//  Sets up all the managers so all views can use them.
//

import SwiftUI
import RookSDK

/// Notification posted when user logs out; triggers full session reset.
extension Notification.Name {
    static let userDidLogout = Notification.Name("userDidLogout")
    /// Notification posted when an API-based wearable (Oura/Whoop/Fitbit) successfully connects.
    /// Triggers automatic vitality scoring computation.
    static let apiWearableConnected = Notification.Name("apiWearableConnected")
}

@main
struct Miya_HealthApp: App {

    // Enables ROOK background upload hooks (via UIKit app delegate).
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Create the managers once when the app starts
    // @StateObject means they stay alive for the entire app lifetime
    @StateObject private var authManager = AuthManager()
    @StateObject private var dataManager = DataManager()
    @StateObject private var onboardingManager = OnboardingManager()
    
    /// Session ID that changes on login/logout to force SwiftUI to rebuild the entire view hierarchy.
    /// This ensures zero state leakage between user sessions.
    @State private var appSessionId = UUID()
    
    init() {
        // Initialize Rook SDK at app launch
        _ = RookService.shared
        
        #if DEBUG
        // Validate vitality scoring schema on debug builds
        validateVitalityScoringSchema()
        
        // Uncomment to see schema examples in console:
        // ScoringSchemaExamples.runAllExamples()
        
        // Uncomment to run scoring engine smoke test:
        // ScoringSchemaExamples.runScoringEngineSmokeTest()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(appSessionId) // Forces full rebuild on session change
                // Make the managers available to ALL views in the app
                .environmentObject(authManager)
                .environmentObject(dataManager)
                .environmentObject(onboardingManager)
                .task {
                    // Wire manager references after the App's view hierarchy is installed.
                    // (Avoids "Accessing StateObject... without being installed on a View" warnings.)
                    onboardingManager.dataManager = dataManager
                    
                    // Restore persisted state first (fast, from UserDefaults)
                    dataManager.restorePersistedState()
                    
                    // Restore user session on app launch
                    await authManager.restoreSession()
                    
                    // Clear any cached family state if the auth user changed (prevents cross-account leakage)
                    await dataManager.clearFamilyCachesIfAuthChanged()

                    #if DEBUG
                    // Diagnostic-only: print whether guided onboarding schema exists in the connected Supabase database.
                    await dataManager.debugPrintGuidedSchemaState()
                    #endif
                    
                    // If user is authenticated, fetch their family data (source of truth from DB)
                    if authManager.isAuthenticated {
                        do {
                            try await dataManager.fetchFamilyData()
                        } catch {
                            print("⚠️ Failed to fetch family data: \(error.localizedDescription)")
                        }
                        
                        // Refresh guided context for status-first routing (e.g., force review screen)
                        await onboardingManager.refreshGuidedContextFromDB(dataManager: dataManager)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .userDidLogout)) { _ in
                    // Reset all state on logout
                    onboardingManager.reset()
                    dataManager.resetCaches()
                    appSessionId = UUID() // Force view hierarchy rebuild
                    print("🔄 App: Session reset complete (logout)")
                }
        }
    }
}
