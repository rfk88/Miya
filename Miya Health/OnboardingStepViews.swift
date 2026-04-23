//
//  OnboardingStepViews.swift
//  Miya Health
//
//  Onboarding step views and supporting UI. Edit onboarding screens here.
//

import RookSDK
import HealthKit
import MessageUI
import SwiftUI
import UIKit
import UserNotifications

// MARK: - STEP 1: SUPERADMIN ONBOARDING (SIGN IN WITH APPLE)

struct SuperadminOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.onboardingBackBehavior) private var onboardingBackBehavior
    @Environment(\.onboardingResumeStepBack) private var onboardingResumeStepBack
    
    // Access the managers from the environment
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    
    @State private var firstName: String = ""
    
    // Navigation and error state
    @State private var navigateToNextStep: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isAppleSignInLoading: Bool = false
    /// Inline hint when user taps Sign in with Apple before entering name (no alert).
    @State private var authNameInlineHint: String?

    private let totalSteps: Int = 7
    private let currentStep: Int = 1
    
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
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        TextField("Your name", text: $firstName)
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

                    let nameMissing = firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let appleBlocked = isAppleSignInLoading || authManager.isLoading

                    ZStack {
                        SignInWithAppleButtonView { idToken, nonce, fullName in
                            await handleAppleSignIn(idToken: idToken, nonce: nonce, fullName: fullName)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: MiyaTheme.buttonH)
                        .disabled(appleBlocked)

                        if nameMissing && !appleBlocked {
                            Color.clear
                                .contentShape(RoundedRectangle(cornerRadius: MiyaTheme.radius, style: .continuous))
                                .frame(maxWidth: .infinity)
                                .frame(height: MiyaTheme.buttonH)
                                .onTapGesture {
                                    authNameInlineHint = "Please add your first name above before using Sign in with Apple."
                                }
                        }
                    }

                    Text("Miya uses Sign in with Apple on iPhone — your subscription uses the same Apple ID.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let hint = authNameInlineHint {
                        Text(hint)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        hideKeyboard()
                        OnboardingBackAction.perform(
                            behavior: onboardingBackBehavior,
                            resumeStepBack: onboardingResumeStepBack,
                            dismiss: dismiss,
                            hideKeyboardFirst: false
                        )
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
                }
                .padding(.bottom, 8)
                
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
            onboardingManager.setCurrentStep(1)
            print("📱 SuperadminOnboardingView appeared")
        }
        .onChange(of: firstName) { _ in
            if !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                authNameInlineHint = nil
                showError = false
            }
        }
    }
    
    private func handleAppleSignIn(idToken: String, nonce: String?, fullName: PersonNameComponents?) async {
        showError = false
        isAppleSignInLoading = true
        defer { isAppleSignInLoading = false }
        do {
            let userId = try await authManager.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
            let first = fullName?.givenName ?? fullName?.familyName ?? firstName.trimmingCharacters(in: .whitespacesAndNewlines)
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
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var navigateToNextStep: Bool = false
    
    private let totalSteps: Int = 7
    private let currentStep: Int = 2
    
    private var isFormValid: Bool {
        !familyName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                        .padding(.top, 16)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Set up your family")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.miyaTextPrimary)
                        Text("Miya is built for families. Anyone in your household can connect a wearable—you’ll choose who to invite next, and you can always add more family members later.")
                            .font(.system(size: 15))
                            .foregroundColor(.miyaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
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
                    
                    NavigationLink(destination: WearableSelectionView(), isActive: $navigateToNextStep) { EmptyView() }
                        .hidden()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OnboardingCTABar(
                    onBack: { hideKeyboard(); dismiss() },
                    backDisabled: dataManager.isLoading,
                    onContinue: { hideKeyboard(); Task { await saveFamily() } },
                    continueLabel: dataManager.isLoading ? "Saving..." : "Continue",
                    continueLoading: dataManager.isLoading,
                    continueDisabled: !isFormValid,
                    showError: showError,
                    errorMessage: errorMessage
                )
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            onboardingManager.setCurrentStep(2)
        }
    }
    
    private func saveFamily() async {
        showError = false
        errorMessage = ""
        
        do {
            onboardingManager.familyName = familyName
            onboardingManager.familySize = "twoToFour"
            
            try await dataManager.saveFamily(
                name: familyName,
                size: "twoToFour",
                firstName: onboardingManager.firstName
            )
            
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

// MARK: - STEP 2b: ADDITIONAL FAMILY MEMBERS COUNT

struct AdditionalFamilyMembersCountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.onboardingBackBehavior) private var onboardingBackBehavior
    @Environment(\.onboardingResumeStepBack) private var onboardingResumeStepBack
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager

    @State private var memberCount: Int = 1
    @State private var isLoading: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var navigateToInvites: Bool = false
    @State private var navigateToComplete: Bool = false

    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        OnboardingProgressBar(currentStep: 7, totalSteps: 7)
                            .padding(.top, 16)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Invite your family")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.miyaTextPrimary)
                            Text("How many other family members do you want to invite now? Each person can connect their own wearable. You can skip for now and add people anytime from your dashboard.")
                                .font(.system(size: 15))
                                .foregroundColor(.miyaTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Big visual count picker
                        VStack(spacing: 12) {
                            HStack(spacing: 40) {
                                Button {
                                    if memberCount > 0 { memberCount -= 1 }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 44))
                                        .foregroundColor(memberCount > 0 ? .miyaPrimary : .miyaTextSecondary.opacity(0.25))
                                }
                                .disabled(memberCount == 0)

                                Text("\(memberCount)")
                                    .font(.system(size: 72, weight: .bold))
                                    .foregroundColor(.miyaTextPrimary)
                                    .frame(minWidth: 80)
                                    .multilineTextAlignment(.center)

                                Button {
                                    if memberCount < 10 { memberCount += 1 }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 44))
                                        .foregroundColor(memberCount < 10 ? .miyaPrimary : .miyaTextSecondary.opacity(0.25))
                                }
                                .disabled(memberCount == 10)
                            }

                            Text(countLabel)
                                .font(.system(size: 14))
                                .foregroundColor(.miyaTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }

                // Fixed bottom buttons
                VStack(spacing: 0) {
                    if showError {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                    }

                    HStack(spacing: 12) {
                        Button {
                            OnboardingBackAction.perform(
                                behavior: onboardingBackBehavior,
                                resumeStepBack: onboardingResumeStepBack,
                                dismiss: dismiss,
                                hideKeyboardFirst: false
                            )
                        } label: {
                            Text("Back")
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.clear)
                                .foregroundColor(.miyaTextSecondary)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.miyaBackground, lineWidth: 1))
                        }
                        .disabled(isLoading)

                        Button {
                            Task { await saveMemberCount() }
                        } label: {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                Text(isLoading ? "Saving..." : "Continue")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isLoading ? Color.miyaPrimary.opacity(0.5) : Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }
                        .disabled(isLoading)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                NavigationLink(destination: FamilyMembersInviteView(), isActive: $navigateToInvites) { EmptyView() }
                    .hidden()
                NavigationLink(
                    destination: OnboardingCompleteView(membersCount: onboardingManager.invitedMembers.count)
                        .environmentObject(onboardingManager)
                        .environmentObject(dataManager),
                    isActive: $navigateToComplete
                ) { EmptyView() }
                    .hidden()
            }
        }
        .navigationBarBackButtonHidden(false)
        .onAppear {
            onboardingManager.setCurrentStep(8)
        }
    }

    private var countLabel: String {
        switch memberCount {
        case 0: return "Just you for now — you can invite members later."
        case 1: return "1 additional member"
        default: return "\(memberCount) additional members"
        }
    }

    private func saveMemberCount() async {
        showError = false
        isLoading = true
        defer { isLoading = false }

        onboardingManager.additionalFamilyMembersTarget = memberCount

        do {
            try await dataManager.updateFamilyTierForAdditionalMembers(memberCount)
            if memberCount == 0 {
                navigateToComplete = true
            } else {
                navigateToInvites = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview("Step: Additional member count") {
    NavigationStack {
        AdditionalFamilyMembersCountView()
            .environmentObject(DataManager())
            .environmentObject(OnboardingManager())
    }
}

enum FamilySizeOption: String {
    case twoToFour
    case fourToEight
    case ninePlus
}

// Note: FamilySizeOptionCard retained for any legacy usage; no longer shown in onboarding flow.
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
    case garmin
    
    var id: String { rawValue }
    
    /// Order on the link screen (API sources first, Apple last).
    static let linkScreenOrder: [WearableType] = [.whoop, .oura, .fitbit, .garmin, .appleWatch]
    
    /// Asset catalog image set name (`WearableLogo*` in Assets.xcassets).
    var logoAssetName: String {
        switch self {
        case .appleWatch: return "WearableLogoApple"
        case .whoop:      return "WearableLogoWhoop"
        case .oura:       return "WearableLogoOura"
        case .fitbit:     return "WearableLogoFitbit"
        case .garmin:     return "WearableLogoGarmin"
        }
    }
    
    /// Secondary line under the title (Apple only, for parity with prior copy).
    var cardSubtitle: String? {
        switch self {
        case .appleWatch: return "Connect via Apple Health"
        default: return nil
        }
    }
    
    var displayName: String {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .whoop:      return "WHOOP"
        case .oura:       return "Oura Ring"
        case .fitbit:     return "Fitbit"
        case .garmin:     return "Garmin"
        }
    }
    
    /// SF Symbol fallback if a catalog logo is missing at runtime.
    var systemImageName: String {
        switch self {
        case .appleWatch: return "applewatch"
        case .whoop:      return "bolt.heart"
        case .oura:       return "moon.stars"
        case .fitbit:     return "figure.walk"
        case .garmin:     return "figure.run"
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
        case .garmin:     return "garmin"
        }
    }
    
    /// Returns true if this wearable uses Rook's REST API (not SDK)
    var isAPIBasedSource: Bool {
        rookDataSourceId != nil
    }
}

extension WearableType {
    /// Title for the account sidebar sync row: uses linked `connected_wearables` types; prefers API sources over Apple (same order as the link screen).
    static func accountSidebarWearableTitle(connectedRawValues: [String]) -> String {
        let keys = Set(connectedRawValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard !keys.isEmpty else { return "Wearable data" }
        for wearable in Self.linkScreenOrder where keys.contains(wearable.rawValue) {
            if wearable == .appleWatch { return "Apple Health" }
            return wearable.displayName
        }
        return "Wearable data"
    }
}

struct WearableSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.onboardingBackBehavior) private var onboardingBackBehavior
    @Environment(\.onboardingResumeStepBack) private var onboardingResumeStepBack
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    // Flag for invited users with Guided Setup (skip full onboarding after wearables)
    var isGuidedSetupInvite: Bool = false
    
    // Flag for dashboard reconnect mode (no onboarding navigation, just dismiss)
    var isReconnectMode: Bool = false
    
    @State private var selectedWearable: WearableType? = nil
    @State private var isConnecting: Bool = false
    @State private var connectedWearables: Set<WearableType> = []
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showAuthorizationView: Bool = false
    @State private var authorizationDataSource: String? = nil
    @State private var authorizationDataSourceName: String? = nil
    
    /// Full-screen loader (Apple Health / Rook SDK path only).
    @State private var isWaitingForConnection: Bool = false
    @State private var connectingWearableName: String? = nil
    
    /// After API OAuth sheet closes: poll Rook in the background while staying on the link screen.
    @State private var isVerifyingAPIConnection: Bool = false
    /// User tapped Cancel on the OAuth sheet — skip verification polling.
    @State private var apiOAuthUserCancelled: Bool = false
    
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
                
                // Wearable list (single card pattern; Apple uses Rook SDK path only)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(WearableType.linkScreenOrder) { wearable in
                        WearableCard(
                            wearable: wearable,
                            isSelected: selectedWearable == wearable,
                            isConnecting: isConnecting && selectedWearable == wearable,
                            isConnected: connectedWearables.contains(wearable)
                        ) {
                            if wearable == .appleWatch {
                                presentRookConnect()
                            } else {
                                handleConnectTapped(for: wearable)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Back + Continue / Done
                HStack(spacing: 12) {
                    if !isReconnectMode {
                        Button {
                            OnboardingBackAction.perform(
                                behavior: onboardingBackBehavior,
                                resumeStepBack: onboardingResumeStepBack,
                                dismiss: dismiss,
                                hideKeyboardFirst: false
                            )
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
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showAuthorizationView, onDismiss: {
            handleOAuthSheetDismissed()
        }) {
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
                                apiOAuthUserCancelled = true
                                showAuthorizationView = false
                            }
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
    
    /// Runs when the Rook OAuth sheet is dismissed (any reason). Keeps user on the link screen unless they cancelled.
    private func handleOAuthSheetDismissed() {
        print("🟡 WearableSelectionView: OAuth sheet dismissed (cancelled=\(apiOAuthUserCancelled))")
        if apiOAuthUserCancelled {
            apiOAuthUserCancelled = false
            Task { @MainActor in
                isConnecting = false
                isVerifyingAPIConnection = false
                await checkAPIWearableConnectionStatus()
            }
            return
        }
        guard authorizationDataSource != nil else {
            Task { await checkAPIWearableConnectionStatus() }
            return
        }
        // Stay on link screen: card shows Connecting… while we verify in the background (no full-screen takeover).
        isVerifyingAPIConnection = true
        isConnecting = true
        Task {
            await pollUntilAPIConnectionVerified()
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
                        isConnecting = false
                        errorMessage = "Please sign in first to connect your wearable."
                        showError = true
                    }
                    return
                }
                
                print("✅ WearableSelectionView: Got user ID: \(userId)")
                
                guard let dataSourceId = wearable.rookDataSourceId else {
                    print("❌ WearableSelectionView: No Rook data source ID for \(wearable.displayName)")
                    await MainActor.run {
                        isConnecting = false
                        errorMessage = "Invalid data source"
                        showError = true
                    }
                    return
                }
                
                print("🟢 WearableSelectionView: Setting authorization view for \(dataSourceId)")
                await MainActor.run {
                    apiOAuthUserCancelled = false
                    authorizationDataSource = dataSourceId
                    authorizationDataSourceName = wearable.displayName
                    isConnecting = true
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
                    // Stay on link screen: user taps Continue when ready (no auto-advance from API verify).
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
            let done = await MainActor.run { () -> Bool in
                if !isVerifyingAPIConnection { return true }
                guard let ds = authorizationDataSource,
                      let wearable = WearableType.allCases.first(where: { $0.rookDataSourceId == ds }) else {
                    return true
                }
                if connectedWearables.contains(wearable) {
                    isVerifyingAPIConnection = false
                    isConnecting = false
                    return true
                }
                return false
            }
            if done { return }
            try? await Task.sleep(nanoseconds: delaySeconds)
        }
        await MainActor.run {
            if isVerifyingAPIConnection {
                isVerifyingAPIConnection = false
                isConnecting = false
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
                    print("🟢 RookConnect: Requesting Apple Health permissions (production)")
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

/// On-brand indeterminate “connecting” motion (card row + Apple full-screen loader).
private struct MiyaConnectingGlyph: View {
    var diameter: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Group {
            if reduceMotion {
                ProgressView()
                    .tint(Color.miyaPrimary)
                    .frame(width: diameter, height: diameter)
            } else {
                TimelineView(.periodic(from: .now, by: 0.032)) { context in
                    let seconds = context.date.timeIntervalSinceReferenceDate
                    let angle = (seconds * 220).truncatingRemainder(dividingBy: 360)
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(Color.miyaPrimary.opacity(0.92 - Double(i) * 0.24))
                                .frame(width: max(4, diameter * 0.19), height: max(4, diameter * 0.19))
                                .offset(y: -(diameter * 0.38))
                                .rotationEffect(.degrees(Double(i) * 120 + angle))
                        }
                    }
                    .frame(width: diameter, height: diameter)
                }
            }
        }
    }
}

/// Full-screen animated view shown while waiting for wearable connection to be verified during onboarding.
private struct ConnectingWearableView: View {
    let wearableName: String
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            MiyaConnectingGlyph(diameter: 80)
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
    }
}

/// Fixed-size catalog logo with SF Symbol fallback when the asset is absent.
private struct WearableBrandLogoView: View {
    let wearable: WearableType
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.miyaBackground.opacity(0.45))
            if UIImage(named: wearable.logoAssetName) != nil {
                Image(wearable.logoAssetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .padding(5)
            } else {
                Image(systemName: wearable.systemImageName)
                    .font(.system(size: 22))
                    .foregroundColor(.miyaPrimary)
            }
        }
        .frame(width: 40, height: 40)
    }
}

struct WearableCard: View {
    let wearable: WearableType
    let isSelected: Bool
    let isConnecting: Bool
    let isConnected: Bool
    let onConnectTapped: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                WearableBrandLogoView(wearable: wearable)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(wearable.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    if let subtitle = wearable.cardSubtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.miyaTextSecondary)
                    }
                }
                
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
                        MiyaConnectingGlyph(diameter: 26)
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
    
    private var nutritionDescription: String {
        switch Int(nutritionQuality) {
        case 1: return "1/5 — mostly fast food or processed meals, rarely cooking at home"
        case 2: return "2/5 — frequent eating out, occasional junk food, inconsistent meals"
        case 3: return "3/5 — mix of home cooking and convenience food, some healthy choices"
        case 4: return "4/5 — mostly home-cooked, balanced meals with occasional treats"
        case 5: return "5/5 — consistently healthy, whole-food diet, minimal processed food"
        default: return ""
        }
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Progress
                    OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                        .padding(.top, 16)
                    
                    // Title + subtitle
                    VStack(alignment: .leading, spacing: 8) {
                        OnboardingPersonBadge(
                            firstName: onboardingManager.firstName,
                            lastName: onboardingManager.lastName
                        )
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
                    VStack(alignment: .leading, spacing: 18) {

                        // Biological sex
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Biological sex *")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)

                            HStack(spacing: 10) {
                                ForEach(Gender.allCases) { gender in
                                    Button {
                                        selectedGender = gender
                                    } label: {
                                        HStack {
                                            Text(gender.rawValue)
                                                .font(.system(size: 14))
                                                .foregroundColor(.miyaTextPrimary)
                                            Spacer()
                                            if selectedGender == gender {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.miyaPrimary)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(selectedGender == gender ? Color.miyaPrimary.opacity(0.1) : Color.white)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(selectedGender == gender ? Color.miyaPrimary : Color.miyaBackground.opacity(0.8), lineWidth: 1)
                                        )
                                    }
                                }
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ethnicity *")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(Ethnicity.allCases) { ethnicity in
                                    Button {
                                        selectedEthnicity = ethnicity
                                    } label: {
                                        HStack {
                                            Text(ethnicity.rawValue)
                                                .font(.system(size: 13))
                                                .foregroundColor(.miyaTextPrimary)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                            if selectedEthnicity == ethnicity {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.miyaPrimary)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 10)
                                        .background(selectedEthnicity == ethnicity ? Color.miyaPrimary.opacity(0.1) : Color.white)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(selectedEthnicity == ethnicity ? Color.miyaPrimary : Color.miyaBackground.opacity(0.8), lineWidth: 1)
                                        )
                                    }
                                }
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
                        
                        // Scroll-cue: appears between height and weight when height is entered but form incomplete
                        let heightStarted = useImperial
                            ? !heightFeet.trimmingCharacters(in: .whitespaces).isEmpty
                            : !heightCm.trimmingCharacters(in: .whitespaces).isEmpty
                        if heightStarted && !isFormValid {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundColor(.miyaPrimary)
                                Text("Keep going — fill in weight and nutrition below to continue.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.miyaTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.miyaPrimary.opacity(0.06))
                            .cornerRadius(8)
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
                            Text("Nutrition quality")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("How would you describe your typical diet?")
                                .font(.system(size: 12))
                                .foregroundColor(.miyaTextSecondary)
                            
                            HStack {
                                Text("Poor")
                                    .font(.system(size: 12))
                                    .foregroundColor(.miyaTextSecondary)
                                Slider(value: $nutritionQuality, in: 1...5, step: 1)
                                Text("Excellent")
                                    .font(.system(size: 12))
                                    .foregroundColor(.miyaTextSecondary)
                            }
                            
                            Text(nutritionDescription)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.miyaTextPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.miyaPrimary.opacity(0.07))
                                .cornerRadius(8)
                        }

                        NavigationLink(
                            destination: HeartHealthView()
                                .environmentObject(onboardingManager)
                                .environmentObject(dataManager),
                            isActive: $navigateToNextStep
                        ) {
                            EmptyView()
                        }
                        .hidden()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OnboardingCTABar(
                    onBack: { hideKeyboard(); dismiss() },
                    backDisabled: dataManager.isLoading,
                    onContinue: { hideKeyboard(); Task { await saveProfile() } },
                    continueLabel: dataManager.isLoading ? "Saving..." : "Continue",
                    continueLoading: dataManager.isLoading,
                    continueDisabled: !isFormValid,
                    showError: showError,
                    errorMessage: errorMessage
                )
            }
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
                    .font(.system(size: 17, weight: .semibold))
            }
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
    
    // Medical conditions
    @State private var hasChronicKidneyDisease: Bool = false
    @State private var hasAtrialFibrillation: Bool = false
    @State private var hasHighCholesterol: Bool = false
    
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var navigateToNextStep: Bool = false
    
    var body: some View {
        content
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

    private var content: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                        .padding(.top, 16)
                    headerSection
                    formSections
                    nextStepLink
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OnboardingCTABar(
                    onBack: { dismiss() },
                    backDisabled: dataManager.isLoading,
                    onContinue: { Task { await saveHeartHealth() } },
                    continueLabel: dataManager.isLoading ? "Saving..." : "Continue",
                    continueLoading: dataManager.isLoading,
                    continueDisabled: bloodPressureStatus == nil || diabetesStatus == nil,
                    showError: showError,
                    errorMessage: errorMessage
                )
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnboardingPersonBadge(
                firstName: onboardingManager.firstName,
                lastName: onboardingManager.lastName
            )
            Text("Heart health")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.miyaTextPrimary)

            Text("This helps us understand your cardiovascular health. Answer as best you can.")
                .font(.system(size: 15))
                .foregroundColor(.miyaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formSections: some View {
        VStack(alignment: .leading, spacing: 24) {
            bloodPressureSection
            diabetesSection
            historySection
            otherConditionsSection
        }
    }

    private var bloodPressureSection: some View {
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
                    statusButton(
                        label: status.displayText,
                        selected: bloodPressureStatus == status
                    ) {
                        bloodPressureStatus = status
                    }
                }
            }
        }
    }

    private var diabetesSection: some View {
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
                    statusButton(
                        label: status.displayText,
                        selected: diabetesStatus == status
                    ) {
                        diabetesStatus = status
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Medical History")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)

            Text("Have you ever had any of the following?")
                .font(.system(size: 13))
                .foregroundColor(.miyaTextSecondary)

            VStack(spacing: 8) {
                ConditionToggleRow(title: "Heart attack", isOn: $hasPriorHeartAttack)
                ConditionToggleRow(title: "Stroke", isOn: $hasPriorStroke)
            }
        }
    }

    private var otherConditionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Other Conditions")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)

            Text("Do you have any of these conditions?")
                .font(.system(size: 13))
                .foregroundColor(.miyaTextSecondary)

            VStack(spacing: 8) {
                ConditionToggleRow(title: "Chronic kidney disease", isOn: $hasChronicKidneyDisease)
                ConditionToggleRow(title: "Atrial fibrillation (irregular heartbeat)", isOn: $hasAtrialFibrillation)
                ConditionToggleRow(title: "High cholesterol (diagnosed by doctor)", isOn: $hasHighCholesterol)
            }
        }
    }

    private var nextStepLink: some View {
        NavigationLink(
            destination: MedicalHistoryView(),
            isActive: $navigateToNextStep
        ) {
            EmptyView()
        }
        .hidden()
    }

    private func statusButton(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.miyaPrimary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? Color.miyaPrimary.opacity(0.1) : Color.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.miyaPrimary : Color.gray.opacity(0.3), lineWidth: 1)
            )
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
            
            ScrollView {
                VStack(spacing: 24) {
                    // Progress
                    OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                        .padding(.top, 16)
                    
                    // Title + subtitle
                    VStack(alignment: .leading, spacing: 8) {
                        OnboardingPersonBadge(
                            firstName: onboardingManager.firstName,
                            lastName: onboardingManager.lastName
                        )
                        Text("Family Health History")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text("Heart disease often runs in families. Understanding your family's health helps us assess your risk.")
                            .font(.system(size: 15))
                            .foregroundColor(.miyaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
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
                        
                        ConditionToggleRow(
                            title: "Heart disease (heart attack, bypass surgery) before age 60",
                            isOn: $familyHeartDiseaseEarly
                        )
                        
                        ConditionToggleRow(
                            title: "Stroke before age 60",
                            isOn: $familyStrokeEarly
                        )
                        
                        ConditionToggleRow(
                            title: "Type 2 diabetes (at any age)",
                            isOn: $familyType2Diabetes
                        )
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        ConditionToggleRow(
                            title: "Not sure / I don't know my family history",
                            isOn: $isUnsure
                        )
                    }

                    // Hidden NavigationLink - goes to Breakout 1 (self-onboarding) or next step based on user type
                    NavigationLink(
                        destination: Group {
                            if showBreakouts {
                                Breakout1View()
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
                                AlertsChampionView()
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
                .padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OnboardingCTABar(
                    onBack: { dismiss() },
                    backDisabled: dataManager.isLoading,
                    onContinue: { Task { await saveMedicalHistory() } },
                    continueLabel: dataManager.isLoading ? "Saving..." : "Continue",
                    continueLoading: dataManager.isLoading,
                    showError: showError,
                    errorMessage: errorMessage
                )
            }
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
// Name label shown above screen titles to anchor personal health data entry
struct OnboardingPersonBadge: View {
    let firstName: String
    let lastName: String

    private var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var body: some View {
        if !firstName.isEmpty {
            Text(fullName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.miyaTextSecondary)
        }
    }
}

// Reusable toggle row for conditions (used in onboarding)
struct ConditionToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.miyaTextPrimary)
                .multilineTextAlignment(.leading)
        }
        .toggleStyle(SwitchToggleStyle(tint: .miyaPrimary))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isOn ? Color.miyaPrimary : Color.miyaBackground.opacity(0.9), lineWidth: isOn ? 1.5 : 1)
        )
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
    
    @State private var navigateToInviteSetup: Bool = false
    @State private var navigateToComplete: Bool = false
    @State private var showPushDeniedAlert: Bool = false
    @State private var showPushEnabledConfirmation: Bool = false
    @State private var isSaving: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var allowOpenAIThirdParty: Bool = false
    @State private var showOpenAIThirdPartyExplainer: Bool = false
    @State private var showAIReminderSheet: Bool = false
    @State private var showAIBenefitsSheet: Bool = false
    /// True when benefits sheet is dismissed after a button already ran save/navigation.
    @State private var aiBenefitsDismissSkipFollowUpSave: Bool = false
    /// Avoid presenting benefits after reminder dismiss when user chose Turn on (state batching).
    @State private var skipBenefitsAfterReminderDismiss: Bool = false

    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            content
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .onAppear {
            onboardingManager.setCurrentStep(onboardingManager.isInvitedUser ? 6 : 7)
        }
        .onChange(of: onboardingManager.notifyPush) { _, isEnabled in
            guard isEnabled else { return }
            requestPushAuthorizationFromPrivacyStep()
        }
        .alert("Push Notifications Blocked", isPresented: $showPushDeniedAlert) {
            Button("Not now", role: .cancel) {
                onboardingManager.notifyPush = false
            }
            Button("Open Settings") {
                onboardingManager.notifyPush = false
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Notifications were previously turned off for Miya on this device. Apple requires you to re-enable them in Settings > Miya > Notifications.")
        }
        .overlay(alignment: .top) {
            if showPushEnabledConfirmation {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Push notifications enabled")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.miyaTextPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeOut(duration: 0.3), value: showPushEnabledConfirmation)
            }
        }
        .sheet(isPresented: $showAIReminderSheet, onDismiss: {
            if skipBenefitsAfterReminderDismiss {
                skipBenefitsAfterReminderDismiss = false
                return
            }
            if !allowOpenAIThirdParty {
                DispatchQueue.main.async {
                    showAIBenefitsSheet = true
                }
            }
        }) {
            OnboardingAIReminderSheet(
                onTurnOn: {
                    skipBenefitsAfterReminderDismiss = true
                    allowOpenAIThirdParty = true
                    showAIReminderSheet = false
                    Task { await saveAlertPreferencesAndContinue() }
                },
                onNoThanks: {
                    showAIReminderSheet = false
                }
            )
        }
        .sheet(isPresented: $showAIBenefitsSheet, onDismiss: {
            if aiBenefitsDismissSkipFollowUpSave {
                aiBenefitsDismissSkipFollowUpSave = false
                return
            }
            if !allowOpenAIThirdParty {
                Task { await saveAlertPreferencesAndContinue() }
            }
        }) {
            OnboardingAIBenefitsSheet(
                onTurnOnAndContinue: {
                    allowOpenAIThirdParty = true
                    aiBenefitsDismissSkipFollowUpSave = true
                    showAIBenefitsSheet = false
                    Task { await saveAlertPreferencesAndContinue() }
                },
                onContinueWithoutAI: {
                    aiBenefitsDismissSkipFollowUpSave = true
                    showAIBenefitsSheet = false
                    Task { await saveAlertPreferencesAndContinue() }
                }
            )
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 24) {
                OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 16)

                headerSection
                cardsSection
                navigationLinks
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingCTABar(
                onBack: { hideKeyboard(); dismiss() },
                backDisabled: isSaving,
                onContinue: { Task { await handlePrivacyAlertsContinueTapped() } },
                continueLabel: isSaving ? "Saving…" : (onboardingManager.isInvitedUser ? "Finish Setup" : "Continue"),
                continueLoading: isSaving,
                showError: showError,
                errorMessage: errorMessage
            )
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy & Alerts")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.miyaTextPrimary)

            Text("Set the essentials now so you can invite family with confidence. You can fine-tune detailed sharing rules from your dashboard later.")
                .font(.system(size: 15))
                .foregroundColor(.miyaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            notificationCard
            smartAlertTimingCard
            openAIThirdPartyCard
            infoBanner
        }
    }
    
    private var openAIThirdPartyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("Optional AI features — powered by OpenAI")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
                Button {
                    showOpenAIThirdPartyExplainer = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.miyaPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Learn how Miya AI is used")
            }
            Text("Miya uses OpenAI's API for family chat, insights, and message suggestions. Enabling this sends limited health context to OpenAI. Leave this off if you prefer.")
                .font(.system(size: 13))
                .foregroundColor(.miyaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $allowOpenAIThirdParty) {
                Text("I agree to share limited data with OpenAI for these features")
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextPrimary)
            }
            .tint(.miyaPrimary)
            Text("Off by default — you can change this anytime in Settings.")
                .font(.system(size: 12))
                .foregroundColor(.miyaTextSecondary)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        .sheet(isPresented: $showOpenAIThirdPartyExplainer) {
            NavigationStack {
                ScrollView {
                    MiyaAIDataSharingExplainerContent()
                        .padding(24)
                }
                .background(Color.miyaBackground.ignoresSafeArea())
                .navigationTitle("Miya AI")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showOpenAIThirdPartyExplainer = false }
                    }
                }
            }
        }
    }

    private var notificationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How should Miya notify you?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)
            Text("Pick the channels you want right now.")
                .font(.system(size: 13))
                .foregroundColor(.miyaTextSecondary)

            VStack(spacing: 8) {
                NotificationToggleRow(title: "In-app notifications", isOn: $onboardingManager.notifyInApp)
                NotificationToggleRow(title: "Push notifications", isOn: $onboardingManager.notifyPush)
                NotificationToggleRow(title: "Email notifications", isOn: $onboardingManager.notifyEmail)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    private var smartAlertTimingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "bell.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Alert Timing")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)

                    Text("How pattern alerts escalate over time")
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
                    description: "Other family members on Miya are notified too",
                    color: .orange
                )

                AlertTimingRow(
                    day: "21",
                    severity: "Critical",
                    description: "Everyone in your family on Miya is notified",
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
    }

    private var infoBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.miyaPrimary)
                Text("Fine-tune later")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }

            Text("Detailed per-person and per-metric privacy controls are available from your dashboard anytime.")
                .font(.system(size: 13))
                .foregroundColor(.miyaTextSecondary)
        }
        .padding(12)
        .background(Color.miyaPrimary.opacity(0.1))
        .cornerRadius(12)
    }

    private var navigationLinks: some View {
        Group {
            NavigationLink(
                destination: AdditionalFamilyMembersCountView()
                    .environmentObject(onboardingManager)
                    .environmentObject(dataManager),
                isActive: $navigateToInviteSetup
            ) {
                EmptyView()
            }
            .hidden()

            NavigationLink(
                destination: OnboardingCompleteView(membersCount: onboardingManager.invitedMembers.count)
                    .environmentObject(onboardingManager)
                    .environmentObject(dataManager),
                isActive: $navigateToComplete
            ) {
                EmptyView()
            }
            .hidden()
        }
    }

    @MainActor
    private func handlePrivacyAlertsContinueTapped() async {
        if allowOpenAIThirdParty {
            await saveAlertPreferencesAndContinue()
        } else {
            showAIReminderSheet = true
        }
    }

    private func saveAlertPreferencesAndContinue() async {
        hideKeyboard()
        showError = false
        isSaving = true
        defer { isSaving = false }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        do {
            try await dataManager.saveAlertPreferences(
                notifyInApp: onboardingManager.notifyInApp,
                notifyPush: onboardingManager.notifyPush,
                notifyEmail: onboardingManager.notifyEmail,
                quietStart: formatter.string(from: onboardingManager.quietHoursStart),
                quietEnd: formatter.string(from: onboardingManager.quietHoursEnd),
                quietApplyCritical: onboardingManager.quietHoursApplyCritical
            )
            try await dataManager.applyAIThirdPartyConsent(
                enabled: allowOpenAIThirdParty,
                source: allowOpenAIThirdParty ? "onboarding_agree" : "onboarding_decline"
            )
        } catch {
            showError = true
            errorMessage = "Couldn't save your preferences. Please try again."
            return
        }

        if onboardingManager.isInvitedUser {
            navigateToComplete = true
        } else {
            navigateToInviteSetup = true
        }
    }

    private func requestPushAuthorizationFromPrivacyStep() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
