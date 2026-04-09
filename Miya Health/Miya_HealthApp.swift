//
//  Miya_HealthApp.swift
//  Miya Health
//
//  The main entry point of the app.
//  Sets up all the managers so all views can use them.
//

import SwiftUI
import RookSDK
import Supabase
import Combine
import UIKit

/// Notification posted when user logs out; triggers full session reset.
extension Notification.Name {
    static let userDidLogout = Notification.Name("userDidLogout")
    /// User tapped Retry after cold-start hydration timed out.
    static let miyaColdStartHydrationRetry = Notification.Name("miyaColdStartHydrationRetry")
    /// Notification posted when an API-based wearable (Oura/Whoop/Fitbit) successfully connects.
    /// Triggers automatic vitality scoring computation.
    static let apiWearableConnected = Notification.Name("apiWearableConnected")
    /// Notification posted after a user updates their profile (name, health fields, etc.).
    /// Used to refresh name-dependent UI (e.g. dashboard weekly badge winners).
    static let profileDidUpdate = Notification.Name("profileDidUpdate")
}

@main
struct Miya_HealthApp: App {

    // Enables ROOK background upload hooks (via UIKit app delegate).
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @Environment(\.scenePhase) private var scenePhase
    
    // Create the managers once when the app starts
    // @StateObject means they stay alive for the entire app lifetime
    @StateObject private var authManager = AuthManager()
    @StateObject private var dataManager = DataManager()
    @StateObject private var onboardingManager = OnboardingManager()
    @StateObject private var subscriptionManager = SubscriptionManager()

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
                .preferredColorScheme(.light) // Force light mode for consistent appearance across all devices
                .environmentObject(authManager)
                .environmentObject(dataManager)
                .environmentObject(onboardingManager)
                .environmentObject(subscriptionManager)
                .task {
                    await performColdStartRestore()
                }
                .onReceive(NotificationCenter.default.publisher(for: .miyaColdStartHydrationRetry)) { _ in
                    Task { @MainActor in
                        await performAuthenticatedHydrationRetry()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .userDidLogout)) { _ in
                    onboardingManager.reset()
                    dataManager.resetCaches()
                    subscriptionManager.reset()
                    authManager.isLoadingProfile = false
                    // `reset()` clears `isHydrated`; cold-start hydration does not run again until next launch.
                    // Sign-up paths (Get started) do not set `isHydrated` like the login sheet does—without this,
                    // the next session in the same launch can stay on “Syncing your profile…” forever.
                    onboardingManager.isHydrated = true
                    UserDefaults.standard.removeObject(forKey: "miya.hasSeenFamilyIntro")
                    appSessionId = UUID()
                    print("🔄 App: Session reset complete (logout)")
                }
                .onOpenURL { url in
                    Task {
                        try? await SupabaseConfig.client.auth.session(from: url)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active, authManager.isAuthenticated {
                        RookService.shared.syncIfStale(cooldownHours: 6)
                        Task {
                            await subscriptionManager.refreshForCurrentSession()
                        }
                        // Lightweight reconciliation: confirm auth session is still valid
                        // without triggering heavy profile reload. Prevents stale routing
                        // after extended background time.
                        Task {
                            await reconcileOnForeground()
                        }
                    }
                }
        }
    }
}

// MARK: - Cold start restore (timeouts, guaranteed loading clear, retry)

extension Miya_HealthApp {
    @MainActor
    fileprivate func performColdStartRestore() async {
        onboardingManager.dataManager = dataManager
        dataManager.restorePersistedState()
        authManager.isLoadingProfile = true
        authManager.needsLaunchRestoreRetry = false
        defer {
            authManager.isLoadingProfile = false
        }

        let sessionTimedOut = await raceTimeout(seconds: 18) {
            await authManager.restoreSession()
        }
        if sessionTimedOut {
            print("⚠️ Launch: session restore exceeded timeout; continuing with best-effort auth state")
        }

#if DEBUG
        print("🔎 LaunchRestore: isAuthenticated=\(authManager.isAuthenticated)")
#endif

        if authManager.isAuthenticated {
            UIApplication.shared.registerForRemoteNotifications()
            await subscriptionManager.refreshForCurrentSession()
        }

        await dataManager.clearFamilyCachesIfAuthChanged()

#if DEBUG
        Task(priority: .utility) {
            await dataManager.debugPrintGuidedSchemaState()
        }
#endif

        guard authManager.isAuthenticated else {
            onboardingManager.isHydrated = true
#if DEBUG
            print("🔎 HydrationReady: not authenticated → marked hydrated (will show auth entry)")
#endif
            return
        }

        let hydrationTimedOut = await raceTimeout(seconds: 45) {
            await hydrateAuthenticatedLaunchState()
        }
        onboardingManager.isHydrated = true
#if DEBUG
        print("🔎 HydrationReady: authenticated → step=\(onboardingManager.currentStep) complete=\(onboardingManager.isOnboardingComplete) timedOut=\(hydrationTimedOut)")
#endif
        if hydrationTimedOut {
            print("⚠️ Launch: authenticated hydration timed out")
            authManager.needsLaunchRestoreRetry = true
        }
    }

    /// Re-run only post-auth hydration after user taps Retry (e.g. slow network).
    @MainActor
    fileprivate func performAuthenticatedHydrationRetry() async {
        guard authManager.isAuthenticated else { return }
        authManager.isLoadingProfile = true
        authManager.needsLaunchRestoreRetry = false
        defer {
            authManager.isLoadingProfile = false
        }

        let timedOut = await raceTimeout(seconds: 45) {
            await hydrateAuthenticatedLaunchState()
        }
        onboardingManager.isHydrated = true
        if timedOut {
            authManager.needsLaunchRestoreRetry = true
        }
    }

    /// Returns `true` if the timeout branch won (work may be incomplete).
    @MainActor
    private func raceTimeout(seconds: Double, operation: @escaping @Sendable () async -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask {
                await operation()
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return true
            }
            let first = await group.next() ?? true
            group.cancelAll()
            return first
        }
    }

    /// Lightweight foreground reconciliation: confirm the Supabase session is still
    /// valid without re-running the full hydration pipeline. If the session has expired
    /// while the app was suspended, route the user to the logged-out state cleanly.
    @MainActor
    fileprivate func reconcileOnForeground() async {
        guard authManager.isAuthenticated else { return }
        do {
            _ = try await SupabaseConfig.client.auth.session
            await dataManager.refreshAIThirdPartyConsentFromServer()
        } catch {
#if DEBUG
            print("⚠️ ForegroundReconcile: session invalid after foreground — \(error.localizedDescription)")
#endif
            // Session expired while backgrounded; sign out cleanly so routing resets.
            try? await authManager.signOut()
        }
    }

    @MainActor
    fileprivate func hydrateAuthenticatedLaunchState() async {
        await AuthenticatedLaunchHydration.hydrateAuthenticatedUser(
            dataManager: dataManager,
            onboardingManager: onboardingManager
        )
    }
}
