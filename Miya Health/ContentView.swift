//
//  ContentView.swift
//  Miya Health
//
//  Created by Josh Kempton on 21/11/2025.
//

import SwiftUI

// ROOT VIEW USED BY Miya_HealthApp
struct ContentView: View {
    var body: some View {
        LandingView()
    }
}

#Preview {
    ContentView()
}

struct LandingView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [.miyaBackground, .white],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 24) {
                    // MARK: - Top Logo / Brand
                    Text("Miya Health")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.miyaPrimary)
                        .padding(.top, 32)
                    
                    Spacer(minLength: 0)
                    
                    // MARK: - Hero Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Welcome to your family’s health HQ.")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.miyaTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(
                                    LinearGradient(
                                        colors: [.miyaPrimary.opacity(0.12), .miyaSecondary.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            VStack(spacing: 12) {
                                Image(systemName: "heart.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .foregroundColor(.miyaPrimary)
                                
                                Text("Your family. One heartbeat.")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)
                                
                                Text("A calmer, healthier rhythm for your whole family — built from daily habits, not medical labels.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.miyaTextSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 20)
                            .padding(.horizontal, 16)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    Spacer()
                    
                    // MARK: - Primary actions
                    VStack(spacing: 12) {
                        // Enter Code (placeholder screen)
                        NavigationLink {
                            Text("Invite code onboarding goes here")
                                .navigationTitle("Enter code")
                        } label: {
                            Text("Enter Code")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.miyaPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(18)
                        }
                        
                        // Create new family -> Step 1
                        NavigationLink {
                            SuperadminOnboardingView()
                        } label: {
                            Text("Create a new family")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.miyaPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(18)
                        }
                        
                        Button {
                            // TODO: present your Auth / Login screen
                            print("Go to login screen")
                        } label: {
                            Text("I already have an account")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.miyaTextSecondary)
                                .underline()
                        }
                        .padding(.top, 4)
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

#Preview {
    LandingView()
}

// MARK: - STEP 1: SUPERADMIN ONBOARDING (EMAIL + PASSWORD)

struct SuperadminOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    
    private let totalSteps: Int = 8
    private let currentStep: Int = 1
    
    private var passwordsMatch: Bool {
        !password.isEmpty && !confirmPassword.isEmpty && password == confirmPassword
    }
    
    private var isFormValid: Bool {
        guard !email.isEmpty,
              !password.isEmpty,
              !confirmPassword.isEmpty else { return false }
        guard password.count >= 8 else { return false }
        guard passwordsMatch else { return false }
        return true
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                
                // Progress bar
                OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 16)
                
                // Title + subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Secure your family’s health hub")
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
                                
                                Text(passwordsMatch ? "Passwords match" : "Passwords don’t match")
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

                    NavigationLink {
                        FamilySetupView()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isFormValid ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(!isFormValid)
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    NavigationStack {
        SuperadminOnboardingView()
    }
}

// MARK: - STEP 2: FAMILY SETUP VIEW

struct FamilySetupView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var familyName: String = ""
    @State private var selectedFamilySize: FamilySizeOption? = nil
    
    private let totalSteps: Int = 8
    private let currentStep: Int = 2
    
    private var isFormValid: Bool {
        !familyName.trimmingCharacters(in: .whitespaces).isEmpty && selectedFamilySize != nil
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 16)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Build your health team")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Let’s set up your family’s health journey.")
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
                
                Spacer()
                
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
                    
                    // Step 2 should go to Step 3 (WearableSelectionView)
                    NavigationLink {
                        WearableSelectionView()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isFormValid ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(!isFormValid)
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
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

private extension Color {
    static let miyaPrimary = Color(red: 0/255, green: 155/255, blue: 138/255)   // #009B8A
    static let miyaSecondary = Color(red: 248/255, green: 207/255, blue: 146/255)
    static let miyaBackground = Color(red: 247/255, green: 250/255, blue: 249/255) // #F7FAF9
    static let miyaTextPrimary = Color(red: 30/255, green: 46/255, blue: 61/255)
    static let miyaTextSecondary = Color(red: 94/255, green: 110/255, blue: 116/255)
}
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
}

struct WearableSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedWearable: WearableType? = nil
    @State private var isConnecting: Bool = false
    @State private var connectionProgress: Double = 0.0
    @State private var connectedWearables: Set<WearableType> = []
    
    private let totalSteps: Int = 8
    private let currentStep: Int = 3
    
    private var canContinue: Bool {
        !connectedWearables.isEmpty
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                
                // Progress bar: Step 3 of 8
                OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 16)
                
                // Title + subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Link your health tech")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("We’ll sync automatically — set it and forget it ✨")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Wearable list
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(WearableType.allCases) { wearable in
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
                }
                
                Spacer()
                
                // Back + Continue
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
                    
                    // Step 3 should go to Step 4 (AboutYouView)
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
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
            // Watch the animated progress to mark connection complete
            .onChange(of: connectionProgress) { newValue in
                if newValue >= 1.0, isConnecting {
                    isConnecting = false
                    if let selected = selectedWearable {
                        connectedWearables.insert(selected)
                    }
                }
            }
        }
    }
    
    private func handleConnectTapped(for wearable: WearableType) {
        // If already connected, do nothing
        if connectedWearables.contains(wearable) || isConnecting {
            return
        }
        
        selectedWearable = wearable
        isConnecting = true
        connectionProgress = 0.0
        
        // Animate from 0 → 1 over 3 seconds
        withAnimation(.linear(duration: 3.0)) {
            connectionProgress = 1.0
        }
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
    case black = "Black"
    case asian = "Asian"
    case hispanic = "Hispanic"
    case other = "Other"
    
    var id: String { rawValue }
}

