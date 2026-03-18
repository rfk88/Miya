//
//  OnboardingStepViews.swift
//  Miya Health
//
//  Onboarding step views and supporting UI. Edit onboarding screens here.
//

import RookSDK
import HealthKit
import SwiftUI
import UIKit

// MARK: - STEP 1: SUPERADMIN ONBOARDING (EMAIL + PASSWORD)

struct SuperadminOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Access the managers from the environment
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    
    // Form fields
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    
    // Navigation and error state
    @State private var navigateToNextStep: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isAppleSignInLoading: Bool = false

    private let totalSteps: Int = 7
    private let currentStep: Int = 1
    
    private var passwordsMatch: Bool {
        !password.isEmpty && !confirmPassword.isEmpty && password == confirmPassword
    }
    
    private var isFormValid: Bool {
        guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty,
              !lastName.trimmingCharacters(in: .whitespaces).isEmpty,
              !email.isEmpty,
              !password.isEmpty,
              !confirmPassword.isEmpty else { return false }
        guard password.count >= 8 else { return false }
        guard passwordsMatch else { return false }
        return true
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Progress bar
                    OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 16)
                
                // Title + subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Secure your family's health hub")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                        .multilineTextAlignment(.leading)
                    
                    Text("Your data, protected with bank-level security. 🔒")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Form
                VStack(spacing: 16) {
                    // Names row
                    HStack(spacing: 12) {
                    // First Name
                    VStack(alignment: .leading, spacing: 6) {
                            Text("First name")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                            TextField("First", text: $firstName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled(true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                            )
                        }
                        
                        // Last Name
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Last name")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            TextField("Last", text: $lastName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled(true)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                                )
                        }
                    }
                    
                    // Email
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email address")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        TextField("your.email@example.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                            )
                    }
                    
                    // Password
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create password")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        SecureField("Min. 8 characters", text: $password)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                            )
                    }
                    
                    // Confirm password + match tag
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Confirm password")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        SecureField("Retype your password", text: $confirmPassword)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                            )
                        
                        if !password.isEmpty || !confirmPassword.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .font(.system(size: 12, weight: .bold))
                                
                                Text(passwordsMatch ? "Passwords match" : "Passwords don't match")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                (passwordsMatch ? Color.green : Color.red)
                                    .opacity(0.12)
                            )
                            .foregroundColor(passwordsMatch ? .green : .red)
                            .cornerRadius(999)
                        }
                    }
                }
                
                // Error message (if any)
                if showError {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Buttons
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.clear)
                            .foregroundColor(.miyaTextSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.miyaBackground, lineWidth: 1)
                            )
                    }
                    .disabled(authManager.isLoading)

                    Button {
                        print("🟢 Continue button tapped!")
                        print("🟢 isFormValid: \(isFormValid)")
                        print("🟢 isLoading: \(authManager.isLoading)")
                        Task {
                            await signUp()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if authManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(authManager.isLoading ? "Creating account..." : "Continue")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isFormValid && !authManager.isLoading ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                    .disabled(!isFormValid || authManager.isLoading)
                }
                .padding(.bottom, 8)
                
                // Or sign in with Apple
                VStack(spacing: 12) {
                    HStack {
                        Rectangle().fill(Color.miyaBackground).frame(height: 1)
                        Text("Or sign in with Apple")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Rectangle().fill(Color.miyaBackground).frame(height: 1)
                    }
                    SignInWithAppleButtonView { idToken, nonce, fullName in
                        await handleAppleSignIn(idToken: idToken, nonce: nonce, fullName: fullName)
                    }
                    .disabled(isAppleSignInLoading || authManager.isLoading)
                }
                .padding(.bottom, 16)
                
                // Hidden NavigationLink for programmatic navigation
                NavigationLink(
                    destination: FamilySetupView(),
                    isActive: $navigateToNextStep
                ) {
                    EmptyView()
                }
                .hidden()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            print("📱 SuperadminOnboardingView appeared")
            print("📱 isFormValid: \(isFormValid)")
        }
        .onChange(of: firstName) { _ in
            print("📝 Form valid: \(isFormValid), firstName: '\(firstName)', email: '\(email)', password length: \(password.count)")
        }
        .onChange(of: email) { _ in
            print("📝 Form valid: \(isFormValid)")
        }
        .onChange(of: password) { _ in
            print("📝 Form valid: \(isFormValid), password length: \(password.count), passwords match: \(passwordsMatch)")
        }
    }
    
    // MARK: - Sign Up Function
    
    private func signUp() async {
        print("🔵 signUp() called")
        print("📧 Email: \(email)")
        print("👤 First Name: \(firstName)")
        
        showError = false
        
        do {
            print("🔄 Calling authManager.signUp()...")
            
            // Call the AuthManager to create the account
            let userId = try await authManager.signUp(
                email: email,
                password: password,
                firstName: firstName
            )
            
            print("✅ Sign up successful! User ID: \(userId)")
            
            // 🔥 CRITICAL: Create initial user_profile immediately (fixes abandon-at-step-1 bug)
            try await dataManager.createInitialProfile(   // uses injected dataManager
                userId: userId,
                firstName: firstName,
                step: 1
            )
            
            print("✅ Initial profile created for user")
            
            // Store the data in OnboardingManager for later steps
            onboardingManager.firstName = firstName
            onboardingManager.lastName = lastName
            onboardingManager.email = email
            onboardingManager.password = password
            onboardingManager.currentUserId = userId
            
            // Navigate to the next step
            navigateToNextStep = true
            
        } catch {
            // Show error to user
            print("❌ Sign up error: \(error)")
            print("❌ Error description: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func handleAppleSignIn(idToken: String, nonce: String?, fullName: PersonNameComponents?) async {
        showError = false
        isAppleSignInLoading = true
        defer { isAppleSignInLoading = false }
        do {
            let userId = try await authManager.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
            let first = fullName?.givenName ?? fullName?.familyName ?? "User"
            let last = fullName?.familyName ?? ""
            try await dataManager.createInitialProfile(userId: userId, firstName: first, step: 1)
            onboardingManager.currentUserId = userId
            onboardingManager.firstName = first
            onboardingManager.lastName = last
            navigateToNextStep = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview("Step 1: Superadmin sign up") {
    NavigationStack {
        SuperadminOnboardingView()
            .environmentObject(AuthManager())
            .environmentObject(OnboardingManager())
            .environmentObject(DataManager())
    }
}

// MARK: - STEP 2: FAMILY SETUP VIEW

struct FamilySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    @State private var familyName: String = ""
    @State private var selectedFamilySize: FamilySizeOption? = nil
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var navigateToNextStep: Bool = false
    
    private let totalSteps: Int = 7
    private let currentStep: Int = 2
    
    private var isFormValid: Bool {
        !familyName.trimmingCharacters(in: .whitespaces).isEmpty && selectedFamilySize != nil
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                        .padding(.top, 16)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Build your health team")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Let's set up your family's health journey.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What should we call your family?")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        TextField("e.g., The Johnson Family", text: $familyName)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How many people are in your family?")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        VStack(spacing: 10) {
                            FamilySizeOptionCard(
                                title: "2–4 family members",
                                subtitle: "Small but mighty crew.",
                                option: .twoToFour,
                                selectedOption: $selectedFamilySize
                            )
                            
                            FamilySizeOptionCard(
                                title: "4–8 family members",
                                subtitle: "A busy, full house.",
                                option: .fourToEight,
                                selectedOption: $selectedFamilySize
                            )
                            
                            FamilySizeOptionCard(
                                title: "9+ family members",
                                subtitle: "Big family, big impact.",
                                option: .ninePlus,
                                selectedOption: $selectedFamilySize
                            )
                        }
                    }
                }
                
                // Error message
                if showError {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.clear)
                            .foregroundColor(.miyaTextSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.miyaBackground, lineWidth: 1)
                            )
                    }
                    .disabled(dataManager.isLoading)
                    
                    Button {
                        Task {
                            await saveFamily()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if dataManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(dataManager.isLoading ? "Saving..." : "Continue")
                            .font(.system(size: 16, weight: .semibold))
                        }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        .background(isFormValid && !dataManager.isLoading ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(!isFormValid || dataManager.isLoading)
                }
                .padding(.bottom, 16)
                
                // Hidden NavigationLink for programmatic navigation
                NavigationLink(
                    destination: WearableSelectionView(),
                    isActive: $navigateToNextStep
                ) {
                    EmptyView()
                }
                .hidden()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Step 2: Family Setup
            onboardingManager.setCurrentStep(2)
        }
    }
    
    private func saveFamily() async {
        guard let familySize = selectedFamilySize else { return }
        
        showError = false
        errorMessage = ""
        
        do {
            // Save to OnboardingManager
            onboardingManager.familyName = familyName
            onboardingManager.familySize = familySize.rawValue
            
            // Save to database
            try await dataManager.saveFamily(
                name: familyName,
                size: familySize.rawValue,
                firstName: onboardingManager.firstName
            )
            
            // Navigate to next step
            navigateToNextStep = true
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview("Step: Family setup") {
    NavigationStack {
        FamilySetupView()
            .environmentObject(DataManager())
            .environmentObject(OnboardingManager())
    }
}

enum FamilySizeOption: String {
    case twoToFour
    case fourToEight
    case ninePlus
}

struct FamilySizeOptionCard: View {
    let title: String
    let subtitle: String
    let option: FamilySizeOption
    
    @Binding var selectedOption: FamilySizeOption?
    
    private var isSelected: Bool {
        selectedOption == option
    }
    
    var body: some View {
        Button {
            selectedOption = option
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextSecondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? .miyaPrimary : .miyaTextSecondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: isSelected ? Color.black.opacity(0.05) : .clear,
                            radius: 8, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.miyaPrimary : Color.miyaBackground.opacity(0.9),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SHARED: PROGRESS BAR + COLOURS

struct OnboardingProgressBar: View {
    let currentStep: Int
    let totalSteps: Int
    
    private var progress: CGFloat {
        guard totalSteps > 0 else { return 0 }
        return CGFloat(currentStep) / CGFloat(totalSteps)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step \(currentStep) of \(totalSteps)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.miyaTextSecondary)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.miyaBackground.opacity(0.9))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(Color.miyaPrimary)
                        .frame(width: geometry.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

// Colors are defined in Miya.swift
// MARK: - STEP 3: WEARABLE SELECTION

enum WearableType: String, CaseIterable, Identifiable {
    case appleWatch
    case whoop
    case oura
    case fitbit
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .whoop:      return "WHOOP"
        case .oura:       return "Oura Ring"
        case .fitbit:     return "Fitbit"
        }
    }
    
    // Placeholder SF Symbols – later you can replace with real logo assets in Assets.xcassets
    var systemImageName: String {
        switch self {
        case .appleWatch: return "applewatch"
        case .whoop:      return "bolt.heart"
        case .oura:       return "moon.stars"
        case .fitbit:     return "figure.walk"
        }
    }
    
    /// Maps to Rook's data source identifier for API-based sources
    /// Returns nil for Apple Health (handled by SDK, not API)
    var rookDataSourceId: String? {
        switch self {
        case .appleWatch: return nil  // Handled by SDK, not API
        case .whoop:      return "whoop"
        case .oura:       return "oura"
        case .fitbit:     return "fitbit"
        }
    }
    
    /// Returns true if this wearable uses Rook's REST API (not SDK)
    var isAPIBasedSource: Bool {
        rookDataSourceId != nil
    }
}

struct WearableSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    // Flag for invited users with Guided Setup (skip full onboarding after wearables)
    var isGuidedSetupInvite: Bool = false
    
    // Flag for dashboard reconnect mode (no onboarding navigation, just dismiss)
    var isReconnectMode: Bool = false
    
    @State private var selectedWearable: WearableType? = nil
    @State private var isConnecting: Bool = false
    @State private var connectionProgress: Double = 0.0
    @State private var connectedWearables: Set<WearableType> = []
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showAuthorizationView: Bool = false
    @State private var authorizationDataSource: String? = nil
    @State private var authorizationDataSourceName: String? = nil
    
    /// Shown when waiting for wearable connection to be verified (onboarding only). Never advance until connection is confirmed.
    @State private var isWaitingForConnection: Bool = false
    @State private var connectingWearableName: String? = nil
    
    private let totalSteps: Int = 7
    private let currentStep: Int = 2
    
    private var canContinue: Bool {
        let can = !connectedWearables.isEmpty
        if !can {
            print("⚠️ WearableSelectionView: canContinue = false (connectedWearables: \(connectedWearables.count))")
        } else {
            print("✅ WearableSelectionView: canContinue = true (connected: \(connectedWearables.map { $0.displayName }.joined(separator: ", ")))")
        }
        return can
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            if isWaitingForConnection {
                // Full-screen animated loading until connection is verified; keeps user engaged
                ConnectingWearableView(wearableName: connectingWearableName ?? "wearable")
            } else {
            VStack(spacing: 24) {
                
                // Progress bar: Step 3 of 8 (only show in onboarding mode)
                if !isReconnectMode {
                    OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                        .padding(.top, 16)
                }
                
                // Title + subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text(isReconnectMode ? "Reconnect Wearables" : "Link your health tech")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text(isReconnectMode
                         ? "Reconnect your wearables to refresh your vitality data and recalculate your baseline."
                         : (isGuidedSetupInvite
                            ? "Connect a wearable so we can calculate your vitality while your admin completes the rest of your health profile."
                            : "We’ll sync automatically — set it and forget it ✨"))
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, isReconnectMode ? 16 : 0)
                
                // Wearable list
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(WearableType.allCases.filter { $0 != .appleWatch }) { wearable in
                        WearableCard(
                            wearable: wearable,
                            isSelected: selectedWearable == wearable,
                            isConnecting: isConnecting && selectedWearable == wearable,
                            progress: connectionProgress,
                            isConnected: connectedWearables.contains(wearable)
                        ) {
                            handleConnectTapped(for: wearable)
                        }
                    }
                    
                    // Apple Watch / Rook Connect button
                    Button {
                        presentRookConnect()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "applewatch")
                                .font(.system(size: 26))
                                .frame(width: 36, height: 36)
                                .foregroundColor(.miyaPrimary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Apple Watch")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)
                                
                                Text("Connect via Apple Health")
                                    .font(.system(size: 13))
                                    .foregroundColor(.miyaTextSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
                        )
                    }
                }
                
                Spacer()
                
                // Back + Continue / Done
                HStack(spacing: 12) {
                    if !isReconnectMode {
                        Button {
                            dismiss()
                        } label: {
                            Text("Back")
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.clear)
                                .foregroundColor(.miyaTextSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.miyaBackground, lineWidth: 1)
                                )
                        }
                    }
                    
                    // In reconnect mode, just show Done button
                    if isReconnectMode {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.miyaPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                        }
                    } else {
                        // Navigation depends on whether this is a guided setup invite
                        if isGuidedSetupInvite {
                            // Guided Setup: After wearables, take them directly to onboarding complete (dashboard).
                            NavigationLink {
                                OnboardingCompleteView(membersCount: 0)
                                    .environmentObject(onboardingManager)
                                    .environmentObject(dataManager)
                            } label: {
                                Text("Continue")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(canContinue ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                            }
                            .disabled(!canContinue)
                        } else {
                            // Normal flow: Go to Step 4 (AboutYouView)
                            NavigationLink {
                                AboutYouView()
                            } label: {
                                Text("Continue")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(canContinue ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                            }
                            .disabled(!canContinue)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
            // Watch the animated progress to mark connection complete
            .onChange(of: connectionProgress) { newValue in
                if newValue >= 1.0, isConnecting {
                    Task {
                        await completeConnection()
                    }
                }
            }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showAuthorizationView) {
            if let dataSource = authorizationDataSource,
               let dataSourceName = authorizationDataSourceName {
                NavigationStack {
                    RookAuthorizationFlowView(
                        dataSource: dataSource,
                        dataSourceName: dataSourceName
                    )
                    .environmentObject(authManager)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Cancel") {
                                print("🟡 WearableSelectionView: User cancelled authorization")
                                showAuthorizationView = false
                            }
                        }
                    }
                }
                .onDisappear {
                    print("🟡 WearableSelectionView: Authorization view dismissed")
                    // When returning from OAuth: show loader and poll until connection is verified (onboarding only)
                    if !isReconnectMode, authorizationDataSource != nil {
                        isWaitingForConnection = true
                        connectingWearableName = authorizationDataSourceName
                        Task {
                            await pollUntilAPIConnectionVerified()
                        }
                    } else {
                        Task {
                            await checkAPIWearableConnectionStatus()
                        }
                    }
                }
            } else {
                // Fallback if data source info is missing
                VStack(spacing: 16) {
                    Text("Error")
                        .font(.headline)
                    Text("Missing authorization information")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Close") {
                        showAuthorizationView = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .onChange(of: showAuthorizationView) { newValue in
            print("📊 WearableSelectionView: showAuthorizationView changed to \(newValue)")
            if newValue {
                print("   - dataSource: \(authorizationDataSource ?? "nil")")
                print("   - dataSourceName: \(authorizationDataSourceName ?? "nil")")
            }
        }
        .onAppear {
            // Step 2: Wearables (only in onboarding mode)
            if !isReconnectMode {
                onboardingManager.setCurrentStep(2)
            }
            // Check connection status for API-based wearables on appear
            Task {
                await checkAPIWearableConnectionStatus()
            }
        }
    }
    
    private func handleConnectTapped(for wearable: WearableType) {
        print("🟢 WearableSelectionView: handleConnectTapped for \(wearable.displayName)")
        
        // If already connected, do nothing
        if connectedWearables.contains(wearable) {
            print("⚠️ WearableSelectionView: \(wearable.displayName) already connected")
            return
        }
        
        if isConnecting {
            print("⚠️ WearableSelectionView: Already connecting, ignoring tap")
            return
        }
        
        selectedWearable = wearable
        
        // Route based on source type
        if wearable.isAPIBasedSource {
            print("🟢 WearableSelectionView: \(wearable.displayName) is API-based, starting OAuth flow")
            // API-based source: Use OAuth authorization flow
            Task {
                print("📡 WearableSelectionView: Getting user ID...")
                guard let userId = await authManager.getCurrentUserId() else {
                    print("❌ WearableSelectionView: No user ID available")
                    await MainActor.run {
                        errorMessage = "Please sign in first to connect your wearable."
                        showError = true
                    }
                    return
                }
                
                print("✅ WearableSelectionView: Got user ID: \(userId)")
                
                guard let dataSourceId = wearable.rookDataSourceId else {
                    print("❌ WearableSelectionView: No Rook data source ID for \(wearable.displayName)")
                    await MainActor.run {
                        errorMessage = "Invalid data source"
                        showError = true
                    }
                    return
                }
                
                print("🟢 WearableSelectionView: Setting authorization view for \(dataSourceId)")
                await MainActor.run {
                    authorizationDataSource = dataSourceId
                    authorizationDataSourceName = wearable.displayName
                    showAuthorizationView = true
                    print("✅ WearableSelectionView: showAuthorizationView = true")
                }
            }
        } else {
            // Apple Health: Use existing SDK flow (via "Connect with Rook" button)
            // For now, show a message directing user to use the Rook Connect button
            print("ℹ️ WearableSelectionView: \(wearable.displayName) is SDK-based, directing to Rook Connect button")
            errorMessage = "Please use the 'Connect with Rook' button below to connect Apple Health."
            showError = true
        }
    }
    
    private func completeConnection() async {
        guard let selected = selectedWearable else { return }
        
        // This function is only called for the mock animation flow
        // API-based sources handle connection completion in checkAPIWearableConnectionStatus
        isConnecting = false
        connectedWearables.insert(selected)
        
        // Save to OnboardingManager
        onboardingManager.connectedWearables.append(selected.rawValue)
        
        // Save to database
        do {
            try await dataManager.saveWearable(wearableType: selected.rawValue)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            // Remove from connected set if save failed
            connectedWearables.remove(selected)
        }
    }
    
    /// Advance to next onboarding step only after wearable is verified connected. Call only from verified-connected code paths.
    private func advanceOnboardingAfterWearableConnection() {
        if isReconnectMode { return }
        if isGuidedSetupInvite {
            onboardingManager.completeOnboarding()
            Task {
                await onboardingManager.refreshGuidedContextFromDB(dataManager: dataManager)
            }
        } else {
            onboardingManager.setCurrentStep(3)
        }
    }
    
    /// Check connection status for all API-based wearables
    private func checkAPIWearableConnectionStatus() async {
        guard let userId = await authManager.getCurrentUserId() else {
            return
        }
        
        // Check status for each API-based wearable
        for wearable in WearableType.allCases where wearable.isAPIBasedSource {
            guard let dataSourceId = wearable.rookDataSourceId else { continue }
            
            do {
                let isConnected = try await RookAPIService.shared.checkConnectionStatus(
                    dataSource: dataSourceId,
                    userId: userId
                )
                
                // Check if this was already connected before updating state
                let wasAlreadyConnected = await MainActor.run {
                    connectedWearables.contains(wearable)
                }
                
                await MainActor.run {
                    if isConnected {
                        connectedWearables.insert(wearable)
                        // Save to database if not already saved
                        if !onboardingManager.connectedWearables.contains(wearable.rawValue) {
                            onboardingManager.connectedWearables.append(wearable.rawValue)
                        }
                    } else {
                        connectedWearables.remove(wearable)
                    }
                }
                
                // Await save so we only advance after connection is verified and persisted
                if isConnected && !wasAlreadyConnected {
                    do {
                        try await dataManager.saveWearable(wearableType: wearable.rawValue)
                    } catch {
                        print("⚠️ WearableSelectionView: Failed to save \(wearable.displayName): \(error.localizedDescription)")
                    }
                }
                
                // AUTO_API_SCORING_TRIGGERED: If this is a newly connected API-based wearable,
                // post notification to trigger automatic vitality scoring
                // (Post outside MainActor.run to avoid async issues)
                if isConnected && !wasAlreadyConnected && wearable.isAPIBasedSource {
                    print("🟢 AUTO_API_SCORING_TRIGGERED: wearable=\(wearable.displayName) userId=\(userId)")
                    NotificationCenter.default.post(
                        name: .apiWearableConnected,
                        object: nil,
                        userInfo: [
                            "wearableType": wearable.rawValue,
                            "wearableName": wearable.displayName,
                            "userId": userId
                        ]
                    )
                    // Onboarding: only advance when we have verified this wearable and we were waiting for it
                    if !isReconnectMode, isWaitingForConnection, wearable.rookDataSourceId == authorizationDataSource {
                        await MainActor.run {
                            isWaitingForConnection = false
                            advanceOnboardingAfterWearableConnection()
                        }
                    }
                }
            } catch {
                print("⚠️ WearableSelectionView: Error checking status for \(wearable.displayName): \(error.localizedDescription)")
            }
        }
    }
    
    /// Poll API connection status until the wearable we're waiting for is verified, or timeout (~60s).
    private func pollUntilAPIConnectionVerified() async {
        let maxAttempts = 20
        let delaySeconds: UInt64 = 3_000_000_000 // 3 seconds
        for _ in 0..<maxAttempts {
            await checkAPIWearableConnectionStatus()
            let stillWaiting = await MainActor.run { isWaitingForConnection }
            if !stillWaiting { return }
            try? await Task.sleep(nanoseconds: delaySeconds)
        }
        await MainActor.run {
            if isWaitingForConnection {
                isWaitingForConnection = false
                errorMessage = "Connection didn’t complete. Please try again."
                showError = true
            }
        }
    }
    
    // MARK: - Rook Connect Helper
    
    private func presentRookConnect() {
        // 1. Get the authenticated user's ID - required for Rook to know which user's data this is
        Task {
            guard let userId = await authManager.getCurrentUserId() else {
                await MainActor.run {
                    print("🔴 RookConnect: No authenticated user - cannot connect to Rook")
                    errorMessage = "Please sign in first to connect your wearable."
                    showError = true
                }
                return
            }
            
            await MainActor.run {
                print("🟢 RookConnect: Starting connection for user: \(userId)")
            }
            
            // 2. Set the user ID with Rook SDK (tells Rook who this user is)
            // IMPORTANT: Wait for user registration to succeed before requesting permissions + syncing.
            RookService.shared.setUserId(userId) { ok in
                guard ok else {
                    DispatchQueue.main.async {
                        print("🔴 RookConnect: Failed to register user with Rook")
                        errorMessage = "Unable to connect to Rook right now. Please try again."
                        showError = true
                    }
                    return
                }

                // 3. Request Apple Health permissions
                DispatchQueue.main.async {
                    let permissionsManager = RookConnectPermissionsManager()
                    print("🟢 RookConnect: Requesting Apple Health permissions (sandbox)")
                    // Onboarding: show loader so when user returns from permission sheet we show "Connecting..." until save completes
                    if !self.isReconnectMode {
                        self.isWaitingForConnection = true
                        self.connectingWearableName = "Apple Health"
                    }
                    
                    permissionsManager.requestAllPermissions { _ in
                        DispatchQueue.main.async {
                            print("🟢 RookConnect: Permission screen flow finished")
                            
                            // HealthKit read permissions do not reliably reflect in `authorizationStatus`.
                            // Treat the completed permission flow as a successful connect to avoid blocking onboarding.
                            print("✅ RookConnect: Permission flow finished - marking Apple Health as connected")
                            Task { @MainActor in
                                let appleHealthWearable = WearableType.appleWatch
                                let wasAlreadyConnected = connectedWearables.contains(appleHealthWearable)
                                connectedWearables.insert(appleHealthWearable)
                                
                                // Save to OnboardingManager
                                if !onboardingManager.connectedWearables.contains(appleHealthWearable.rawValue) {
                                    onboardingManager.connectedWearables.append(appleHealthWearable.rawValue)
                                }
                                
                                // Save to database
                                do {
                                    try await dataManager.saveWearable(wearableType: appleHealthWearable.rawValue)
                                    print("✅ RookConnect: Apple Health saved to database")
                                    
                                    // Post notification to trigger automatic vitality scoring (same as API-based wearables)
                                    if !wasAlreadyConnected {
                                        NotificationCenter.default.post(
                                            name: .apiWearableConnected,
                                            object: nil,
                                            userInfo: [
                                                "wearableType": appleHealthWearable.rawValue,
                                                "wearableName": appleHealthWearable.displayName,
                                                "userId": userId
                                            ]
                                        )
                                        print("✅ RookConnect: Posted apiWearableConnected notification for Apple Health")
                                    }
                                    // Onboarding: only advance after verified save; hide loader
                                    isWaitingForConnection = false
                                    advanceOnboardingAfterWearableConnection()
                                } catch {
                                    print("⚠️ RookConnect: Failed to save Apple Health to database: \(error.localizedDescription)")
                                    isWaitingForConnection = false
                                    errorMessage = error.localizedDescription
                                    showError = true
                                }
                            }

                        #if DEBUG
                        // Debug helper: read today's steps locally to confirm HealthKit access
                        func debugPrintTodaySteps() {
                            guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
                                print("🔎 HealthKit debug – steps type unavailable")
                                return
                            }
                            let startOfDay = Calendar.current.startOfDay(for: Date())
                            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: [])
                            let query = HKStatisticsQuery(quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                                let count = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                                print("🔎 HealthKit debug – steps today:", count)
                            }
                            HKHealthStore().execute(query)
                        }
                        debugPrintTodaySteps()
                        #endif
                        
                        // 4. After permissions granted, trigger data sync via SDK
                        // This uses RookSummaryManager to sync sleep, physical, and body data
                        // NOTE: Apple Health backfill is limited; we cap to ~29 days.
                        RookService.shared.syncHealthData(backfillDays: 29)
                        
                        print("🟢 RookConnect: Sync triggered - data will arrive via webhook")
                        }
                    }
                }
            }
        }
    }
}

#Preview("Step: Wearable selection") {
    NavigationStack {
        WearableSelectionView()
            .environmentObject(AuthManager())
            .environmentObject(DataManager())
            .environmentObject(OnboardingManager())
    }
}

