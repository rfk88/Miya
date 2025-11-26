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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Make the managers available to ALL views in the app
                .environmentObject(authManager)
                .environmentObject(dataManager)
                .environmentObject(onboardingManager)
        }
    }
}
