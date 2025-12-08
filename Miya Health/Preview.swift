//
//  Preview.swift
//  Miya Health
//
//  Preview providers for SwiftUI canvas.
//

import SwiftUI

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(DataManager())
        .environmentObject(OnboardingManager())
}