/// Full-screen animated view shown while waiting for wearable connection to be verified during onboarding.
private struct ConnectingWearableView: View {
    let wearableName: String
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                // Pulsing ring
                Circle()
                    .stroke(Color.miyaPrimary.opacity(0.2), lineWidth: 4)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.miyaPrimary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            }
            .frame(height: 100)
            VStack(spacing: 8) {
                Text("Connecting your \(wearableName)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                    .multilineTextAlignment(.center)
                Text("This usually takes a few seconds.")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isAnimating = true }
    }
}

struct WearableCard: View {
    let wearable: WearableType
    let isSelected: Bool
    let isConnecting: Bool
    let progress: Double
    let isConnected: Bool
    let onConnectTapped: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: wearable.systemImageName)
                    .font(.system(size: 26))
                    .frame(width: 36, height: 36)
                    .foregroundColor(.miyaPrimary)
                
                Text(wearable.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                Spacer()
            }
            
            HStack {
                if isConnected {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Connected")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.green)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(999)
                } else if isConnecting {
                    HStack(spacing: 10) {
                        CircularProgressView(progress: progress)
                            .frame(width: 24, height: 24)
                        Text("Connecting…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.miyaTextPrimary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.white)
                    .cornerRadius(999)
                } else {
                    Button(action: onConnectTapped) {
                        Text("Connect")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(999)
                    }
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: (isSelected || isConnected) ? Color.black.opacity(0.05) : .clear,
                        radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    (isSelected || isConnected) ? Color.miyaPrimary : Color.miyaBackground.opacity(0.9),
                    lineWidth: (isSelected || isConnected) ? 1.5 : 1
                )
        )
    }
}