#if DEBUG
            let label: String
            switch status {
            case .notDetermined: label = "notDetermined"
            case .denied:        label = "denied"
            case .authorized:    label = "authorized"
            case .provisional:   label = "provisional"
            case .ephemeral:     label = "ephemeral"
            @unknown default:    label = "unknown"
            }
            print("🔔 PushAuth: current status = \(label)")
#endif
            switch status {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                    showPushEnabledConfirmation = true
                    hidePushConfirmationAfterDelay()
                }
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async {
                        if granted {
                            UIApplication.shared.registerForRemoteNotifications()
                            showPushEnabledConfirmation = true
                            hidePushConfirmationAfterDelay()
                        } else {
                            onboardingManager.notifyPush = false
                            showPushDeniedAlert = true
                        }
                    }
                }
            case .denied:
                DispatchQueue.main.async {
                    onboardingManager.notifyPush = false
                    showPushDeniedAlert = true
                }
            @unknown default:
                DispatchQueue.main.async {
                    onboardingManager.notifyPush = false
                }
            }
        }
    }

    private func hidePushConfirmationAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showPushEnabledConfirmation = false }
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
    @Environment(\.onboardingBackBehavior) private var onboardingBackBehavior
    @Environment(\.onboardingResumeStepBack) private var onboardingResumeStepBack
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
    @State private var allowOpenAIThirdParty: Bool = false
    @State private var showOpenAIThirdPartyExplainerWB: Bool = false
    @State private var showAIReminderSheetWB: Bool = false
    @State private var showAIBenefitsSheetWB: Bool = false
    @State private var aiBenefitsDismissSkipFollowUpSaveWB: Bool = false
    @State private var skipBenefitsAfterReminderDismissWB: Bool = false

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
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                Text("Optional AI — powered by OpenAI")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)
                                Spacer()
                                Button {
                                    showOpenAIThirdPartyExplainerWB = true
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(.miyaPrimary)
                                }
                                .buttonStyle(.plain)
                            }
                            Text("Miya uses OpenAI's API for insights and chat. Enabling this sends limited health context to OpenAI. Leave this off if you prefer.")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                            Toggle(isOn: $allowOpenAIThirdParty) {
                                Text("I agree to share limited data with OpenAI for these features")
                                    .font(.system(size: 14))
                            }
                            .tint(.miyaPrimary)
                            Text("Off by default — you can change this anytime in Settings.")
                                .font(.system(size: 12))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.vertical, 4)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Color.miyaBackground)
                .sheet(isPresented: $showOpenAIThirdPartyExplainerWB) {
                    NavigationStack {
                        ScrollView {
                            MiyaAIDataSharingExplainerContent()
                                .padding(24)
                        }
                        .background(Color.miyaBackground.ignoresSafeArea())
                        .navigationTitle("Miya AI")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showOpenAIThirdPartyExplainerWB = false }
                            }
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
                
                // Buttons
                HStack(spacing: 12) {
                    Button {
                        OnboardingBackAction.perform(
                            behavior: onboardingBackBehavior,
                            resumeStepBack: onboardingResumeStepBack,
                            dismiss: dismiss,
                            hideKeyboardFirst: false
                        )
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
                            await handleWellbeingPrivacyContinueTapped()
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
        .sheet(isPresented: $showAIReminderSheetWB, onDismiss: {
            if skipBenefitsAfterReminderDismissWB {
                skipBenefitsAfterReminderDismissWB = false
                return
            }
            if !allowOpenAIThirdParty {
                DispatchQueue.main.async {
                    showAIBenefitsSheetWB = true
                }
            }
        }) {
            OnboardingAIReminderSheet(
                onTurnOn: {
                    skipBenefitsAfterReminderDismissWB = true
                    allowOpenAIThirdParty = true
                    showAIReminderSheetWB = false
                    Task { await savePrivacySettings() }
                },
                onNoThanks: {
                    showAIReminderSheetWB = false
                }
            )
        }
        .sheet(isPresented: $showAIBenefitsSheetWB, onDismiss: {
            if aiBenefitsDismissSkipFollowUpSaveWB {
                aiBenefitsDismissSkipFollowUpSaveWB = false
                return
            }
            if !allowOpenAIThirdParty {
                Task { await savePrivacySettings() }
            }
        }) {
            OnboardingAIBenefitsSheet(
                onTurnOnAndContinue: {
                    allowOpenAIThirdParty = true
                    aiBenefitsDismissSkipFollowUpSaveWB = true
                    showAIBenefitsSheetWB = false
                    Task { await savePrivacySettings() }
                },
                onContinueWithoutAI: {
                    aiBenefitsDismissSkipFollowUpSaveWB = true
                    showAIBenefitsSheetWB = false
                    Task { await savePrivacySettings() }
                }
            )
        }
        .onAppear {
            // Step 6: Wellbeing Privacy
            onboardingManager.setCurrentStep(6)
        }
    }

    @MainActor
    private func handleWellbeingPrivacyContinueTapped() async {
        if allowOpenAIThirdParty {
            await savePrivacySettings()
        } else {
            showAIReminderSheetWB = true
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
            try await dataManager.applyAIThirdPartyConsent(
                enabled: allowOpenAIThirdParty,
                source: allowOpenAIThirdParty ? "onboarding_agree" : "onboarding_decline"
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

enum RelationshipGroup { case family, supportNetwork }
enum RelationshipDirection { case upward, downward, lateral }

enum MemberRelationship: String, CaseIterable, Identifiable {
    case partner     = "Partner"
    case parent      = "Parent"
    case child       = "Child"
    case sibling     = "Sibling"
    case grandparent = "Grandparent"
    case grandchild  = "Grandchild"
    case other       = "Other"   // UI-only sentinel — never stored directly in the DB

    var id: String { rawValue }

    var group: RelationshipGroup {
        switch self {
        case .other: return .supportNetwork
        default:     return .family
        }
    }

    var direction: RelationshipDirection {
        switch self {
        case .parent, .grandparent: return .upward
        case .child, .grandchild:   return .downward
        default:                    return .lateral
        }
    }

    /// All raw values that may legally appear in the family_members.relationship column.
    /// Excludes the .other sentinel (never stored directly), includes legacy "Other" for
    /// backward compatibility, and includes all MemberRelationshipOtherType sub-type values.
    static var allValidStoredValues: Set<String> {
        let coreValues = Self.allCases
            .filter { $0 != .other }
            .map(\.rawValue)
        let subValues = MemberRelationshipOtherType.allCases.map(\.rawValue)
        return Set(coreValues + subValues + ["Other"])
    }
}

/// Sub-type shown when the user picks "Other" in the relationship picker.
/// The selected sub-type's rawValue is what actually gets written to the DB.
enum MemberRelationshipOtherType: String, CaseIterable, Identifiable {
    case friend         = "Friend"
    case familyFriend   = "Family Friend"
    case carer          = "Carer"
    case extendedFamily = "Extended Family"
    case preferNotToSay = "Prefer not to say"

    var id: String { rawValue }
    var group: RelationshipGroup { .supportNetwork }
    var direction: RelationshipDirection { .lateral }
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

/// Per-slot state for FamilyMembersInviteView. Each slot represents one family member the admin intends to invite.
struct MemberSlot: Identifiable {
    let id = UUID()
    var firstName: String = ""
    var selectedRelationship: MemberRelationship? = nil
    var selectedOtherType: MemberRelationshipOtherType? = nil
    var selectedOnboardingType: MemberOnboardingType? = nil
    var inviteCode: String? = nil

    var isInviteGenerated: Bool { inviteCode != nil }
    var canGenerate: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedRelationship != nil &&
        selectedOnboardingType != nil &&
        (selectedRelationship != .other || selectedOtherType != nil)
    }

    /// The string that gets written to family_members.relationship.
    /// When the user picks "Other" + a sub-type, this returns the sub-type rawValue (e.g. "Friend"),
    /// never the sentinel string "Other".
    var effectiveRelationshipRawValue: String {
        if selectedRelationship == .other, let sub = selectedOtherType {
            return sub.rawValue
        }
        return selectedRelationship?.rawValue ?? ""
    }
}

private enum InviteNameField: Hashable {
    case slot(Int)
}

struct FamilyMembersInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.onboardingBackBehavior) private var onboardingBackBehavior
    @Environment(\.onboardingResumeStepBack) private var onboardingResumeStepBack
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager

    /// When true, this view is presented from the Dashboard/Sidebar (not during onboarding).
    let isPresentedFromDashboard: Bool

    init(isPresentedFromDashboard: Bool = false) {
        self.isPresentedFromDashboard = isPresentedFromDashboard
    }

    @State private var slots: [MemberSlot] = []
    @State private var showInviteSheet = false
    @State private var currentInviteCode = ""
    @State private var currentInviteName = ""
    @State private var showSkipAlert = false
    @State private var skipAlertSlotName = ""
    @State private var skipAlertSlotIndex: Int = 0
    @State private var shouldScrollToSkippedSlot = false
    @State private var navigateToComplete = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var generatingSlotIndex: Int? = nil
    @FocusState private var focusedNameField: InviteNameField?
    @State private var removeSlotIndex: Int?
    @State private var showRemoveConfirm = false

    // MARK: - Helpers

    private var anyInviteGenerated: Bool { slots.contains { $0.isInviteGenerated } }
    private var firstUnfilledIndex: Int? { slots.indices.first { !slots[$0].isInviteGenerated } }
    private var finishButtonLabel: String { anyInviteGenerated ? "Finish" : "Skip for now" }

    private var youDisplayName: String {
        let n = onboardingManager.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "You" : n
    }

    private var familyDisplayLine: String {
        let fam = dataManager.familyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if fam.isEmpty {
            return "Your household includes \(youDisplayName). Invite anyone else who should be part of your family health circle."
        }
        return "\(fam) · \(youDisplayName) is already set up. Invite others below."
    }
    
    var body: some View {
        baseLayout
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedNameField = nil
                    }
                    .font(.system(size: 17, weight: .semibold))
                }
            }
            .sheet(isPresented: $showInviteSheet) {
                InviteCodeSheet(name: currentInviteName, code: currentInviteCode) {
                    if isPresentedFromDashboard { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("What about \(skipAlertSlotName)?", isPresented: $showSkipAlert) {
                Button("Edit") { shouldScrollToSkippedSlot = true }
                Button("Skip", role: .destructive) { navigateToComplete = true }
            } message: {
                Text("You haven't generated an invite code for this person yet.")
            }
            .alert("Remove this invite?", isPresented: $showRemoveConfirm) {
                Button("Cancel", role: .cancel) { removeSlotIndex = nil }
                Button("Remove", role: .destructive) {
                    if let i = removeSlotIndex {
                        removeSlot(at: i)
                    }
                    removeSlotIndex = nil
                }
            } message: {
                Text("You’ll lose what you entered for this person. You can add another invite later.")
            }
            .onAppear {
                if !isPresentedFromDashboard { onboardingManager.setCurrentStep(6) }
                Task { await loadExistingInvites() }
            }
    }

    private var baseLayout: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        Color.clear.frame(height: 0).id("top")
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Invite your family")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.miyaTextPrimary)
                            Text("Create an invite for each person. They’ll use the same app flow you just completed—each family member can connect a wearable to share their health picture with the family.")
                                .font(.system(size: 15))
                                .foregroundColor(.miyaTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 16)

                        // Family baseline
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your family so far")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            Text(familyDisplayLine)
                                .font(.system(size: 14))
                                .foregroundColor(.miyaTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.9)))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1))

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

                        // Slot cards
                        ForEach(slots.indices, id: \.self) { index in
                            slotCard(index: index)
                                .id(index)
                        }

                        // Add another invite
                        Button {
                            slots.append(MemberSlot())
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add another person to invite")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.white)
                            .foregroundColor(.miyaPrimary)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.miyaPrimary.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    inviteBottomBar
                }
                .onChange(of: shouldScrollToSkippedSlot) { triggered in
                    guard triggered else { return }
                    withAnimation { proxy.scrollTo(skipAlertSlotIndex, anchor: .top) }
                    shouldScrollToSkippedSlot = false
                }
            }
        }
    }

    // MARK: - Bottom bar (keyboard-safe via safeAreaInset)

    @ViewBuilder
    private var inviteBottomBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)

            if isPresentedFromDashboard {
                Button { dismiss() } label: {
                    Text("Close")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.miyaPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            } else {
                HStack(spacing: 12) {
                    Button {
                        focusedNameField = nil
                        OnboardingBackAction.perform(
                            behavior: onboardingBackBehavior,
                            resumeStepBack: onboardingResumeStepBack,
                            dismiss: dismiss,
                            hideKeyboardFirst: false
                        )
                    } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.clear)
                            .foregroundColor(.miyaTextSecondary)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.miyaBackground, lineWidth: 1))
                    }

                    Button {
                        focusedNameField = nil
                        handleFinish()
                    } label: {
                        Text(finishButtonLabel)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                NavigationLink(
                    destination: OnboardingCompleteView(membersCount: onboardingManager.invitedMembers.count)
                        .environmentObject(onboardingManager)
                        .environmentObject(dataManager),
                    isActive: $navigateToComplete
                ) {
                    EmptyView()
                }
                .hidden()
            }
        }
        .background(Color.miyaBackground)
    }

    // MARK: - Slot card

    private func inviteCardTitle(for index: Int) -> String {
        "Person to invite \(index + 1)"
    }

    @ViewBuilder
    private func slotCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(inviteCardTitle(for: index))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
                if slots[index].isInviteGenerated {
                    Label("Invited", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                } else if canRemoveSlot(at: index) {
                    Button {
                        requestRemoveSlot(at: index)
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if slots[index].isInviteGenerated {
                VStack(alignment: .leading, spacing: 8) {
                    Text(slots[index].firstName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.miyaTextPrimary)
                    HStack(spacing: 8) {
                        Text(slots[index].inviteCode ?? "")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.miyaPrimary)
                        Spacer()
                        Button {
                            currentInviteCode = slots[index].inviteCode ?? ""
                            currentInviteName = slots[index].firstName
                            showInviteSheet = true
                        } label: {
                            Text("Share")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.miyaPrimary.opacity(0.1))
                                .foregroundColor(.miyaPrimary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Their name")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    TextField("Their name", text: $slots[index].firstName)
                        .focused($focusedNameField, equals: .slot(index))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1))
                }

                // Relationship
                VStack(alignment: .leading, spacing: 6) {
                    Text("Relationship")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    Menu {
                        ForEach(MemberRelationship.allCases) { relation in
                            Button(relation.rawValue) {
                                slots[index].selectedRelationship = relation
                                slots[index].selectedOtherType = nil
                            }
                        }
                    } label: {
                        HStack {
                            Text(slots[index].selectedRelationship?.rawValue ?? "Select relationship")
                                .foregroundColor(slots[index].selectedRelationship == nil ? .miyaTextSecondary : .miyaTextPrimary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1))
                    }

                    if slots[index].selectedRelationship == .other {
                        Menu {
                            ForEach(MemberRelationshipOtherType.allCases) { subType in
                                Button(subType.rawValue) { slots[index].selectedOtherType = subType }
                            }
                        } label: {
                            HStack {
                                Text(slots[index].selectedOtherType?.rawValue ?? "Tell us a bit more")
                                    .foregroundColor(slots[index].selectedOtherType == nil ? .miyaTextSecondary : .miyaTextPrimary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.miyaTextSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.miyaBackground.opacity(0.8), lineWidth: 1))
                        }
                    }
                }

                // Who creates their profile (stored values unchanged: Guided Setup / Self Setup)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Who creates their profile")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    VStack(spacing: 10) {
                        OnboardingTypeCard(
                            title: "Set it up for them",
                            subtitle: "You’ll create their profile in a few steps. Best for parents or family members who aren’t tech-savvy.",
                            type: .guided,
                            isEnabled: true,
                            selectedType: $slots[index].selectedOnboardingType
                        )
                        OnboardingTypeCard(
                            title: "They’ll set it up themselves",
                            subtitle: "We’ll send them a link so they can create their own profile.",
                            type: .selfSetup,
                            isEnabled: true,
                            selectedType: $slots[index].selectedOnboardingType
                        )
                    }
                    Text("They’ll answer the same health questions you just completed for yourself.")
                        .font(.system(size: 12))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Generate button
                Button {
                    Task { await generateInviteForSlot(at: index) }
                } label: {
                    HStack(spacing: 8) {
                        if generatingSlotIndex == index {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(generatingSlotIndex == index ? "Generating..." : "Generate invite code")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(slots[index].canGenerate && generatingSlotIndex == nil
                                ? Color.miyaPrimary : Color.miyaPrimary.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                .disabled(!slots[index].canGenerate || generatingSlotIndex != nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
    }

    // MARK: - Actions

    private func canRemoveSlot(at index: Int) -> Bool {
        guard slots.indices.contains(index), !slots[index].isInviteGenerated else { return false }
        return slots.count > 1
    }

    private func requestRemoveSlot(at index: Int) {
        guard canRemoveSlot(at: index) else { return }
        let slot = slots[index]
        let hasContent =
            !slot.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || slot.selectedRelationship != nil
            || slot.selectedOnboardingType != nil
            || slot.selectedOtherType != nil
        if hasContent {
            removeSlotIndex = index
            showRemoveConfirm = true
        } else {
            removeSlot(at: index)
        }
    }

    private func removeSlot(at index: Int) {
        guard slots.indices.contains(index), !slots[index].isInviteGenerated, slots.count > 1 else { return }
        focusedNameField = nil
        slots.remove(at: index)
    }

    private func handleFinish() {
        guard anyInviteGenerated, let unfilledIndex = firstUnfilledIndex else {
            navigateToComplete = true
            return
        }
        let name = slots[unfilledIndex].firstName.trimmingCharacters(in: .whitespaces)
        skipAlertSlotName = name.isEmpty ? inviteCardTitle(for: unfilledIndex) : name
        skipAlertSlotIndex = unfilledIndex
        showSkipAlert = true
    }

    private func generateInviteForSlot(at index: Int) async {
        let slot = slots[index]
        guard slot.selectedRelationship != nil,
              let onboardingType = slot.selectedOnboardingType,
              !slot.firstName.trimmingCharacters(in: .whitespaces).isEmpty,
              !slot.effectiveRelationshipRawValue.isEmpty
        else { return }

        generatingSlotIndex = index
        showError = false
        errorMessage = ""

        do {
            let guidedStatus: GuidedSetupStatus? = onboardingType == .guided ? .pendingAcceptance : nil
            let (inviteCode, _) = try await dataManager.saveFamilyMemberInviteWithId(
                firstName: slot.firstName.trimmingCharacters(in: .whitespaces),
                relationship: slot.effectiveRelationshipRawValue,
                onboardingType: onboardingType.rawValue,
                guidedSetupStatus: guidedStatus
            )
            slots[index].inviteCode = inviteCode

            if !isPresentedFromDashboard {
                onboardingManager.invitedMembers.append(InvitedFamilyMember(
                    firstName: slot.firstName.trimmingCharacters(in: .whitespaces),
                    relationship: slot.effectiveRelationshipRawValue,
                    onboardingType: onboardingType.rawValue,
                    inviteCode: inviteCode
                ))
            }
            currentInviteName = slot.firstName
            currentInviteCode = inviteCode
            showInviteSheet = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        generatingSlotIndex = nil
    }

    private func loadExistingInvites() async {
        guard let familyId = dataManager.currentFamilyId else {
            print("⚠️ FamilyMembersInviteView: currentFamilyId is nil")
            initializeEmptySlots()
            return
        }

        do {
            let records = try await dataManager.fetchPendingFamilyInvites(familyId: familyId)
            let mapped: [MemberSlot] = records.compactMap { rec in
                guard let relStr = rec.relationship,
                      let onboardingStr = rec.onboardingType,
                      let onboarding = MemberOnboardingType(rawValue: onboardingStr),
                      let code = rec.inviteCode else { return nil }

                // Try to resolve the stored relationship string back to our enum cases.
                // Sub-type values (e.g. "Friend", "Family Friend") are not MemberRelationship cases,
                // so we fall back to MemberRelationshipOtherType and reconstruct .other + subType.
                var resolvedRelationship: MemberRelationship?
                var resolvedOtherType: MemberRelationshipOtherType?
                if let rel = MemberRelationship(rawValue: relStr) {
                    resolvedRelationship = rel
                } else if let sub = MemberRelationshipOtherType(rawValue: relStr) {
                    resolvedRelationship = .other
                    resolvedOtherType = sub
                } else {
                    return nil  // unknown value — safe to drop
                }

                var slot = MemberSlot()
                slot.firstName = rec.firstName
                slot.selectedRelationship = resolvedRelationship
                slot.selectedOtherType = resolvedOtherType
                slot.selectedOnboardingType = onboarding
                slot.inviteCode = code
                return slot
            }

            let target = onboardingManager.additionalFamilyMembersTarget > 0
                ? max(onboardingManager.additionalFamilyMembersTarget, mapped.count)
                : max(3, mapped.count)
            var newSlots = mapped
            while newSlots.count < target { newSlots.append(MemberSlot()) }
            slots = newSlots

            if !isPresentedFromDashboard {
                onboardingManager.invitedMembers = mapped.map {
                    InvitedFamilyMember(firstName: $0.firstName,
                                        relationship: $0.effectiveRelationshipRawValue,
                                        onboardingType: $0.selectedOnboardingType?.rawValue ?? "",
                                        inviteCode: $0.inviteCode ?? "")
                }
            }
            print("✅ FamilyMembersInviteView: \(mapped.count) existing invites, \(slots.count) total slots")
        } catch {
            print("❌ FamilyMembersInviteView: \(error.localizedDescription)")
            initializeEmptySlots()
        }
    }

    private func initializeEmptySlots() {
        let count = onboardingManager.additionalFamilyMembersTarget > 0
            ? onboardingManager.additionalFamilyMembersTarget : 3
        slots = (0..<count).map { _ in MemberSlot() }
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let name: String
    let code: String
    let onDone: () -> Void
    
    @State private var showMessageComposer = false
    @State private var showShareSheet = false
    @State private var unavailableAlert: InviteShareAlertType? = nil

    private var inviteMessage: String {
        "Join my family on Miya Health. Use this invite code: \(code). Download Miya Health from the App Store, then enter the code to join."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 6) {
                    Text("Invite sent to \(name)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                        .multilineTextAlignment(.center)
                    Text("It's as easy as 1-2-3")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)

                // Code block
                VStack(spacing: 6) {
                    Text(code)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.miyaPrimary)
                    Text("Share this code with \(name)")
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                )

                // 1-2-3 steps
                VStack(alignment: .leading, spacing: 14) {
                    InviteStep(number: "1", text: "Send \(name) this code")
                    InviteStep(number: "2", text: "They download Miya and enter it")
                    InviteStep(number: "3", text: "They set up their profile — you'll be notified when they join")
                }
                .padding(.horizontal, 28)

                // Share actions
                VStack(spacing: 12) {
                    Button {
                        sendTextInvite()
                    } label: {
                        HStack {
                            Image(systemName: "message.fill")
                            Text("Text")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.miyaPrimary.opacity(0.08))
                        .foregroundColor(.miyaPrimary)
                        .cornerRadius(14)
                    }
                    
                    Button {
                        sendWhatsAppInvite()
                    } label: {
                        HStack {
                            Image(systemName: "message.circle.fill")
                            Text("WhatsApp")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.miyaPrimary.opacity(0.08))
                        .foregroundColor(.miyaPrimary)
                        .cornerRadius(14)
                    }
                    
                    Button {
                        showShareSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share invite")
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
                    onDone()
                    dismiss()
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
        .sheet(isPresented: $showMessageComposer) {
            MessageComposerView(body: inviteMessage)
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityShareSheet(activityItems: [inviteMessage])
        }
        .alert(item: $unavailableAlert) { alertType in
            Alert(
                title: Text(alertType.title),
                message: Text(alertType.message),
                primaryButton: .default(Text("Share another way")) {
                    showShareSheet = true
                },
                secondaryButton: .cancel(Text("Not now"))
            )
        }
    }
    
    private func sendTextInvite() {
        guard MFMessageComposeViewController.canSendText() else {
            unavailableAlert = .textUnavailable
            return
        }
        showMessageComposer = true
    }
    
    private func sendWhatsAppInvite() {
        let encoded = inviteMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "whatsapp://send?text=\(encoded)") else {
            unavailableAlert = .whatsAppUnavailable
            return
        }
        
        openURL(url) { accepted in
            if !accepted {
                unavailableAlert = .whatsAppUnavailable
            }
        }
    }
}

/// A single numbered step row used inside InviteCodeSheet.
private struct InviteStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.miyaPrimary)
                .frame(width: 22, height: 22)
                .background(Color.miyaPrimary.opacity(0.1))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.miyaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum InviteShareAlertType: String, Identifiable {
    case textUnavailable
    case whatsAppUnavailable
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .textUnavailable:
            return "Text isn't available"
        case .whatsAppUnavailable:
            return "WhatsApp isn't available"
        }
    }
    
    var message: String {
        switch self {
        case .textUnavailable:
            return "This device can't send text messages right now. You can still share the invite using another option."
        case .whatsAppUnavailable:
            return "WhatsApp isn't installed on this device. You can still share the invite using another option."
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

private struct MessageComposerView: UIViewControllerRepresentable {
    let body: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.body = body
        composer.messageComposeDelegate = context.coordinator
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) { }
    
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
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
                
                Text("Set up \(memberName)’s profile")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.miyaTextPrimary)
                
                Text("You’re creating their health profile for them. When would you like to fill it in?")
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
                    
                    Text("Family profiles to complete")
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
                        Text("No family members waiting for you to finish their profile.")
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
                
                Text("Your family member chose to set up your profile for you—they’ll walk through the same health questions you would, on your behalf.")
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
                            Text("Yes, set it up for me")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text("They’ll create your profile for you")
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
                            Text("I’ll set it up myself")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            Text("We’ll send you through the same steps on your phone")
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
                            reviewRow("Biological sex", value: data.aboutYou.gender)
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
            
            ScrollView {
                VStack(spacing: 24) {
                    // Progress header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button(action: { hideKeyboard(); handleBack() }) {
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
                        Text("Health profile for \(memberName)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.miyaTextPrimary)
                        Text(stepSubtitle)
                            .font(.system(size: 15))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Step content
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
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OnboardingCTABar(
                    onContinue: { hideKeyboard(); handleContinue() },
                    continueLabel: currentStep == totalSteps ? "Save" : "Continue",
                    continueLoading: isLoading,
                    continueDisabled: !canContinue,
                    showError: showError,
                    errorMessage: errorMessage
                )
            }
        }
        .navigationBarHidden(true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
                    .font(.system(size: 17, weight: .semibold))
            }
        }
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
            // Biological sex
            VStack(alignment: .leading, spacing: 8) {
                Text("Biological sex")
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
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Ethnicity.allCases) { ethnicity in
                        Button {
                            selectedEthnicity = ethnicity
                        } label: {
                            HStack {
                                Text(ethnicity.rawValue)
                                    .font(.system(size: 13))
                                    .foregroundColor(.miyaTextPrimary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if selectedEthnicity == ethnicity {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12))
                                        .foregroundColor(.miyaPrimary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(selectedEthnicity == ethnicity ? Color.miyaPrimary.opacity(0.1) : Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedEthnicity == ethnicity ? Color.miyaPrimary : Color.miyaBackground.opacity(0.8), lineWidth: 1)
                            )
                        }
                    }
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
    @Environment(\.onboardingBackBehavior) private var onboardingBackBehavior
    @Environment(\.onboardingResumeStepBack) private var onboardingResumeStepBack
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    let membersCount: Int
    
    @State private var navigateToLanding: Bool = false
    
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
                        navigateToLanding = true
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
                        OnboardingBackAction.perform(
                            behavior: onboardingBackBehavior,
                            resumeStepBack: onboardingResumeStepBack,
                            dismiss: dismiss,
                            hideKeyboardFirst: false
                        )
                    } label: {
                        Text("Back")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.miyaTextSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            
            // Route through LandingView so paywall logic is never bypassed.
            NavigationLink(
                destination: LandingView()
                    .environmentObject(onboardingManager)
                    .environmentObject(dataManager)
                    .environmentObject(authManager)
                    .environmentObject(subscriptionManager),
                isActive: $navigateToLanding
            ) {
                EmptyView()
            }
            .hidden()
        }
        .onAppear {
            // For the standard Get Started (non-invited) superadmin path, eagerly mark
            // isSuperAdmin so LandingView routes correctly without waiting for the DB round-trip.
            // This also sets the fresh-flag so ContentView shows the paywall immediately
            // without blocking on the StoreKit entitlement check.
            if !onboardingManager.isInvitedUser {
                onboardingManager.isSuperAdmin = true
                onboardingManager.freshlyCompletedGetStarted = true
            }
            onboardingManager.completeOnboarding()
            print("✅ OnboardingCompleteView: Onboarding marked as complete (superadmin=\(!onboardingManager.isInvitedUser), freshlyCompletedGetStarted=\(onboardingManager.freshlyCompletedGetStarted))")
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