enum SmokingStatus: String, CaseIterable, Identifiable {
    case never = "Never"
    case former = "Former"
    case current = "Current"
    
    var id: String { rawValue }
}

struct AboutYouView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let totalSteps: Int = 8
    private let currentStep: Int = 4
    
    @State private var selectedGender: Gender? = nil
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var selectedEthnicity: Ethnicity? = nil
    @State private var smokingStatus: SmokingStatus? = nil
    @State private var heightCm: String = ""
    @State private var weightKg: String = ""
    @State private var nutritionQuality: Double = 3   // 1–5
    
    private var isFormValid: Bool {
        selectedGender != nil &&
        selectedEthnicity != nil &&
        smokingStatus != nil &&
        !heightCm.trimmingCharacters(in: .whitespaces).isEmpty &&
        !weightKg.trimmingCharacters(in: .whitespaces).isEmpty
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
                        
                        // Gender
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Gender *")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
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
                            Text("Smoking status *")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            HStack(spacing: 8) {
                                SmokingPill(label: "Never", status: .never, selected: $smokingStatus)
                                SmokingPill(label: "Former", status: .former, selected: $smokingStatus)
                                SmokingPill(label: "Current", status: .current, selected: $smokingStatus)
                            }
                        }
                        
                        // Height
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Height (cm) *")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            TextField("e.g. 180", text: $heightCm)
                                .keyboardType(.decimalPad)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                                )
                        }
                        
                        // Weight
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Weight (kg) *")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            TextField("e.g. 75", text: $weightKg)
                                .keyboardType(.decimalPad)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1)
                                )
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
                    
                    // Step 4 should go to Step 5 (HeartHealthView)
                    NavigationLink {
                        HeartHealthView()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isFormValid ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(!isFormValid)
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
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
// MARK: - STEP 5: HEART HEALTH

struct HeartHealthView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let totalSteps: Int = 8
    private let currentStep: Int = 5
    
    @State private var hasHypertension: Bool = false
    @State private var hasDiabetes: Bool = false
    @State private var hasCholesterolIssue: Bool = false
    @State private var hasPriorHeartOrStroke: Bool = false
    @State private var isUnsure: Bool = false
    
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
                    
                    Text("Select any that apply. You can skip this if nothing applies.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Select any that apply (optional):")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                            .padding(.bottom, 4)
                        
                        SelectableConditionRow(
                            title: "Blood pressure treatment / hypertension",
                            isSelected: $hasHypertension
                        )
                        
                        SelectableConditionRow(
                            title: "Diabetes status",
                            isSelected: $hasDiabetes
                        )
                        
                        SelectableConditionRow(
                            title: "Cholesterol or lipid disorders",
                            isSelected: $hasCholesterolIssue
                        )
                        
                        SelectableConditionRow(
                            title: "Prior heart attack / stroke / procedure",
                            isSelected: $hasPriorHeartOrStroke
                        )
                        
                        SelectableConditionRow(
                            title: "Unsure",
                            isSelected: $isUnsure
                        )
                    }
                    .padding(.vertical, 4)
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
                    
                    NavigationLink {
                        MedicalHistoryView()    // 👉 STEP 6
                    } label: {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    // Note: always enabled — user doesn't have to select anything
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
    }
}
// MARK: - STEP 6: MEDICAL HISTORY