// Simple circular progress (0–1)
struct CircularProgressView: View {
    let progress: Double   // 0.0 to 1.0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.miyaBackground, lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.miyaPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
// MARK: - STEP 4: ABOUT YOU

enum Gender: String, CaseIterable, Identifiable {
    case male = "Male"
    case female = "Female"
    
    var id: String { rawValue }
    
}

enum Ethnicity: String, CaseIterable, Identifiable {
    case white = "White"
    case asian = "Asian"
    case black = "Black"
    case hispanic = "Hispanic"
    case other = "Other"
    
    var id: String { rawValue }
}

enum SmokingStatus: String, CaseIterable, Identifiable {
    case never = "Never"
    case former = "Former"
    case current = "Current"
    
    var id: String { rawValue }
    
    var displayText: String {
        switch self {
        case .never: return "I've never smoked"
        case .former: return "I used to smoke (quit more than 1 year ago)"
        case .current: return "I currently smoke or use tobacco products"
        }
    }
}

#Preview("Step: About you") {
    NavigationStack {
        AboutYouView()
            .environmentObject(DataManager())
            .environmentObject(OnboardingManager())
    }
}

struct AboutYouView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    private let totalSteps: Int = 7
    private let currentStep: Int = 3
    
    @State private var selectedGender: Gender? = nil
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var selectedEthnicity: Ethnicity? = nil
    @State private var smokingStatus: SmokingStatus? = nil
    
    // Height/Weight with imperial support
    @State private var useImperial: Bool = false
    @State private var heightCm: String = ""
    @State private var heightFeet: String = ""
    @State private var heightInches: String = ""
    @State private var weightKg: String = ""
    @State private var weightLbs: String = ""
    @State private var nutritionQuality: Double = 3   // 1–5
    
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var navigateToNextStep: Bool = false
    
    // Computed properties
    private var age: Int {
        let components = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date())
        return components.year ?? 0
    }
    
    private var showBreakouts: Bool {
        // Show educational breakouts only for self-onboarding (not guided setup)
        onboardingManager.guidedSetupStatus == nil
    }
    
    // Convert imperial to metric for storage
    private var heightInCm: Double? {
        if useImperial {
            guard let feet = Double(heightFeet), let inches = Double(heightInches.isEmpty ? "0" : heightInches) else { return nil }
            let totalInches = (feet * 12) + inches
            return totalInches * 2.54
        } else {
            return Double(heightCm)
        }
    }
    
    private var weightInKg: Double? {
        if useImperial {
            guard let lbs = Double(weightLbs) else { return nil }
            return lbs * 0.453592
        } else {
            return Double(weightKg)
        }
    }
    
    private var isFormValid: Bool {
        guard selectedGender != nil,
              selectedEthnicity != nil,
              smokingStatus != nil else { return false }
        
        if useImperial {
            guard !heightFeet.trimmingCharacters(in: .whitespaces).isEmpty,
                  !weightLbs.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        } else {
            guard !heightCm.trimmingCharacters(in: .whitespaces).isEmpty,
                  !weightKg.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        }
        
        return true
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Progress
                OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 16)
                
                // Title + subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text("About you")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Tell us about yourself. Your data is private and secure.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // FORM
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        
                        // Biological Sex
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What is your sex? *")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Biological sex affects cardiovascular risk calculations.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("We use this for medical accuracy, not identity.")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                            .padding(.bottom, 4)
                            
                            Menu {
                                ForEach(Gender.allCases) { gender in
                                    Button(gender.rawValue) {
                                        selectedGender = gender
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedGender?.rawValue ?? "Select gender")
                                        .foregroundColor(
                                            selectedGender == nil ? .miyaTextSecondary : .miyaTextPrimary
                                        )
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.miyaTextSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                                )
                            }
                        }
                        
                        // Date of Birth
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Date of birth *")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            DatePicker(
                                "Date of birth",
                                selection: $dateOfBirth,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                            )
                        }
                        
                        // Ethnicity
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ethnicity *")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Menu {
                                ForEach(Ethnicity.allCases) { ethnicity in
                                    Button(ethnicity.rawValue) {
                                        selectedEthnicity = ethnicity
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedEthnicity?.rawValue ?? "Select ethnicity")
                                        .foregroundColor(
                                            selectedEthnicity == nil ? .miyaTextSecondary : .miyaTextPrimary
                                        )
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.miyaTextSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                                )
                            }
                        }
                        
                        // Smoking status
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What is your smoking status? *")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("Vaping/e-cigarettes count as tobacco use.")
                                .font(.system(size: 12))
                                .foregroundColor(.miyaTextSecondary)
                            
                            VStack(spacing: 8) {
                                ForEach(SmokingStatus.allCases) { status in
                                    Button {
                                        smokingStatus = status
                                    } label: {
                                        HStack {
                                            Text(status.displayText)
                                                .font(.system(size: 14))
                                                .foregroundColor(.miyaTextPrimary)
                                            Spacer()
                                            if smokingStatus == status {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.miyaPrimary)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(smokingStatus == status ? Color.miyaPrimary.opacity(0.1) : Color.white)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(smokingStatus == status ? Color.miyaPrimary : Color.miyaBackground.opacity(0.8), lineWidth: 1)
                                        )
                                    }
                                }
                            }
                            
                            Text("Tobacco use is one of the most significant factors affecting heart health.")
                                .font(.system(size: 11))
                                .foregroundColor(.miyaTextSecondary)
                                .italic()
                        }
                        
                        
                        // Body Measurements Header with Unit Toggle
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Body Measurements")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)
                                
                                Spacer()
                                
                                // Unit Toggle
                                Picker("Units", selection: $useImperial) {
                                    Text("Metric").tag(false)
                                    Text("Imperial").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 140)
                            }
                            
                            Text("Used to calculate BMI for health assessment.")
                                .font(.system(size: 12))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        
                        // Height
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Height *")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            if useImperial {
                                HStack(spacing: 12) {
                                    HStack {
                                        TextField("5", text: $heightFeet)
                                            .keyboardType(.numberPad)
                                            .frame(width: 50)
                                        Text("ft")
                                            .foregroundColor(.miyaTextSecondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1))
                                    
                                    HStack {
                                        TextField("7", text: $heightInches)
                                            .keyboardType(.numberPad)
                                            .frame(width: 50)
                                        Text("in")
                                            .foregroundColor(.miyaTextSecondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1))
                                }
                            } else {
                                TextField("e.g. 170", text: $heightCm)
                                .keyboardType(.decimalPad)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1))
                            }
                        }
                        
                        // Weight
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Weight *")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            if useImperial {
                                HStack {
                                    TextField("154", text: $weightLbs)
                                .keyboardType(.decimalPad)
                                    Text("lbs")
                                        .foregroundColor(.miyaTextSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1))
                            } else {
                                HStack {
                                    TextField("70", text: $weightKg)
                                        .keyboardType(.decimalPad)
                                    Text("kg")
                                        .foregroundColor(.miyaTextSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1))
                            }
                        }
                        
                        // Under-18 note
                        if age < 18 && age > 0 {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.orange)
                                Text("Risk assessments are designed for adults. Results may be less accurate for those under 18.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        // Nutrition quality
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nutrition quality (1–5)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            HStack {
                                Text("Low")
                                    .font(.system(size: 12))
                                    .foregroundColor(.miyaTextSecondary)
                                Slider(value: $nutritionQuality, in: 1...5, step: 1)
                                Text("High")
                                    .font(.system(size: 12))
                                    .foregroundColor(.miyaTextSecondary)
                            }
                            
                            Text("You rated: \(Int(nutritionQuality)) / 5")
                                .font(.system(size: 12))
                                .foregroundColor(.miyaTextSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(Color.miyaBackground)
                
                // Error message
                if showError {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Buttons
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.clear)
                            .foregroundColor(.miyaTextSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.miyaBackground, lineWidth: 1)
                            )
                    }
                    .disabled(dataManager.isLoading)
                    
                    Button {
                        Task {
                            await saveProfile()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if dataManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(dataManager.isLoading ? "Saving..." : "Continue")
                            .font(.system(size: 16, weight: .semibold))
                        }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        .background(isFormValid && !dataManager.isLoading ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(!isFormValid || dataManager.isLoading)
                }
                .padding(.bottom, 16)
                
                // Hidden NavigationLink for programmatic navigation
                NavigationLink(
                    destination: Group {
                        if showBreakouts {
                            Breakout1View()
                                .environmentObject(onboardingManager)
                                .environmentObject(dataManager)
                        } else {
                            HeartHealthView()
                        }
                    },
                    isActive: $navigateToNextStep
                ) {
                    EmptyView()
                }
                .hidden()
            }
            .padding(.horizontal, 24)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Step 3: About You
            onboardingManager.setCurrentStep(3)
        }
    }
    
    private func saveProfile() async {
        showError = false
        errorMessage = ""
        
        // Always convert to metric for storage (backend stores cm/kg)
        let heightValue = heightInCm
        let weightValue = weightInKg
        
        do {
            // Save to OnboardingManager (always in metric)
            onboardingManager.gender = selectedGender?.rawValue ?? ""
            onboardingManager.dateOfBirth = dateOfBirth
            onboardingManager.ethnicity = selectedEthnicity?.rawValue ?? ""
            onboardingManager.smokingStatus = smokingStatus?.rawValue ?? ""
            onboardingManager.heightCm = heightValue ?? 0
            onboardingManager.weightKg = weightValue ?? 0
            onboardingManager.nutritionQuality = Int(nutritionQuality)
            
            // Save to database (lastName from onboardingManager, always metric values)
            try await dataManager.saveUserProfile(
                lastName: onboardingManager.lastName,
                gender: selectedGender?.rawValue,
                dateOfBirth: dateOfBirth,
                ethnicity: selectedEthnicity?.rawValue,
                smokingStatus: smokingStatus?.rawValue,
                heightCm: heightValue,
                weightKg: weightValue,
                nutritionQuality: Int(nutritionQuality),
                onboardingStep: onboardingManager.currentStep
            )
            
            // Navigate to next step
            navigateToNextStep = true
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}


// Small pill button for smoking status
struct SmokingPill: View {
    let label: String
    let status: SmokingStatus
    @Binding var selected: SmokingStatus?
    
    private var isSelected: Bool {
        selected == status
    }
    
    var body: some View {
        Button {
            selected = status
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(isSelected ? Color.miyaPrimary : Color.white)
                .foregroundColor(isSelected ? .white : .miyaTextPrimary)
                .cornerRadius(999)
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(isSelected ? Color.miyaPrimary : Color.miyaBackground.opacity(0.9), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
// MARK: - STEP 5: HEART HEALTH (WHO Risk)

// Blood Pressure Status Options
enum BloodPressureStatus: String, CaseIterable, Identifiable {
    case normal = "normal"
    case elevatedUntreated = "elevated_untreated"
    case elevatedTreated = "elevated_treated"
    case unknown = "unknown"
    
    var id: String { rawValue }
    
    var displayText: String {
        switch self {
        case .normal: return "Normal (never told it's high)"
        case .elevatedUntreated: return "Told it's high, not on medication"
        case .elevatedTreated: return "Told it's high, on medication"
        case .unknown: return "Never checked / Not sure"
        }
    }
}

// Diabetes Status Options
enum DiabetesStatus: String, CaseIterable, Identifiable {
    case none = "none"
    case preDiabetic = "pre_diabetic"
    case type1 = "type_1"
    case type2 = "type_2"
    case unknown = "unknown"
    
    var id: String { rawValue }
    
    var displayText: String {
        switch self {
        case .none: return "No diabetes"
        case .preDiabetic: return "Pre-diabetic"
        case .type1: return "Type 1 diabetes"
        case .type2: return "Type 2 diabetes"
        case .unknown: return "Not sure"
        }
    }
}

struct HeartHealthView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    private let totalSteps: Int = 7
    private let currentStep: Int = 4
    
    // WHO Risk fields (nil = no selection; user must explicitly choose)
    @State private var bloodPressureStatus: BloodPressureStatus? = nil
    @State private var diabetesStatus: DiabetesStatus? = nil
    @State private var hasPriorHeartAttack: Bool = false
    @State private var hasPriorStroke: Bool = false
    @State private var noPriorEvents: Bool = false  // "None of the above"
    
    // Medical conditions
    @State private var hasChronicKidneyDisease: Bool = false
    @State private var hasAtrialFibrillation: Bool = false
    @State private var hasHighCholesterol: Bool = false
    @State private var noMedicalConditions: Bool = false  // "None of the above"
    
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var navigateToNextStep: Bool = false
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Progress
                OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 16)
                
                // Title + subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Heart health")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("This helps us understand your cardiovascular health. Answer as best you can.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // Blood Pressure Status
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What is your blood pressure status?")
                                .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                            
                            Text("High blood pressure (hypertension) often has no symptoms. If you're unsure, select 'never checked' and we'll remind you to get it tested.")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            VStack(spacing: 8) {
                                ForEach(BloodPressureStatus.allCases) { status in
                                    Button {
                                        bloodPressureStatus = status
                                    } label: {
                                        HStack {
                                            Text(status.displayText)
                                                .font(.system(size: 14))
                                                .foregroundColor(.miyaTextPrimary)
                                            Spacer()
                                            if bloodPressureStatus == status {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.miyaPrimary)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(bloodPressureStatus == status ? Color.miyaPrimary.opacity(0.1) : Color.white)
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(bloodPressureStatus == status ? Color.miyaPrimary : Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }
                        
                        // Diabetes Status
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Do you have diabetes or pre-diabetes?")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("Diabetes and pre-diabetes significantly affect cardiovascular health. Knowing your status helps us provide better guidance.")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            VStack(spacing: 8) {
                                ForEach(DiabetesStatus.allCases) { status in
                                    Button {
                                        diabetesStatus = status
                                    } label: {
                                        HStack {
                                            Text(status.displayText)
                                                .font(.system(size: 14))
                                                .foregroundColor(.miyaTextPrimary)
                                            Spacer()
                                            if diabetesStatus == status {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.miyaPrimary)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(diabetesStatus == status ? Color.miyaPrimary.opacity(0.1) : Color.white)
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(diabetesStatus == status ? Color.miyaPrimary : Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }
                        
                        // Prior Cardiovascular Events
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Medical History")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("Have you ever had any of the following? (Check all that apply)")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                            
                            VStack(spacing: 8) {
                        SelectableConditionRow(
                                    title: "Heart attack",
                                    isSelected: Binding(
                                        get: { hasPriorHeartAttack },
                                        set: { newValue in
                                            hasPriorHeartAttack = newValue
                                            if newValue { noPriorEvents = false }
                                        }
                                    )
                        )
                        
                        SelectableConditionRow(
                                    title: "Stroke",
                                    isSelected: Binding(
                                        get: { hasPriorStroke },
                                        set: { newValue in
                                            hasPriorStroke = newValue
                                            if newValue { noPriorEvents = false }
                                        }
                                    )
                        )
                        
                        SelectableConditionRow(
                                    title: "None of the above",
                                    isSelected: Binding(
                                        get: { noPriorEvents },
                                        set: { newValue in
                                            noPriorEvents = newValue
                                            if newValue {
                                                hasPriorHeartAttack = false
                                                hasPriorStroke = false
                                            }
                                        }
                                    ),
                                    isDisabled: hasPriorHeartAttack || hasPriorStroke
                                )
                            }
                        }
                        
                        // Other Medical Conditions
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Other Conditions")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("Do you have any of these conditions? (Check all that apply)")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                            
                            VStack(spacing: 8) {
                        SelectableConditionRow(
                                    title: "Chronic kidney disease",
                                    isSelected: Binding(
                                        get: { hasChronicKidneyDisease },
                                        set: { newValue in
                                            hasChronicKidneyDisease = newValue
                                            if newValue { noMedicalConditions = false }
                                        }
                                    )
                        )
                        
                        SelectableConditionRow(
                                    title: "Atrial fibrillation (irregular heartbeat)",
                                    isSelected: Binding(
                                        get: { hasAtrialFibrillation },
                                        set: { newValue in
                                            hasAtrialFibrillation = newValue
                                            if newValue { noMedicalConditions = false }
                                        }
                                    )
                                )
                                
                                SelectableConditionRow(
                                    title: "High cholesterol (diagnosed by doctor)",
                                    isSelected: Binding(
                                        get: { hasHighCholesterol },
                                        set: { newValue in
                                            hasHighCholesterol = newValue
                                            if newValue { noMedicalConditions = false }
                                        }
                                    )
                                )
                                
                                SelectableConditionRow(
                                    title: "None of the above",
                                    isSelected: Binding(
                                        get: { noMedicalConditions },
                                        set: { newValue in
                                            noMedicalConditions = newValue
                                            if newValue {
                                                hasChronicKidneyDisease = false
                                                hasAtrialFibrillation = false
                                                hasHighCholesterol = false
                                            }
                                        }
                                    ),
                                    isDisabled: hasChronicKidneyDisease || hasAtrialFibrillation || hasHighCholesterol
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(Color.miyaBackground)
                
                // Error message
                if showError {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Buttons
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.clear)
                            .foregroundColor(.miyaTextSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.miyaBackground, lineWidth: 1)
                            )
                    }
                    .disabled(dataManager.isLoading)
                    
                    Button {
                        Task {
                            await saveHeartHealth()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if dataManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(dataManager.isLoading ? "Saving..." : "Continue")
                            .font(.system(size: 16, weight: .semibold))
                        }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        .background(!dataManager.isLoading ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(dataManager.isLoading)
                }
                .padding(.bottom, 16)
                
                // Hidden NavigationLink for programmatic navigation
                NavigationLink(
                    destination: MedicalHistoryView(),
                    isActive: $navigateToNextStep
                ) {
                    EmptyView()
                }
                .hidden()
            }
            .padding(.horizontal, 24)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Step 4: Heart Health
            onboardingManager.setCurrentStep(4)
        }
    }
    
    private func saveHeartHealth() async {
        showError = false
        errorMessage = ""
        
        // Require both blood pressure and diabetes to be selected before saving
        guard let bp = bloodPressureStatus, let diab = diabetesStatus else {
            await MainActor.run {
                errorMessage = "Please select your blood pressure status and diabetes status."
                showError = true
            }
            return
        }
        
        // Save to OnboardingManager
        onboardingManager.bloodPressureStatus = bp.rawValue
        onboardingManager.diabetesStatus = diab.rawValue
        onboardingManager.hasPriorHeartAttack = hasPriorHeartAttack
        onboardingManager.hasPriorStroke = hasPriorStroke
        onboardingManager.hasChronicKidneyDisease = hasChronicKidneyDisease
        onboardingManager.hasAtrialFibrillation = hasAtrialFibrillation
        onboardingManager.hasHighCholesterol = hasHighCholesterol
        
        do {
            // Save EXACT condition types for accurate WHO risk scoring
            var conditions: [String: Bool] = [:]
            
            // Blood Pressure - save exact status
            switch bp {
            case .normal:
                conditions["bp_normal"] = true
            case .elevatedUntreated:
                conditions["bp_elevated_untreated"] = true
            case .elevatedTreated:
                conditions["bp_elevated_treated"] = true
            case .unknown:
                conditions["bp_unknown"] = true
            }
            
            // Diabetes - save exact type
            switch diab {
            case .none:
                conditions["diabetes_none"] = true
            case .preDiabetic:
                conditions["diabetes_pre_diabetic"] = true
            case .type1:
                conditions["diabetes_type_1"] = true
            case .type2:
                conditions["diabetes_type_2"] = true
            case .unknown:
                conditions["diabetes_unknown"] = true
            }
            
            // Prior events - save separately for accurate scoring
            if hasPriorHeartAttack {
                conditions["prior_heart_attack"] = true
            }
            if hasPriorStroke {
                conditions["prior_stroke"] = true
            }
            
            // Medical conditions
            if hasChronicKidneyDisease {
                conditions["chronic_kidney_disease"] = true
            }
            if hasAtrialFibrillation {
                conditions["atrial_fibrillation"] = true
            }
            if hasHighCholesterol {
                conditions["high_cholesterol"] = true
            }
            
            // Save to health_conditions table
            try await dataManager.saveHealthConditions(
                conditions: conditions,
                sourceStep: "heart_health"
            )
            
            // Navigate to next step
            navigateToNextStep = true
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview("Step: Heart health") {
    NavigationStack {
        HeartHealthView()
            .environmentObject(DataManager())
            .environmentObject(OnboardingManager())
    }
}

// MARK: - STEP 6: FAMILY HISTORY (WHO Risk)

struct MedicalHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    private let totalSteps: Int = 7
    private let currentStep: Int = 5
    
    // WHO Family History fields
    @State private var familyHeartDiseaseEarly: Bool = false
    @State private var familyStrokeEarly: Bool = false
    @State private var familyType2Diabetes: Bool = false
    @State private var isUnsure: Bool = false
    
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var navigateToNextStep: Bool = false
    
    private var showBreakouts: Bool {
        // Show educational breakouts only for self-onboarding (not guided setup)
        onboardingManager.guidedSetupStatus == nil
    }
    
    private var isGuidedInviteeAwaitingAdmin: Bool {
        onboardingManager.isInvitedUser && onboardingManager.guidedSetupStatus == .acceptedAwaitingData
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Progress
                OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 16)
                
                // Title + subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Family Health History")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Heart disease often runs in families. Understanding your family's health helps us assess your risk.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Do any of your parents or siblings have a history of the following? Think about your mother, father, brothers, and sisters.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.miyaTextPrimary)
                            .padding(.bottom, 8)
                        
                        Text("Family history before age 60 is particularly important because it suggests genetic factors.")
                            .font(.system(size: 12))
                            .foregroundColor(.miyaTextSecondary)
                            .italic()
                            .padding(.bottom, 4)
                        
                        SelectableConditionRow(
                            title: "Heart disease (heart attack, bypass surgery) before age 60",
                            isSelected: Binding(
                                get: { familyHeartDiseaseEarly },
                                set: { newValue in
                                    if !isUnsure {
                                        familyHeartDiseaseEarly = newValue
                                        // If selecting any option, clear "unsure"
                                        if newValue {
                                            isUnsure = false
                                        }
                                    }
                                }
                            ),
                            isDisabled: isUnsure
                        )
                        
                        SelectableConditionRow(
                            title: "Stroke before age 60",
                            isSelected: Binding(
                                get: { familyStrokeEarly },
                                set: { newValue in
                                    if !isUnsure {
                                        familyStrokeEarly = newValue
                                        // If selecting any option, clear "unsure"
                                        if newValue {
                                            isUnsure = false
                                        }
                                    }
                                }
                            ),
                            isDisabled: isUnsure
                        )
                        
                        SelectableConditionRow(
                            title: "Type 2 diabetes (at any age)",
                            isSelected: Binding(
                                get: { familyType2Diabetes },
                                set: { newValue in
                                    if !isUnsure {
                                        familyType2Diabetes = newValue
                                        // If selecting any option, clear "unsure"
                                        if newValue {
                                            isUnsure = false
                                        }
                                    }
                                }
                            ),
                            isDisabled: isUnsure
                        )
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        SelectableConditionRow(
                            title: "Not sure / None of these",
                            isSelected: Binding(
                                get: { isUnsure },
                                set: { newValue in
                                    isUnsure = newValue
                                    // If selecting "unsure", clear all other selections
                                    if newValue {
                                        familyHeartDiseaseEarly = false
                                        familyStrokeEarly = false
                                        familyType2Diabetes = false
                                    }
                                }
                            ),
                            isDisabled: familyHeartDiseaseEarly || familyStrokeEarly || familyType2Diabetes
                        )
                    }
                    .padding(.vertical, 4)
                }
                .background(Color.miyaBackground)
                
                // Error message
                if showError {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Buttons
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.clear)
                            .foregroundColor(.miyaTextSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.miyaBackground, lineWidth: 1)
                            )
                    }
                    .disabled(dataManager.isLoading)
                    
                    Button {
                        Task {
                            await saveMedicalHistory()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if dataManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(dataManager.isLoading ? "Saving..." : "Continue")
                            .font(.system(size: 16, weight: .semibold))
                        }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        .background(!dataManager.isLoading ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(dataManager.isLoading)
                }
                .padding(.bottom, 16)
                
                // Hidden NavigationLink - goes to Breakout 2 (self-onboarding) or next step based on user type
                NavigationLink(
                    destination: Group {
                        if showBreakouts {
                            Breakout2View()
                                .environmentObject(onboardingManager)
                                .environmentObject(dataManager)
                        } else if isGuidedInviteeAwaitingAdmin {
                            OnboardingCompleteView(membersCount: 0)
                                .environmentObject(onboardingManager)
                                .environmentObject(dataManager)
                        } else if onboardingManager.isInvitedUser {
                            AlertsChampionView()
                                .environmentObject(onboardingManager)
                                .environmentObject(dataManager)
                        } else {
                            FamilyMembersInviteView()
                                .environmentObject(onboardingManager)
                                .environmentObject(dataManager)
                        }
                    },
                    isActive: $navigateToNextStep
                ) {
                    EmptyView()
                }
                .hidden()
            }
            .padding(.horizontal, 24)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Step 5: Family History / Medical History
            onboardingManager.setCurrentStep(5)
        }
    }
    
    private func saveMedicalHistory() async {
        showError = false
        errorMessage = ""
        
        // Save to OnboardingManager
        onboardingManager.familyHeartDiseaseEarly = familyHeartDiseaseEarly
        onboardingManager.familyStrokeEarly = familyStrokeEarly
        onboardingManager.familyType2Diabetes = familyType2Diabetes
        
        do {
            // Save EXACT family history types for accurate WHO risk scoring
            var conditions: [String: Bool] = [:]
            
            if familyHeartDiseaseEarly {
                conditions["family_history_heart_early"] = true
            }
            
            if familyStrokeEarly {
                conditions["family_history_stroke_early"] = true
            }
            
            if familyType2Diabetes {
                conditions["family_history_type2_diabetes"] = true
            }
            
            if isUnsure {
                conditions["medical_history_unsure"] = true
            }
            
            // Save to health_conditions table (creates one record per condition)
            try await dataManager.saveHealthConditions(
                conditions: conditions,
                sourceStep: "medical_history"
            )
            
            // Calculate risk (stored in memory)
            let riskResult = RiskCalculator.calculateRisk(
                dateOfBirth: onboardingManager.dateOfBirth,
                smokingStatus: onboardingManager.smokingStatus,
                bloodPressureStatus: onboardingManager.bloodPressureStatus,
                diabetesStatus: onboardingManager.diabetesStatus,
                hasPriorHeartAttack: onboardingManager.hasPriorHeartAttack,
                hasPriorStroke: onboardingManager.hasPriorStroke,
                familyHeartDiseaseEarly: familyHeartDiseaseEarly,
                familyStrokeEarly: familyStrokeEarly,
                familyType2Diabetes: familyType2Diabetes,
                heightCm: onboardingManager.heightCm,
                weightKg: onboardingManager.weightKg
            )
            
            // Store in OnboardingManager
            onboardingManager.riskBand = riskResult.band.rawValue
            onboardingManager.riskPoints = riskResult.points
            onboardingManager.optimalVitalityTarget = riskResult.optimalTarget
            
            print("📊 Risk calculated: \(riskResult.band.rawValue) (\(riskResult.points) points), Target: \(riskResult.optimalTarget)")
            
            // Navigate to next step
            navigateToNextStep = true
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
// Reusable selectable row for conditions
struct SelectableConditionRow: View {
    let title: String
    @Binding var isSelected: Bool
    var isDisabled: Bool = false
    
    var body: some View {
        Button {
            if !isDisabled {
            isSelected.toggle()
            }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(isDisabled ? .miyaTextSecondary.opacity(0.5) : .miyaTextPrimary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isDisabled ? .miyaTextSecondary.opacity(0.3) : (isSelected ? .miyaPrimary : .miyaTextSecondary.opacity(0.4)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: (isSelected && !isDisabled) ? Color.black.opacity(0.05) : .clear,
                            radius: 8, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isDisabled ? Color.miyaBackground.opacity(0.5) : (isSelected ? Color.miyaPrimary : Color.miyaBackground.opacity(0.9)),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

#Preview("Step: Medical history") {
    NavigationStack {
        MedicalHistoryView()
            .environmentObject(DataManager())
            .environmentObject(OnboardingManager())
    }
}

// MARK: - STEP 8: PRIVACY & ALERTS PREVIEW

struct AlertsChampionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    private let totalSteps: Int = 7
    private let currentStep: Int = 7  // Final step
    
    @State private var navigateToNextStep: Bool = false
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Progress
                OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 16)
                
                // Title + subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy & Alerts")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("You'll have full control over your health data once your family joins.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Control What They See
                        PrivacyFeatureCard(
                            icon: "eye.circle.fill",
                            iconColor: .blue,
                            title: "Control What They See",
                            description: "Choose which family members can view your vitality scores, sleep patterns, stress levels, and medical data."
                        )
                        
                        // Choose Your Champion
                        PrivacyFeatureCard(
                            icon: "heart.circle.fill",
                            iconColor: .red,
                            title: "Choose Your Champion",
                            description: "Select one trusted family member who always sees your data and receives critical alerts on your behalf."
                        )
                        
                        // Smart Alert Timing
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.orange)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Smart Alert Timing")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.miyaTextPrimary)
                                    
                                    Text("Decide who gets notified and when")
                                        .font(.system(size: 14))
                                        .foregroundColor(.miyaTextSecondary)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                AlertTimingRow(
                                    day: "7",
                                    severity: "Gentle",
                                    description: "Private reminder just for you",
                                    color: .green
                                )
                                
                                AlertTimingRow(
                                    day: "14",
                                    severity: "Moderate",
                                    description: "Choose who to notify from your family",
                                    color: .orange
                                )
                                
                                AlertTimingRow(
                                    day: "21",
                                    severity: "Critical",
                                    description: "Alert you and your champion",
                                    color: .red
                                )
                            }
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(12)
                        }
                        .padding(16)
                        .background(Color.miyaPrimary.opacity(0.05))
                        .cornerRadius(16)
                        
                        // Per-Metric Privacy
                        PrivacyFeatureCard(
                            icon: "slider.horizontal.3",
                            iconColor: .purple,
                            title: "Customize Per Metric",
                            description: "Set different privacy rules for sleep, movement, stress, and medical data. For example: hide stress from parents but share with your partner."
                        )
                        
                        // Info Banner
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.miyaPrimary)
                                Text("Configure Later")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)
                            }
                            
                            Text("You can set up these preferences from your dashboard once family members accept your invites.")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        .padding(12)
                        .background(Color.miyaPrimary.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.vertical, 4)
                }
                .background(Color.miyaBackground)
                
                Spacer()
                
                // Buttons
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.clear)
                            .foregroundColor(.miyaTextSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.miyaBackground, lineWidth: 1)
                            )
                    }
                    
                    Button {
                        navigateToNextStep = true
                    } label: {
                        Text("Finish Setup")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                }
                .padding(.bottom, 16)
                
                // Hidden NavigationLink - goes to Onboarding Complete
                NavigationLink(
                    destination: OnboardingCompleteView(membersCount: onboardingManager.invitedMembers.count)
                        .environmentObject(onboardingManager)
                        .environmentObject(dataManager),
                    isActive: $navigateToNextStep
                ) {
                    EmptyView()
                }
                .hidden()
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            // Step 7: Privacy & Alerts Preview (Final Step)
            onboardingManager.setCurrentStep(7)
        }
    }
}

