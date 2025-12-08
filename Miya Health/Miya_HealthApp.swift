//
//  Miya_HealthApp.swift
//  Miya Health
//
//  The main entry point of the app.
//  Sets up all the managers so all views can use them.
//

import SwiftUI

@main
struct Miya_HealthApp: App {
    
    // Create the managers once when the app starts
    // @StateObject means they stay alive for the entire app lifetime
    @StateObject private var authManager = AuthManager()
    @StateObject private var dataManager = DataManager()
    @StateObject private var onboardingManager = OnboardingManager()
    
    init() {
        // Set up the dataManager reference in onboardingManager
        // This allows onboardingManager to save to database when step changes
        _onboardingManager.wrappedValue.dataManager = _dataManager.wrappedValue
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Make the managers available to ALL views in the app
                .environmentObject(authManager)
                .environmentObject(dataManager)
                .environmentObject(onboardingManager)
                .task {
                    // Restore persisted state first (fast, from UserDefaults)
                    dataManager.restorePersistedState()
                    
                    // Restore user session on app launch
                    await authManager.restoreSession()
                    
                    // If user is authenticated, fetch their family data (source of truth from DB)
                    if authManager.isAuthenticated {
                        do {
                            try await dataManager.fetchFamilyData()
                        } catch {
                            print("⚠️ Failed to fetch family data: \(error.localizedDescription)")
                        }
                    }
                }
        }
    }
}