struct MedicalHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let totalSteps: Int = 8
    private let currentStep: Int = 6
    
    @State private var hasCKD: Bool = false
    @State private var hasAF: Bool = false
    @State private var hasFamilyHistoryHeartDisease: Bool = false
    @State private var isUnsure: Bool = false
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Progress
                OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 16)
                
                // Title + subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Medical history")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Select any that apply. You can skip this if nothing applies.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Select any that apply (optional):")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                            .padding(.bottom, 4)
                        
                        SelectableConditionRow(
                            title: "Chronic kidney disease (CKD)",
                            isSelected: $hasCKD
                        )
                        
                        SelectableConditionRow(
                            title: "Atrial fibrillation / irregular heartbeat",
                            isSelected: $hasAF
                        )
                        
                        SelectableConditionRow(
                            title: "Family history of heart disease (before age 60)",
                            isSelected: $hasFamilyHistoryHeartDisease
                        )
                        
                        SelectableConditionRow(
                            title: "Unsure",
                            isSelected: $isUnsure
                        )
                    }
                    .padding(.vertical, 4)
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
                    
                    // Step 6 should go to the Final Step (WellbeingPrivacyView) which is step 7 currently.
                    NavigationLink {
                        WellbeingPrivacyView()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    // Always allowed – optional selections
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
    }
}
// Reusable selectable row for conditions
struct SelectableConditionRow: View {
    let title: String
    @Binding var isSelected: Bool
    
    var body: some View {
        Button {
            isSelected.toggle()
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextPrimary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? .miyaPrimary : .miyaTextSecondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: isSelected ? Color.black.opacity(0.05) : .clear,
                            radius: 8, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.miyaPrimary : Color.miyaBackground.opacity(0.9),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
// MARK: - FINAL STEP: WELLBEING PRIVACY SHARING

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
    
    // Progress shows step 7 of 8 here.
    private let totalSteps: Int = 8
    private let currentStep: Int = 7
    
    @State private var tier1Option: Tier1SharingOption = .family
    @State private var tier2Option: Tier2SharingOption = .meOnly
    
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
                    
                    // Step 7 -> Step 8 (Invite family members)
                    NavigationLink {
                        FamilyMembersInviteView()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
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
    
    // Navigation to completion
    @State private var navigateToComplete: Bool = false
    
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
                                selectedType: $selectedOnboardingType
                            )
                            
                            OnboardingTypeCard(
                                title: "Self setup",
                                subtitle: "They set up alone",
                                type: .selfSetup,
                                selectedType: $selectedOnboardingType
                            )
                        }
                    }
                    
                    // Generate invite code
                    Button {
                        generateInviteCode()
                    } label: {
                        Text("Generate invite code")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(canGenerateInvite ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(!canGenerateInvite)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                )
                
                Spacer()
                
                // Bottom actions: Back + Finish onboarding
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
                
                // Hidden NavigationLink to push summary when finishing
                NavigationLink(
                    destination: OnboardingCompleteView(membersCount: invitedMembers.count),
                    isActive: $navigateToComplete
                ) {
                    EmptyView()
                }
                .hidden()
            }
            .padding(.horizontal, 24)
        }
        // Invite popup
        .sheet(isPresented: $showInviteSheet) {
            InviteCodeSheet(
                name: currentInviteName,
                code: currentInviteCode
            ) {
                // Done tapped – clear form for the next member
                resetCurrentMemberForm()
            }
        }
    }
    
    private func generateInviteCode() {
        guard let relationship = selectedRelationship,
              let onboardingType = selectedOnboardingType
        else { return }
        
        let code = "MIYA-" + randomCode(4)
        
        // Save to list
        let member = InvitedMember(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            relationship: relationship,
            onboardingType: onboardingType,
            inviteCode: code
        )
        invitedMembers.append(member)
        
        // Set for popup
        currentInviteName = member.firstName
        currentInviteCode = member.inviteCode
        showInviteSheet = true
    }
    
    private func resetCurrentMemberForm() {
        firstName = ""
        selectedRelationship = nil
        selectedOnboardingType = nil
    }
    
    private func randomCode(_ length: Int) -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}

// Card for Guided/Self setup selection
struct OnboardingTypeCard: View {
    let title: String
    let subtitle: String
    let type: MemberOnboardingType
    
    @Binding var selectedType: MemberOnboardingType?
    
    private var isSelected: Bool {
        selectedType == type
    }
    
    var body: some View {
        Button {
            selectedType = type
        } label: {
            HStack(alignment: .center, spacing: 12) {
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
        }
        .buttonStyle(.plain)
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
// MARK: - ONBOARDING COMPLETE SUMMARY

struct OnboardingCompleteView: View {
    @Environment(\.dismiss) private var dismiss
    
    let membersCount: Int
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("You’re all set!")
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
                        value: "Your family" // TODO: replace with real family name
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
                    Text("What’s next?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Your dashboard awaits")
                        Text("  Personalised health insights ready to explore.")
                        
                        Text("• Start tracking")
                        Text("  Daily activities and wellness metrics at your fingertips.")
                        
                        Text("• Meet your AI coach")
                        Text("  Get calm, clear guidance from Arlo for your whole family.")
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
                        print("Launch dashboard tapped")
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
        }
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