// Helper Views for AlertsChampionView

struct AlertExplanationRow: View {
    let days: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text("Day \(days)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.miyaPrimary)
                .frame(width: 50, alignment: .leading)
            
            Text(description)
                .font(.system(size: 13))
                .foregroundColor(.miyaTextSecondary)
        }
    }
}

struct NotificationToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.miyaTextPrimary)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.miyaPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// Helper Views for Privacy & Alerts Preview

struct PrivacyFeatureCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(iconColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
    }
}

struct AlertTimingRow: View {
    let day: String
    let severity: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("Day")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.miyaTextSecondary)
                Text(day)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)
            }
            .frame(width: 40)
            
            Rectangle()
                .fill(color.opacity(0.3))
                .frame(width: 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(severity)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.miyaTextSecondary)
            }
        }
    }
}

#Preview("Step: Privacy & alerts") {
    NavigationStack {
        AlertsChampionView()
            .environmentObject(DataManager())
            .environmentObject(OnboardingManager())
    }
}

// MARK: - LEGACY: WELLBEING PRIVACY SHARING

enum Tier1SharingOption: String {
    case meOnly
    case family
    case custom
}

enum Tier2SharingOption: String {
    case meOnly
    case custom
}

struct WellbeingPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    // Progress shows step 6 of 7 here.
    private let totalSteps: Int = 7
    private let currentStep: Int = 6
    
    @State private var tier1Option: Tier1SharingOption = .family
    @State private var tier2Option: Tier2SharingOption = .meOnly
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var navigateToNextStep: Bool = false
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Progress
                OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 16)
                
                // Title + subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text("You’re in control")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Your family sees summaries, never raw numbers. Choose what to share.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Everyday Wellbeing (Tier 1)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Everyday wellbeing (Tier 1)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("Sleep, stress, movement, energy, mood")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                            
                            HStack(spacing: 8) {
                                PrivacyOptionPill(
                                    label: "Visible to me only",
                                    isSelected: tier1Option == .meOnly
                                ) {
                                    tier1Option = .meOnly
                                }
                                
                                PrivacyOptionPill(
                                    label: "Visible to my family",
                                    isSelected: tier1Option == .family
                                ) {
                                    tier1Option = .family
                                }
                                
                                PrivacyOptionPill(
                                    label: "Custom",
                                    isSelected: tier1Option == .custom
                                ) {
                                    tier1Option = .custom
                                }
                            }
                            .padding(.top, 4)
                        }
                        
                        // Advanced Health (Tier 2)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Advanced health (Tier 2)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("Heart rate, BP, HRV, glucose, metabolic & cardio risk")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                            
                            HStack(spacing: 8) {
                                PrivacyOptionPill(
                                    label: "Visible to me only",
                                    isSelected: tier2Option == .meOnly
                                ) {
                                    tier2Option = .meOnly
                                }
                                
                                PrivacyOptionPill(
                                    label: "Custom",
                                    isSelected: tier2Option == .custom
                                ) {
                                    tier2Option = .custom
                                }
                            }
                            .padding(.top, 4)
                        }
                        
                        // Trusted backup contact
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Trusted backup contact (optional)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("Receives alerts only in emergencies.")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                            
                            Button {
                                // Later: open contact picker or simple form
                                print("Add backup contact tapped")
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("Add contact")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .background(Color.white)
                                .foregroundColor(.miyaPrimary)
                                .cornerRadius(999)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 999)
                                        .stroke(Color.miyaPrimary, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(Color.miyaBackground)
                
                // Error message
                if showError {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Buttons
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.clear)
                            .foregroundColor(.miyaTextSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.miyaBackground, lineWidth: 1)
                            )
                    }
                    .disabled(dataManager.isLoading)
                    
                    Button {
                        Task {
                            await savePrivacySettings()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if dataManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(dataManager.isLoading ? "Saving..." : "Continue")
                            .font(.system(size: 16, weight: .semibold))
                        }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        .background(!dataManager.isLoading ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(dataManager.isLoading)
                }
                .padding(.bottom, 16)
                
                // Hidden NavigationLink for programmatic navigation
                NavigationLink(
                    destination: FamilyMembersInviteView(),
                    isActive: $navigateToNextStep
                ) {
                    EmptyView()
                }
                .hidden()
            }
            .padding(.horizontal, 24)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Step 6: Wellbeing Privacy
            onboardingManager.setCurrentStep(6)
        }
    }
    
    private func savePrivacySettings() async {
        showError = false
        errorMessage = ""
        
        do {
            // Save to OnboardingManager
            onboardingManager.tier1Sharing = tier1Option.rawValue
            onboardingManager.tier2Sharing = tier2Option.rawValue
            
            // Save to database
            try await dataManager.savePrivacySettings(
                tier1Visibility: tier1Option.rawValue,
                tier2Visibility: tier2Option.rawValue
            )
            
            // Navigate to next step
            navigateToNextStep = true
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// Small pill-style button used for privacy options
struct PrivacyOptionPill: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(isSelected ? Color.miyaPrimary : Color.white)
                .foregroundColor(isSelected ? .white : .miyaTextPrimary)
                .cornerRadius(999)
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(
                            isSelected ? Color.miyaPrimary : Color.miyaBackground.opacity(0.9),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
// MARK: - INVITE FAMILY MEMBERS (ONE BY ONE)

enum MemberRelationship: String, CaseIterable, Identifiable {
    case partner = "Partner"
    case parent = "Parent"
    case child = "Child"
    case sibling = "Sibling"
    case grandparent = "Grandparent"
    case other = "Other"
    
    var id: String { rawValue }
}

enum MemberOnboardingType: String, Identifiable {
    case guided = "Guided Setup"
    case selfSetup = "Self Setup"
    
    var id: String { rawValue }
}

struct InvitedMember: Identifiable {
    let id = UUID()
    let firstName: String
    let relationship: MemberRelationship
    let onboardingType: MemberOnboardingType
    let inviteCode: String
}

struct FamilyMembersInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager

    /// When true, this view is presented from the Dashboard/Sidebar (not during onboarding).
    /// In that context we must NOT mutate onboarding step/routing, and we should dismiss back to Dashboard after showing a code.
    let isPresentedFromDashboard: Bool
    
    init(isPresentedFromDashboard: Bool = false) {
        self.isPresentedFromDashboard = isPresentedFromDashboard
    }
    
    // Current in-progress member
    @State private var firstName: String = ""
    @State private var selectedRelationship: MemberRelationship? = nil
    @State private var selectedOnboardingType: MemberOnboardingType? = nil
    
    // List of invited members
    @State private var invitedMembers: [InvitedMember] = []
    
    // Invite popup
    @State private var showInviteSheet: Bool = false
    @State private var currentInviteCode: String = ""
    @State private var currentInviteName: String = ""
    
    // Guided Setup options sheet
    @State private var showGuidedOptionsSheet: Bool = false
    @State private var currentMemberId: String = ""  // For "Fill out now" flow
    @State private var navigateToGuidedDataEntry: Bool = false
    @State private var pendingGuidedMember: InvitedMember? = nil  // Member awaiting guided data entry
    
    // Navigation to completion
    @State private var navigateToComplete: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    private var memberIndex: Int {
        invitedMembers.count + 1
    }
    
    private var canGenerateInvite: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedRelationship != nil &&
        selectedOnboardingType != nil
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Build your health team")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    // You can later replace this with the real family name from Step 2
                    Text("Create profiles for your family.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
                
                // Already invited members (if any)
                if !invitedMembers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Members added")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        ForEach(invitedMembers) { member in
                            HStack {
                                Text(member.firstName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.miyaTextPrimary)
                                
                                Text("• \(member.relationship.rawValue)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.miyaTextSecondary)
                                
                                Text("• \(member.onboardingType == .guided ? "Guided" : "Self")")
                                    .font(.system(size: 13))
                                    .foregroundColor(.miyaTextSecondary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                            )
                        }
                        
                        // New: Add another member button right under the list
                        Button {
                            resetCurrentMemberForm()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add another member")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.white)
                            .foregroundColor(.miyaPrimary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.miyaPrimary.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                
                // Error message (if any)
                if showError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Current member form
                VStack(alignment: .leading, spacing: 16) {
                    Text("Member \(memberIndex)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        TextField("First name", text: $firstName)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                            )
                    }
                    
                    // Relationship
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Relationship")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Menu {
                            ForEach(MemberRelationship.allCases) { relation in
                                Button(relation.rawValue) {
                                    selectedRelationship = relation
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedRelationship?.rawValue ?? "Select relationship")
                                    .foregroundColor(
                                        selectedRelationship == nil ? .miyaTextSecondary : .miyaTextPrimary
                                    )
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.miyaTextSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                            )
                        }
                    }
                    
                    // Onboarding type
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Onboarding type")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        VStack(spacing: 10) {
                            OnboardingTypeCard(
                                title: "Guided setup",
                                subtitle: "You guide them",
                                type: .guided,
                                isEnabled: true,
                                selectedType: $selectedOnboardingType
                            )
                            
                            OnboardingTypeCard(
                                title: "Self setup",
                                subtitle: "They set up alone",
                                type: .selfSetup,
                                isEnabled: true,
                                selectedType: $selectedOnboardingType
                            )
                        }
                    }
                    
                    // Generate invite code
                    Button {
                        // Simplified: always "fill out later" (hide fill-out-now UX for now)
                        generateInviteCode(fillOutNow: false)
                    } label: {
                        HStack(spacing: 8) {
                            if dataManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(dataManager.isLoading ? "Generating..." : "Generate invite code")
                            .font(.system(size: 15, weight: .semibold))
                        }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        .background(canGenerateInvite && !dataManager.isLoading ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(!canGenerateInvite || dataManager.isLoading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                )
                
                Spacer()
                
                // Bottom actions: Back + Finish onboarding
                if isPresentedFromDashboard {
                    // Dashboard context: do not advance onboarding flow. Just close.
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .padding(.bottom, 16)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Back")
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.clear)
                                .foregroundColor(.miyaTextSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.miyaBackground, lineWidth: 1)
                                )
                        }
                        
                        Button {
                            // Navigate to the onboarding completion summary
                            navigateToComplete = true
                        } label: {
                            Text(invitedMembers.isEmpty ? "Skip for now" : "Finish")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.miyaPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                        }
                    }
                    .padding(.bottom, 16)
                    
                    // Hidden NavigationLink - goes to Alerts & Champion setup
                    NavigationLink(
                        destination: AlertsChampionView(),
                        isActive: $navigateToComplete
                    ) {
                        EmptyView()
                    }
                    .hidden()
                }
            }
            .padding(.horizontal, 24)
        }
        // Invite popup
        .sheet(isPresented: $showInviteSheet) {
            InviteCodeSheet(
                name: currentInviteName,
                code: currentInviteCode
            ) {
                // Done tapped
                if isPresentedFromDashboard {
                    // Dashboard context: return to Dashboard immediately after showing code.
                    dismiss()
                } else {
                    // Onboarding context: clear form for the next member.
                    resetCurrentMemberForm()
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            if !isPresentedFromDashboard {
                onboardingManager.setCurrentStep(6)
            }
            Task {
                await loadExistingInvites()
            }
        }
        // (Fill-out-now hidden for now; keep code for future re-enable)
    }
    
    private func generateInviteCode(fillOutNow: Bool) {
        Task {
            await generateInviteCodeAsync(fillOutNow: fillOutNow)
        }
    }
    
    private func generateInviteCodeAsync(fillOutNow: Bool) async {
        guard let relationship = selectedRelationship,
              let onboardingType = selectedOnboardingType
        else { return }
        
        showError = false
        errorMessage = ""
        
        do {
            // Determine the initial guided setup status
            let guidedStatus: GuidedSetupStatus? = onboardingType == .guided ? .pendingAcceptance : nil
            
            // Save to database and get invite code + member ID
            let (inviteCode, memberId) = try await dataManager.saveFamilyMemberInviteWithId(
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                relationship: relationship.rawValue,
                onboardingType: onboardingType.rawValue,
                guidedSetupStatus: guidedStatus
            )
            
            // Save to list
            let member = InvitedMember(
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                relationship: relationship,
                onboardingType: onboardingType,
                inviteCode: inviteCode
            )
            invitedMembers.append(member)
            
            // Save to OnboardingManager
            if !isPresentedFromDashboard {
                onboardingManager.invitedMembers.append(InvitedFamilyMember(
                    firstName: member.firstName,
                    relationship: relationship.rawValue,
                    onboardingType: onboardingType.rawValue,
                    inviteCode: inviteCode
                ))
            }
            
            if fillOutNow && onboardingType == .guided {
                // Navigate to guided data entry flow
                currentMemberId = memberId
                pendingGuidedMember = member
                navigateToGuidedDataEntry = true
            } else {
                // Show invite code popup
                currentInviteName = member.firstName
                currentInviteCode = member.inviteCode
                showInviteSheet = true
            }
            
            // Reset form for next member
            resetCurrentMemberForm()
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func loadExistingInvites() async {
        guard let familyId = dataManager.currentFamilyId else {
            print("⚠️ FamilyMembersInviteView: currentFamilyId is nil, cannot load existing invites")
            return
        }
        
        print("📥 FamilyMembersInviteView: Loading existing invites for family \(familyId)")
        
        do {
            let records = try await dataManager.fetchPendingFamilyInvites(familyId: familyId)
            print("✅ FamilyMembersInviteView: Fetched \(records.count) pending invites")
            
            let mapped: [InvitedMember] = records.compactMap { rec in
                guard let relStr = rec.relationship,
                      let rel = MemberRelationship(rawValue: relStr),
                      let onboardingStr = rec.onboardingType,
                      let onboarding = MemberOnboardingType(rawValue: onboardingStr),
                      let code = rec.inviteCode else {
                    print("⚠️ FamilyMembersInviteView: Skipping record \(rec.id) - missing data")
                    return nil
                }
                return InvitedMember(
                    firstName: rec.firstName,
                    relationship: rel,
                    onboardingType: onboarding,
                    inviteCode: code
                )
            }
            
            await MainActor.run {
                invitedMembers = mapped
                print("✅ FamilyMembersInviteView: Displaying \(invitedMembers.count) invited members")
            }
        } catch {
            print("❌ FamilyMembersInviteView: Failed to load existing invites: \(error.localizedDescription)")
        }
    }
    
    private func resetCurrentMemberForm() {
        firstName = ""
        selectedRelationship = nil
        selectedOnboardingType = nil
    }
    
}

// Card for Guided/Self setup selection
struct OnboardingTypeCard: View {
    let title: String
    let subtitle: String
    let type: MemberOnboardingType
    let isEnabled: Bool
    
    @Binding var selectedType: MemberOnboardingType?
    
    private var isSelected: Bool {
        selectedType == type
    }
    
    var body: some View {
        Button {
            guard isEnabled else { return }
            selectedType = type
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isEnabled ? .miyaTextPrimary : .miyaTextSecondary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextSecondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .miyaPrimary : .miyaTextSecondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: isSelected ? Color.black.opacity(0.05) : .clear,
                            radius: 8, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.miyaPrimary : Color.miyaBackground.opacity(0.9),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .opacity(isEnabled ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// Popup sheet showing the generated invite code
struct InviteCodeSheet: View {
    @Environment(\.dismiss) private var dismiss   // <-- Add dismiss environment
    let name: String
    let code: String
    let onDone: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Invitation for \(name)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.miyaTextPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                
                Text("Share this code to invite \(name.lowercased()) to join your family.")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                // Code block
                VStack(spacing: 8) {
                    Text(code)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.miyaPrimary)
                    
                    Text("Enter this code in the Miya app to join your family.")
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                )
                
                VStack(spacing: 12) {
                    Text("Share via:")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Button {
                        print("Share via email tapped")
                    } label: {
                        HStack {
                            Image(systemName: "envelope")
                            Text("Email link")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.miyaPrimary.opacity(0.08))
                        .foregroundColor(.miyaPrimary)
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                Button {
                    onDone()     // reset form in parent
                    dismiss()    // dismiss the sheet
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.miyaPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
        }
    }
}

#Preview("Step: Invite family members") {
    NavigationStack {
        FamilyMembersInviteView(isPresentedFromDashboard: false)
            .environmentObject(DataManager())
            .environmentObject(OnboardingManager())
    }
}

// MARK: - GUIDED SETUP OPTIONS SHEET

/// Sheet shown when admin selects Guided Setup - "Fill out now" or "Fill out later"
struct GuidedSetupOptionsSheet: View {
    let memberName: String
    let onFillOutNow: () -> Void
    let onFillOutLater: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 40))
                    .foregroundColor(.miyaPrimary)
                
                Text("Guided Setup for \(memberName)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.miyaTextPrimary)
                
                Text("You've chosen to guide \(memberName)'s setup. When would you like to fill out their health information?")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 24)
            
            // Options
            VStack(spacing: 12) {
                // Fill out now
                Button(action: onFillOutNow) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fill out now")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Complete their profile right away")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.miyaPrimary)
                    .cornerRadius(16)
                }
                
                // Fill out later
                Button(action: onFillOutLater) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fill out later")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            Text("\(memberName) will accept, then you fill in their data")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        Spacer()
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 24))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.miyaBackground, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
}

// MARK: - PENDING GUIDED SETUPS VIEW

/// Admin dashboard view showing family members waiting for guided data entry
struct PendingGuidedSetupsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var pendingMembers: [FamilyMemberRecord] = []
    @State private var isLoading: Bool = true
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var selectedMember: FamilyMemberRecord? = nil
    @State private var navigateToDataEntry: Bool = false
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                    }
                    
                    Spacer()
                    
                    Text("Pending Guided Setups")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Spacer()
                    
                    // Placeholder for symmetry
                    Color.clear.frame(width: 24, height: 24)
                }
                .padding(.top, 16)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                    Text("Loading...")
                        .font(.system(size: 14))
                        .foregroundColor(.miyaTextSecondary)
                    Spacer()
                } else if pendingMembers.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("All caught up!")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        Text("No family members waiting for guided setup")
                            .font(.system(size: 14))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(pendingMembers, id: \.id) { member in
                                pendingMemberRow(member)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .navigationBarHidden(true)
        .onAppear {
            Task {
                await loadPendingSetups()
            }
        }
        .navigationDestination(isPresented: $navigateToDataEntry) {
            if let member = selectedMember {
                GuidedHealthDataEntryFlow(
                    memberId: member.id.uuidString,
                    memberName: member.firstName,
                    inviteCode: member.inviteCode ?? ""
                ) {
                    // Refresh list after completion
                    Task {
                        await loadPendingSetups()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func pendingMemberRow(_ member: FamilyMemberRecord) -> some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.miyaPrimary.opacity(0.1))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(member.firstName.prefix(1)).uppercased())
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.miyaPrimary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(member.firstName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                Text(member.relationship ?? "Family member")
                    .font(.system(size: 13))
                    .foregroundColor(.miyaTextSecondary)
                
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10))
                    Text("Waiting for your input")
                        .font(.system(size: 12))
                }
                .foregroundColor(.orange)
            }
            
            Spacer()
            
            Button {
                selectedMember = member
                navigateToDataEntry = true
            } label: {
                Text("Fill Out")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.miyaPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
    }
    
    private func loadPendingSetups() async {
        isLoading = true
        
        guard let familyId = dataManager.currentFamilyId else {
            isLoading = false
            return
        }
        
        do {
            pendingMembers = try await dataManager.getPendingGuidedSetups(familyId: familyId)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - GUIDED SETUP ACCEPTANCE PROMPT

/// Shown to invited user when they enter a Guided Setup invite code without pre-filled data
struct GuidedSetupAcceptancePrompt: View {
    let memberName: String
    let adminName: String
    let onAcceptGuidedSetup: () -> Void
    let onFillMyself: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.miyaPrimary)
                
                Text("Welcome, \(memberName)!")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.miyaTextPrimary)
                
                Text("Your family member has chosen Guided Setup for you. This means they'll fill out your health information on your behalf.")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 24)
            
            // Options
            VStack(spacing: 12) {
                // Accept Guided Setup
                Button(action: onAcceptGuidedSetup) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Accept Guided Setup")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Let them fill out your health info")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.miyaPrimary)
                    .cornerRadius(16)
                }
                
                // Fill out myself
                Button(action: onFillMyself) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("I'll fill it out myself")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            Text("Complete your own health profile")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        Spacer()
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.miyaBackground, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 24)
            
            // Info note
            Text("You can always edit your information later from settings.")
                .font(.system(size: 13))
                .foregroundColor(.miyaTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Spacer()
        }
    }
}

// MARK: - GUIDED WAITING VIEW

/// Shown to invited user after accepting guided setup; tells them admin will fill data
struct GuidedWaitingForAdminView: View {
    @Environment(\.dismiss) private var dismiss
    let adminName: String
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundColor(.miyaPrimary)
                    
                    Text("Waiting for \(adminName)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    
                    Text("Your family admin will complete your health information. We'll let you know when it's ready to review.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 32)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Text("Got it")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.miyaPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

#Preview("Step: Guided setup review") {
    NavigationStack {
        GuidedSetupReviewView(memberId: UUID().uuidString)
            .environmentObject(DataManager())
            .environmentObject(OnboardingManager())
    }
}

// MARK: - GUIDED SETUP REVIEW VIEW

/// Shown to invited user when admin has pre-filled their health data - allows review and editing
struct GuidedSetupReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    let memberId: String
    
    @State private var guidedData: GuidedHealthData? = nil
    @State private var firstName: String = ""
    @State private var familyName: String = ""
    @State private var isLoading: Bool = true
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var navigateToEdit: Bool = false
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading your health information...")
                        .font(.system(size: 14))
                        .foregroundColor(.miyaTextSecondary)
                        .padding(.top, 8)
                }
            } else if let data = guidedData {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Review Your Health Information")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("Your family member has filled out this information for you. Please review and confirm or make changes.")
                                .font(.system(size: 15))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        .padding(.top, 16)
                        
                        // About You Section
                        reviewSection(title: "About You", icon: "person.fill") {
                            reviewRow("Gender", value: data.aboutYou.gender)
                            reviewRow("Date of Birth", value: data.aboutYou.dateOfBirth)
                            reviewRow("Height", value: "\(Int(data.aboutYou.heightCm)) cm")
                            reviewRow("Weight", value: "\(Int(data.aboutYou.weightKg)) kg")
                            reviewRow("Ethnicity", value: data.aboutYou.ethnicity)
                            reviewRow("Smoking", value: data.aboutYou.smokingStatus)
                        }
                        
                        // Heart Health Section
                        reviewSection(title: "Heart Health", icon: "heart.fill") {
                            reviewRow("Blood Pressure", value: formatBPStatus(data.heartHealth.bloodPressureStatus))
                            reviewRow("Diabetes", value: formatDiabetesStatus(data.heartHealth.diabetesStatus))
                            if data.heartHealth.hasPriorHeartAttack {
                                reviewRow("Prior Events", value: "Heart attack")
                            }
                            if data.heartHealth.hasPriorStroke {
                                reviewRow("Prior Events", value: "Stroke")
                            }
                            if data.heartHealth.hasChronicKidneyDisease {
                                reviewRow("Conditions", value: "Chronic kidney disease")
                            }
                            if data.heartHealth.hasAtrialFibrillation {
                                reviewRow("Conditions", value: "Atrial fibrillation")
                            }
                            if data.heartHealth.hasHighCholesterol {
                                reviewRow("Conditions", value: "High cholesterol")
                            }
                        }
                        
                        // Medical History Section
                        reviewSection(title: "Family History", icon: "person.3.fill") {
                            if data.medicalHistory.familyHeartDiseaseEarly {
                                reviewRow("Family", value: "Heart disease before 60")
                            }
                            if data.medicalHistory.familyStrokeEarly {
                                reviewRow("Family", value: "Stroke before 60")
                            }
                            if data.medicalHistory.familyType2Diabetes {
                                reviewRow("Family", value: "Type 2 diabetes")
                            }
                            if !data.medicalHistory.familyHeartDiseaseEarly &&
                               !data.medicalHistory.familyStrokeEarly &&
                               !data.medicalHistory.familyType2Diabetes {
                                reviewRow("Family", value: "No significant history noted")
                            }
                        }
                        
                        // Action buttons
                        VStack(spacing: 12) {
                            Button {
                                Task {
                                    await confirmData()
                                }
                            } label: {
                                Text("Confirm & Continue")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.miyaPrimary)
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                            }
                            
                            Button {
                                navigateToEdit = true
                            } label: {
                                Text("Make Changes")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.white)
                                    .foregroundColor(.miyaPrimary)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.miyaPrimary, lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 24)
                }
                .background(Color.miyaBackground)
            } else {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("Could not load your health information")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            Task {
                await loadGuidedData()
            }
        }
        .navigationDestination(isPresented: $navigateToEdit) {
            // BUG 5 FIX: Edit guided data (prefilled from admin-provided data)
            if let data = guidedData {
                GuidedHealthDataEditView(
                    memberId: memberId,
                    initialData: data,
                    onSave: {
                        Task {
                            await loadGuidedData()
                            navigateToEdit = false
                        }
                    }
                )
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func reviewSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.miyaPrimary)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(16)
        }
    }
    
    private func reviewRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.miyaTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.miyaTextPrimary)
        }
    }
    
    private func formatBPStatus(_ status: String) -> String {
        switch status {
        case "normal": return "Normal"
        case "elevated_untreated": return "High, not on medication"
        case "elevated_treated": return "High, on medication"
        case "unknown": return "Not sure"
        default: return status
        }
    }
    
    private func formatDiabetesStatus(_ status: String) -> String {
        switch status {
        case "none": return "No diabetes"
        case "pre_diabetic": return "Pre-diabetes"
        case "type_1": return "Type 1"
        case "type_2": return "Type 2"
        case "unknown": return "Not sure"
        default: return status
        }
    }
    
    private func loadGuidedData() async {
        isLoading = true
        
        do {
            // Load the guided health data
            guidedData = try await dataManager.loadGuidedHealthData(memberId: memberId)
            
            // Load member info for display by memberId (not current user)
            if let memberRec = try await dataManager.fetchFamilyMemberRecord(memberId: memberId) {
                firstName = memberRec.firstName
                
                // Fetch family name if family_id is present
                if let familyId = memberRec.familyId {
                    familyName = try await dataManager.fetchFamilyName(familyId: familyId) ?? ""
                }
            }
            
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func confirmData() async {
        do {
            // Confirm review:
            // - Upserts user_profiles from guided data (DataManager)
            // - Transitions guided_setup_status -> reviewed_complete
            try await dataManager.confirmGuidedDataReview(memberId: memberId)
            onboardingManager.guidedSetupStatus = .reviewedComplete
            
            // Keep in-memory onboarding state in sync so downstream screens (BMI/risk UI) don't show 0.0 defaults.
            if let data = guidedData {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                if let dob = dateFormatter.date(from: data.aboutYou.dateOfBirth) {
                    onboardingManager.dateOfBirth = dob
                }
                onboardingManager.gender = data.aboutYou.gender
                onboardingManager.ethnicity = data.aboutYou.ethnicity
                onboardingManager.smokingStatus = data.aboutYou.smokingStatus
                onboardingManager.heightCm = data.aboutYou.heightCm
                onboardingManager.weightKg = data.aboutYou.weightKg
                
                onboardingManager.bloodPressureStatus = data.heartHealth.bloodPressureStatus
                onboardingManager.diabetesStatus = data.heartHealth.diabetesStatus
                onboardingManager.hasPriorHeartAttack = data.heartHealth.hasPriorHeartAttack
                onboardingManager.hasPriorStroke = data.heartHealth.hasPriorStroke
                
                onboardingManager.familyHeartDiseaseEarly = data.medicalHistory.familyHeartDiseaseEarly
                onboardingManager.familyStrokeEarly = data.medicalHistory.familyStrokeEarly
                onboardingManager.familyType2Diabetes = data.medicalHistory.familyType2Diabetes
                
                // Calculate risk assessment
                let riskResult = RiskCalculator.calculateRisk(
                    dateOfBirth: onboardingManager.dateOfBirth,
                    smokingStatus: onboardingManager.smokingStatus,
                    bloodPressureStatus: onboardingManager.bloodPressureStatus,
                    diabetesStatus: onboardingManager.diabetesStatus,
                    hasPriorHeartAttack: onboardingManager.hasPriorHeartAttack,
                    hasPriorStroke: onboardingManager.hasPriorStroke,
                    familyHeartDiseaseEarly: onboardingManager.familyHeartDiseaseEarly,
                    familyStrokeEarly: onboardingManager.familyStrokeEarly,
                    familyType2Diabetes: onboardingManager.familyType2Diabetes,
                    heightCm: onboardingManager.heightCm,
                    weightKg: onboardingManager.weightKg
                )
                
                // Store in OnboardingManager
                onboardingManager.riskBand = riskResult.band.rawValue
                onboardingManager.riskPoints = riskResult.points
                onboardingManager.optimalVitalityTarget = riskResult.optimalTarget
                
                print("📊 Guided setup risk calculated: \(riskResult.band.rawValue) (\(riskResult.points) points), Target: \(riskResult.optimalTarget)")
                
                // Save risk assessment to database
                try await dataManager.saveRiskAssessment(
                    riskBand: riskResult.band.rawValue,
                    riskPoints: riskResult.points,
                    optimalTarget: riskResult.optimalTarget
                )
            }
            
            // Mark onboarding as complete (this will trigger LandingView to show dashboard)
            await MainActor.run {
                onboardingManager.completeOnboarding()
            }
            await onboardingManager.refreshGuidedContextFromDB(dataManager: dataManager)
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - GUIDED HEALTH DATA ENTRY FLOW

/// Multi-step form for admin to fill out health data for a guided setup member
struct GuidedHealthDataEntryFlow: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    let memberId: String
    let memberName: String
    let inviteCode: String
    let onComplete: () -> Void
    
    // Current step
    @State private var currentStep: Int = 1
    private let totalSteps: Int = 3
    
    // Step 1: About You data
    @State private var selectedGender: Gender? = nil
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var heightCm: String = ""
    @State private var weightKg: String = ""
    @State private var selectedEthnicity: Ethnicity? = nil
    @State private var smokingStatus: SmokingStatus? = nil
    
    // Step 2: Heart Health data
    @State private var bloodPressureStatus: String = "normal"
    @State private var diabetesStatus: String = "none"
    @State private var hasPriorHeartAttack: Bool = false
    @State private var hasPriorStroke: Bool = false
    @State private var noPriorEvents: Bool = false  // "None of the above" (must mirror HeartHealthView behavior)
    @State private var hasChronicKidneyDisease: Bool = false
    @State private var hasAtrialFibrillation: Bool = false
    @State private var hasHighCholesterol: Bool = false
    @State private var noMedicalConditions: Bool = false  // "None of the above" (must mirror HeartHealthView behavior)
    
    // Step 3: Medical History data
    @State private var familyHeartDiseaseEarly: Bool = false
    @State private var familyStrokeEarly: Bool = false
    @State private var familyType2Diabetes: Bool = false
    @State private var familyHistoryNotSure: Bool = false
    
    // State
    @State private var isLoading: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Progress header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(action: handleBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                        }
                        Spacer()
                        Text("Step \(currentStep) of \(totalSteps)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.miyaBackground.opacity(0.9))
                                .frame(height: 6)
                            Capsule()
                                .fill(Color.miyaPrimary)
                                .frame(width: geo.size.width * CGFloat(currentStep) / CGFloat(totalSteps), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.top, 16)
                
                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("Guided Setup for \(memberName)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    Text(stepSubtitle)
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Step content
                ScrollView {
                    switch currentStep {
                    case 1:
                        aboutYouStepContent
                    case 2:
                        heartHealthStepContent
                    case 3:
                        medicalHistoryStepContent
                    default:
                        EmptyView()
                    }
                }
                
                // Error message
                if showError {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Continue button
                Button(action: handleContinue) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(currentStep == totalSteps ? "Save" : "Continue")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canContinue ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                .disabled(!canContinue || isLoading)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
        .navigationBarHidden(true)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var stepSubtitle: String {
        switch currentStep {
        case 1: return "Basic information about \(memberName)"
        case 2: return "Heart health and conditions"
        case 3: return "Family medical history"
        default: return ""
        }
    }
    
    private var canContinue: Bool {
        switch currentStep {
        case 1:
            return selectedGender != nil &&
                   !heightCm.isEmpty &&
                   !weightKg.isEmpty &&
                   selectedEthnicity != nil &&
                   smokingStatus != nil
        case 2:
            return true  // All fields have defaults
        case 3:
            return true  // All fields have defaults
        default:
            return false
        }
    }
    
    // MARK: - Step 1: About You
    
    private var aboutYouStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Gender
            VStack(alignment: .leading, spacing: 8) {
                Text("Gender")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                HStack(spacing: 12) {
                    ForEach(Gender.allCases) { gender in
                        Button {
                            selectedGender = gender
                        } label: {
                            Text(gender.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(selectedGender == gender ? Color.miyaPrimary : Color.white)
                                .foregroundColor(selectedGender == gender ? .white : .miyaTextPrimary)
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(selectedGender == gender ? Color.miyaPrimary : Color.miyaBackground, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Date of Birth
            VStack(alignment: .leading, spacing: 8) {
                Text("Date of Birth")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                DatePicker("", selection: $dateOfBirth, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
            
            // Height
            VStack(alignment: .leading, spacing: 8) {
                Text("Height (cm)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                TextField("170", text: $heightCm)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(MiyaTextFieldStyle())
            }
            
            // Weight
            VStack(alignment: .leading, spacing: 8) {
                Text("Weight (kg)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                TextField("70", text: $weightKg)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(MiyaTextFieldStyle())
            }
            
            // Ethnicity
            VStack(alignment: .leading, spacing: 8) {
                Text("Ethnicity")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                Menu {
                    ForEach(Ethnicity.allCases) { ethnicity in
                        Button(ethnicity.rawValue) {
                            selectedEthnicity = ethnicity
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedEthnicity?.rawValue ?? "Select ethnicity")
                            .foregroundColor(selectedEthnicity == nil ? .miyaTextSecondary : .miyaTextPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.miyaTextSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.miyaBackground, lineWidth: 1)
                    )
                }
            }
            
            // Smoking Status
            VStack(alignment: .leading, spacing: 8) {
                Text("Smoking Status")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                VStack(spacing: 8) {
                    ForEach(SmokingStatus.allCases) { status in
                        Button {
                            smokingStatus = status
                        } label: {
                            HStack {
                                Text(status.displayText)
                                    .font(.system(size: 14))
                                    .foregroundColor(.miyaTextPrimary)
                                Spacer()
                                Image(systemName: smokingStatus == status ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(smokingStatus == status ? .miyaPrimary : .miyaTextSecondary.opacity(0.4))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Step 2: Heart Health
    
    private var heartHealthStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Blood Pressure Status
            VStack(alignment: .leading, spacing: 8) {
                Text("Blood Pressure Status")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                VStack(spacing: 8) {
                    bpOptionRow("Normal", value: "normal")
                    bpOptionRow("High, not on medication", value: "elevated_untreated")
                    bpOptionRow("High, taking medication", value: "elevated_treated")
                    bpOptionRow("Never checked / Not sure", value: "unknown")
                }
            }
            
            // Diabetes Status
            VStack(alignment: .leading, spacing: 8) {
                Text("Diabetes Status")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                VStack(spacing: 8) {
                    diabetesOptionRow("No diabetes", value: "none")
                    diabetesOptionRow("Pre-diabetes", value: "pre_diabetic")
                    diabetesOptionRow("Type 1 diabetes", value: "type_1")
                    diabetesOptionRow("Type 2 diabetes", value: "type_2")
                    diabetesOptionRow("Not sure", value: "unknown")
                }
            }
            
            // Prior Events
            VStack(alignment: .leading, spacing: 8) {
                Text("Prior Cardiovascular Events")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                // Must match HeartHealthView behavior:
                // - Selecting an event clears "None of the above"
                // - Selecting "None of the above" clears events and disables itself while any event is selected
                VStack(spacing: 8) {
                    SelectableConditionRow(
                        title: "Heart attack",
                        isSelected: Binding(
                            get: { hasPriorHeartAttack },
                            set: { newValue in
                                hasPriorHeartAttack = newValue
                                if newValue { noPriorEvents = false }
                            }
                        )
                    )
                    
                    SelectableConditionRow(
                        title: "Stroke",
                        isSelected: Binding(
                            get: { hasPriorStroke },
                            set: { newValue in
                                hasPriorStroke = newValue
                                if newValue { noPriorEvents = false }
                            }
                        )
                    )
                    
                    SelectableConditionRow(
                        title: "None of the above",
                        isSelected: Binding(
                            get: { noPriorEvents },
                            set: { newValue in
                                noPriorEvents = newValue
                                if newValue {
                                    hasPriorHeartAttack = false
                                    hasPriorStroke = false
                                }
                            }
                        ),
                        isDisabled: hasPriorHeartAttack || hasPriorStroke
                    )
                }
            }
            
            // Other Conditions
            VStack(alignment: .leading, spacing: 8) {
                Text("Other Conditions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                // Must match HeartHealthView behavior:
                // - Selecting a condition clears "None of the above"
                // - Selecting "None of the above" clears conditions and disables itself while any condition is selected
                VStack(spacing: 8) {
                    SelectableConditionRow(
                        title: "Chronic kidney disease",
                        isSelected: Binding(
                            get: { hasChronicKidneyDisease },
                            set: { newValue in
                                hasChronicKidneyDisease = newValue
                                if newValue { noMedicalConditions = false }
                            }
                        )
                    )
                    
                    SelectableConditionRow(
                        title: "Atrial fibrillation (irregular heartbeat)",
                        isSelected: Binding(
                            get: { hasAtrialFibrillation },
                            set: { newValue in
                                hasAtrialFibrillation = newValue
                                if newValue { noMedicalConditions = false }
                            }
                        )
                    )
                    
                    SelectableConditionRow(
                        title: "High cholesterol (diagnosed by doctor)",
                        isSelected: Binding(
                            get: { hasHighCholesterol },
                            set: { newValue in
                                hasHighCholesterol = newValue
                                if newValue { noMedicalConditions = false }
                            }
                        )
                    )
                    
                    SelectableConditionRow(
                        title: "None of the above",
                        isSelected: Binding(
                            get: { noMedicalConditions },
                            set: { newValue in
                                noMedicalConditions = newValue
                                if newValue {
                                    hasChronicKidneyDisease = false
                                    hasAtrialFibrillation = false
                                    hasHighCholesterol = false
                                }
                            }
                        ),
                        isDisabled: hasChronicKidneyDisease || hasAtrialFibrillation || hasHighCholesterol
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Step 3: Medical History
    
    private var medicalHistoryStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Family Health History")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                Text("Do any parents or siblings have a history of the following?")
                    .font(.system(size: 13))
                    .foregroundColor(.miyaTextSecondary)
                
                VStack(spacing: 8) {
                    familyHistoryToggle("Heart disease (heart attack, bypass surgery) before age 60", isOn: $familyHeartDiseaseEarly)
                    familyHistoryToggle("Stroke before age 60", isOn: $familyStrokeEarly)
                    familyHistoryToggle("Type 2 diabetes (at any age)", isOn: $familyType2Diabetes)
                    
                    Divider()
                    
                    familyHistoryToggle("Not sure / None of these", isOn: $familyHistoryNotSure)
                        .onChange(of: familyHistoryNotSure) { newValue in
                            if newValue {
                                familyHeartDiseaseEarly = false
                                familyStrokeEarly = false
                                familyType2Diabetes = false
                            }
                        }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Helper Views
    
    private func bpOptionRow(_ label: String, value: String) -> some View {
        Button {
            bloodPressureStatus = value
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
                Image(systemName: bloodPressureStatus == value ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(bloodPressureStatus == value ? .miyaPrimary : .miyaTextSecondary.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func diabetesOptionRow(_ label: String, value: String) -> some View {
        Button {
            diabetesStatus = value
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
                Image(systemName: diabetesStatus == value ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(diabetesStatus == value ? .miyaPrimary : .miyaTextSecondary.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func conditionToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        // Guided setup must not use Toggle switches. Use the same checkmark-row interaction as self onboarding.
        SelectableConditionRow(title: label, isSelected: isOn)
    }
    
    private func familyHistoryToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            if label.contains("Not sure") {
                isOn.wrappedValue.toggle()
            } else if !familyHistoryNotSure {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .foregroundColor(isOn.wrappedValue ? .miyaPrimary : .miyaTextSecondary.opacity(0.4))
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(familyHistoryNotSure && !label.contains("Not sure") ? .miyaTextSecondary.opacity(0.5) : .miyaTextPrimary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(familyHistoryNotSure && !label.contains("Not sure"))
    }
    
    // MARK: - Actions
    
    private func handleBack() {
        if currentStep > 1 {
            currentStep -= 1
        } else {
            dismiss()
        }
    }
    
    private func handleContinue() {
        if currentStep < totalSteps {
            currentStep += 1
        } else {
            saveGuidedData()
        }
    }
    
    private func saveGuidedData() {
        isLoading = true
        
        Task {
            do {
                // VERIFIABLE TRACE: confirm we're writing to family_members.id and record current status before writes.
                #if DEBUG
                let before = try? await dataManager.fetchFamilyMemberRecord(memberId: memberId)
                print("🧾 GUIDED_ADMIN_SAVE_BEGIN memberId=\(memberId) currentStatus=\(before?.guidedSetupStatus ?? "nil") action=saveGuidedHealthData")
                #endif
                
                // Format date
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let dobString = dateFormatter.string(from: dateOfBirth)
                
                // Build guided health data
                let aboutYou = GuidedHealthData.AboutYouData(
                    gender: selectedGender?.rawValue ?? "Male",
                    dateOfBirth: dobString,
                    heightCm: Double(heightCm) ?? 170,
                    weightKg: Double(weightKg) ?? 70,
                    ethnicity: selectedEthnicity?.rawValue ?? "White",
                    smokingStatus: smokingStatus?.rawValue ?? "Never"
                )
                
                let heartHealth = GuidedHealthData.HeartHealthData(
                    bloodPressureStatus: bloodPressureStatus,
                    diabetesStatus: diabetesStatus,
                    hasPriorHeartAttack: hasPriorHeartAttack,
                    hasPriorStroke: hasPriorStroke,
                    hasChronicKidneyDisease: hasChronicKidneyDisease,
                    hasAtrialFibrillation: hasAtrialFibrillation,
                    hasHighCholesterol: hasHighCholesterol
                )
                
                let medicalHistory = GuidedHealthData.MedicalHistoryData(
                    familyHeartDiseaseEarly: familyHeartDiseaseEarly,
                    familyStrokeEarly: familyStrokeEarly,
                    familyType2Diabetes: familyType2Diabetes
                )
                
                let guidedData = GuidedHealthData(
                    aboutYou: aboutYou,
                    heartHealth: heartHealth,
                    medicalHistory: medicalHistory
                )
                
                // Save to database
                #if DEBUG
                print("🧾 GUIDED_ADMIN_SAVE_CALL memberId=\(memberId) fn=saveGuidedHealthData")
                #endif
                try await dataManager.saveGuidedHealthData(memberId: memberId, healthData: guidedData)
                #if DEBUG
                print("✅ GUIDED_ADMIN_SAVE_OK memberId=\(memberId) fn=saveGuidedHealthData")
                #endif
                
                // Required transition: accepted_awaiting_data -> data_complete_pending_review (+ guided_data_filled_at)
                #if DEBUG
                print("🧾 GUIDED_ADMIN_SAVE_CALL memberId=\(memberId) fn=updateGuidedSetupStatus newStatus=data_complete_pending_review")
                #endif
                try await dataManager.updateGuidedSetupStatus(memberId: memberId, status: .dataCompletePendingReview)
                
                #if DEBUG
                print("✅ GUIDED_ADMIN_SAVE_OK memberId=\(memberId) fn=updateGuidedSetupStatus newStatus=data_complete_pending_review")
                let after = try? await dataManager.fetchFamilyMemberRecord(memberId: memberId)
                print("🧾 GUIDED_ADMIN_SAVE_AFTER memberId=\(memberId) newStatus=\(after?.guidedSetupStatus ?? "nil") filledAt=\(after?.guidedDataFilledAt?.description ?? "nil")")
                #endif
                
                await MainActor.run {
                    isLoading = false
                    onComplete()
                    dismiss()
                }
                
            } catch {
                #if DEBUG
                print("❌ GUIDED_ADMIN_SAVE_FAIL memberId=\(memberId) error=\(error)")
                #endif
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

#Preview("Step: Guided health data entry") {
    GuidedHealthDataEntryFlow(
        memberId: UUID().uuidString,
        memberName: "Preview Member",
        inviteCode: "PREVIEW-1234",
        onComplete: {}
    )
    .environmentObject(DataManager())
}

// MARK: - ONBOARDING COMPLETE SUMMARY

struct OnboardingCompleteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    
    let membersCount: Int
    
    @State private var navigateToDashboard: Bool = false
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("You're all set!")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Welcome to your family health journey ✨")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 32)
                
                // Summary cards
                VStack(spacing: 12) {
                    SummaryRow(
                        title: "Family created",
                        value: onboardingManager.familyName.isEmpty ? "Your family" : onboardingManager.familyName
                    )
                    
                    SummaryRow(
                        title: "Members added",
                        value: membersCount == 0 ? "Just you (for now)" : "\(membersCount) member\(membersCount == 1 ? "" : "s")"
                    )
                    
                    SummaryRow(
                        title: "Device connected",
                        value: "From your wearable setup"
                    )
                }
                .padding(.horizontal, 24)
                
                // What's next
                VStack(alignment: .leading, spacing: 10) {
                    Text("What's next?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Your dashboard awaits")
                        Text("  Personalised health insights ready to explore.")
                        
                        Text("• Start tracking")
                        Text("  Daily activities and wellness metrics at your fingertips.")
                        
                        Text("• Meet Miya")
                        Text("  Get calm, clear guidance from Miya for your whole family.")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.miyaTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Buttons
                VStack(spacing: 10) {
                    Button {
                        navigateToDashboard = true
                    } label: {
                        Text("Launch my dashboard")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(18)
                    }
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Back")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.miyaTextSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            
            // Navigation to Dashboard
            NavigationLink(
                destination: DashboardView(familyName: onboardingManager.familyName.isEmpty ? "Miya" : onboardingManager.familyName),
                isActive: $navigateToDashboard
            ) {
                EmptyView()
            }
            .hidden()
        }
        .onAppear {
            // Mark onboarding as complete
            onboardingManager.completeOnboarding()
            print("✅ OnboardingCompleteView: Onboarding marked as complete")
            Task {
                await onboardingManager.refreshGuidedContextFromDB(dataManager: dataManager)
            }
        }
    }
}

#Preview("Step: Onboarding complete") {
    NavigationStack {
        OnboardingCompleteView(membersCount: 2)
            .environmentObject(OnboardingManager())
            .environmentObject(DataManager())
    }
}

struct SummaryRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.miyaTextSecondary)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
        )
    }
}
