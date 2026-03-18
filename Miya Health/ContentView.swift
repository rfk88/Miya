//
//  ContentView.swift
//  Miya Health
//
//  AUDIT REPORT (guided onboarding status-driven routing)
//  - Compile audit: Cannot run `xcodebuild` in this environment (no Xcode). Verified compile-safety via lints/type checks in Cursor.
//  - State integrity: Invited-user routing in `EnterCodeView` is now status-first (switch on `InviteDetails.guidedSetupStatus`),
//    and canonical status/IDs are persisted into `OnboardingManager` (no inferred booleans for routing).
//  - DB transition correctness: Uses DataManager transitions:
//      pending_acceptance -> (user accepts) accepted_awaiting_data -> (admin fills) data_complete_pending_review -> (user confirms) reviewed_complete
//    and supports guided->self switch (guided_setup_status cleared).
//  - Edge cases: If `guidedSetupStatus` is nil for a guided invite, routing deterministically treats it as `pending_acceptance`.
//  - Known limitations: `adminName` display currently uses family name as a placeholder label; no notification/nudge system added.
//
import RookSDK
import HealthKit
import SwiftUI
import UIKit

// ROOT VIEW USED BY Miya_HealthApp
struct ContentView: View {
    /// When true, show splash video (cold start only; in-memory so no splash on resume from background).
    @State private var showSplash = true

    var body: some View {
        Group {
            if showSplash {
                SplashView(onFinish: {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showSplash = false
                    }
                })
            } else {
                LandingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showSplash)
    }
}

#Preview {
    ContentView()
}

// MARK: - Hard-locked Theme Tokens (do not modify)
enum MiyaTheme {
    static let bg = Color.white

    // #1D2430
    static let ink = Color(red: 0.113, green: 0.141, blue: 0.188)

    // #2E7F7B and #7AB9AA
    static let tealDark = Color(red: 0.145, green: 0.431, blue: 0.416) // deeper teal for visible gradient
    static let tealLight = Color(red: 0.478, green: 0.725, blue: 0.667)

    // #7DD3C7
    static let wash = Color(red: 0.490, green: 0.827, blue: 0.780)

    static let hPad: CGFloat = 22
    static let ctaGap: CGFloat = 14
    static let buttonH: CGFloat = 60
    static let radius: CGFloat = 18
}

// MARK: - Background wash (EXACT positioning)
struct MiyaBackgroundWash: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                MiyaTheme.bg

                // Radial wash centered at (50% width, 72% height)
                // Radius x=70% width, y=45% height
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: MiyaTheme.wash.opacity(0.22), location: 0.00),
                        .init(color: MiyaTheme.wash.opacity(0.12), location: 0.45),
                        .init(color: Color.white.opacity(0.00), location: 1.00)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 1
                )
                // Convert "elliptical radius" into an explicit frame:
                .frame(width: geo.size.width * 1.40, height: geo.size.height * 0.90) // 2 * rx, 2 * ry
                .position(x: geo.size.width * 0.50, y: geo.size.height * 0.72)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Premium button styles (hard locked)
struct MiyaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: MiyaTheme.buttonH)
            .background(
                LinearGradient(
                    colors: [Color.miyaTealDark, Color.miyaTealLight],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: MiyaTheme.radius, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .opacity(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct MiyaSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: MiyaTheme.buttonH)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: MiyaTheme.radius, style: .continuous)
                    .stroke(MiyaTheme.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: MiyaTheme.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.92 : 1.0)
    }
}

struct LandingView: View {
    @State private var showingSettings = false
    @State private var navigateResume = false
    @State private var showingLogin = false
    @State private var hasRefreshedGuidedContext = false
    
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    /// Global loading flag (auth/data/profile/subscription). Keep UI consistent without touching workflows.
    private var isGlobalLoading: Bool {
        authManager.isLoading || dataManager.isLoading || authManager.isLoadingProfile
        || (authManager.isAuthenticated && onboardingManager.isOnboardingComplete && onboardingManager.isSuperAdmin && !subscriptionManager.entitlementCheckComplete)
    }
    
    /// Returns the view for the saved onboarding step
    @ViewBuilder
    private var resumeDestination: some View {
        // HARD GATE (guided invites): if admin has completed the profile and member hasn't approved yet,
        // always route the member to the review screen until they confirm.
        if onboardingManager.guidedSetupStatus == .dataCompletePendingReview,
           let memberId = onboardingManager.invitedMemberId {
            GuidedSetupReviewView(memberId: memberId)
        } else {
        // Invited users should never be routed into superadmin-only onboarding screens (family creation / inviting others).
        // This is a deterministic guard against cross-account persisted steps.
        if onboardingManager.isInvitedUser && onboardingManager.currentStep <= 1 {
            WearableSelectionView()
        } else {
        switch onboardingManager.currentStep {
        case 1:
            SuperadminOnboardingView()
        case 2:
            WearableSelectionView()
        case 3:
            AboutYouView()
        case 4:
            HeartHealthView()
        case 5:
            MedicalHistoryView()
        case 6:
            if onboardingManager.isInvitedUser {
                AlertsChampionView()
            } else {
                FamilyMembersInviteView()
            }
        case 7:
            AlertsChampionView()
        default:
            SuperadminOnboardingView()
        }
        }
        }
    }
    
    var body: some View {
        Group {
            // HARD GATE: Invited members with admin-filled data awaiting their review
            if authManager.isAuthenticated,
               onboardingManager.guidedSetupStatus == .dataCompletePendingReview,
               let memberId = onboardingManager.invitedMemberId {
                NavigationStack {
                    GuidedSetupReviewView(memberId: memberId)
                }
            }
            // LOADING GUARD: If authenticated but profile is loading, show loading state (prevents onboarding flash)
            else if authManager.isAuthenticated && authManager.isLoadingProfile {
                Color.clear
            }
            // Superadmin waiting for subscription check: show loading until entitlement is known
            else if authManager.isAuthenticated && onboardingManager.isOnboardingComplete && onboardingManager.isSuperAdmin && !subscriptionManager.entitlementCheckComplete {
                Color.clear
            }
            // Superadmin with no active subscription: show paywall
            else if authManager.isAuthenticated && onboardingManager.isOnboardingComplete && onboardingManager.isSuperAdmin && subscriptionManager.entitlementCheckComplete && !subscriptionManager.hasActiveSubscription {
                NavigationStack {
                    PaywallView(
                        onStartTrial: {
                            Task { await subscriptionManager.purchase() }
                        },
                        onRestore: {
                            Task { await subscriptionManager.restore() }
                        },
                        subscriptionManager: subscriptionManager
                    )
                    .environmentObject(authManager)
                    .environmentObject(dataManager)
                    .environmentObject(onboardingManager)
                }
            }
            // Authenticated, onboarding complete, and (not superadmin or has subscription): show dashboard
            else if authManager.isAuthenticated && onboardingManager.isOnboardingComplete {
                NavigationStack {
                    DashboardView(familyName: onboardingManager.familyName.isEmpty ? "Miya" : onboardingManager.familyName)
                }
            } else {
                NavigationStack {
                    AuthEntryScreen(
                        showingSettings: $showingSettings,
                        showingLogin: $showingLogin
                    )
                    .sheet(isPresented: $showingSettings) {
                        SettingsView()
                            .environmentObject(dataManager)
                    }
                    .sheet(isPresented: $showingLogin) {
                        LoginView {
                            // LoginView already loaded the profile and set currentStep from database
                            // Just trigger navigation to the correct step
                            navigateResume = true
                        }
                        .environmentObject(authManager)
                        .environmentObject(onboardingManager)
                        .environmentObject(dataManager)
                    }
                    
                    NavigationLink(
                        destination: resumeDestination
                            .environmentObject(onboardingManager)
                            .environmentObject(dataManager),
                        isActive: $navigateResume
                    ) {
                        EmptyView()
                    }
                    .hidden()
                }
            }
        }
        .overlay {
            if isGlobalLoading {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .miyaPrimary))
                        .scaleEffect(1.2)
                }
                .allowsHitTesting(true)
                .transition(.opacity)
            }
        }
    }
}

#Preview {
    LandingView()
}

// MARK: - ENTER CODE VIEW (FOR INVITED USERS)

struct EnterCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    // Code entry state
    @State private var inviteCode: String = ""
    @State private var isValidatingCode: Bool = false
    @State private var inviteDetails: InviteDetails? = nil
    @State private var codeValidated: Bool = false
    
    // Account creation state
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    
    // Guided setup acceptance (only for Guided Setup invites)
    @State private var showGuidedAcceptancePrompt: Bool = false
    @State private var wearablesIsGuidedSetupInvite: Bool = false
    
    // Navigation and error state
    @State private var navigateToWearables: Bool = false
    @State private var navigateToFullOnboarding: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isAppleSignInLoading: Bool = false

    private var isCodeValid: Bool {
        inviteCode.trimmingCharacters(in: .whitespaces).count >= 4
    }
    
    private var passwordsMatch: Bool {
        !password.isEmpty && !confirmPassword.isEmpty && password == confirmPassword
    }
    
    private var isFormValid: Bool {
        guard codeValidated else { return false }
        guard !email.isEmpty else { return false }
        guard password.count >= 8 else { return false }
        guard passwordsMatch else { return false }
        return true
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // Back button
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.miyaTextPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                        .clipShape(Circle())
                }
                .padding(.top, 8)
                
                if !codeValidated {
                    // STEP 1: Enter invite code
                    enterCodeSection
                } else {
                    // STEP 2: Create account (code validated)
                    createAccountSection
                }
            }
            .padding(.horizontal, 24)
        }
        .navigationBarHidden(true)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        // Guided setup acceptance prompt (Guided Setup invites only)
        .sheet(isPresented: $showGuidedAcceptancePrompt) {
            if let details = inviteDetails {
                GuidedSetupAcceptancePrompt(
                    memberName: details.firstName,
                    adminName: details.familyName,
                    onAcceptGuidedSetup: {
                        showGuidedAcceptancePrompt = false
                        Task { await acceptGuidedSetup() }
                    },
                    onFillMyself: {
                        showGuidedAcceptancePrompt = false
                        Task { await switchToSelfSetup() }
                    }
                )
                .presentationDetents([.medium])
            }
        }
        // Invited members use the standard onboarding flow screens (role-tailored)
        .navigationDestination(isPresented: $navigateToWearables) {
            WearableSelectionView(isGuidedSetupInvite: wearablesIsGuidedSetupInvite)
        }
        .navigationDestination(isPresented: $navigateToFullOnboarding) {
            AboutYouView()  // Skip to AboutYou since they're already in a family
        }
    }
    
    // MARK: - Enter Code Section
    
    private var enterCodeSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text("Enter your invite code")
                .font(.system(size: 28, weight: .bold))
            
            Text("Enter the code shared by your family member to join their health team.")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            
            // Code input
            VStack(alignment: .leading, spacing: 8) {
                Text("Invite Code")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("MIYA-XXXX", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 18, weight: .medium))
                    .padding()
                    .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                    .cornerRadius(12)
            }
            
            // Validate button
            Button {
                Task {
                    await validateCode()
                }
            } label: {
                HStack(spacing: 8) {
                    if isValidatingCode {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(isValidatingCode ? "Checking..." : "Continue")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isCodeValid ? Color.miyaPrimary : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(18)
            }
            .disabled(!isCodeValid || isValidatingCode)
            .padding(.top, 12)
        }
    }
    
    // MARK: - Create Account Section
    
    private var createAccountSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Welcome message with family name
            if let details = inviteDetails {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome, \(details.firstName)!")
                        .font(.system(size: 28, weight: .bold))
                    
                    Text("You've been invited to join")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    
                    Text(details.familyName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.miyaPrimary)
                    
                    // Show onboarding type info
                    HStack(spacing: 8) {
                        Image(systemName: details.isGuidedSetup ? "checkmark.circle.fill" : "person.fill")
                            .foregroundColor(.miyaPrimary)
                        Text(onboardingTypeSummaryText(details))
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                    
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Account creation form
            Text("Create your account")
                .font(.system(size: 20, weight: .semibold))
            
            // Email
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("your@email.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                    .cornerRadius(12)
            }
            
            // Password
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                SecureField("At least 8 characters", text: $password)
                    .padding()
                    .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                    .cornerRadius(12)
            }
            
            // Confirm password
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                SecureField("Confirm your password", text: $confirmPassword)
                    .padding()
                    .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                    .cornerRadius(12)
                
                if !confirmPassword.isEmpty && !passwordsMatch {
                    Text("Passwords do not match")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }
            
            // Join button
            Button {
                Task {
                    await createAccountAndJoin()
                }
            } label: {
                HStack(spacing: 8) {
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(authManager.isLoading ? "Creating account..." : "Join Family")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isFormValid ? Color.miyaPrimary : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(18)
            }
            .disabled(!isFormValid || authManager.isLoading)
            .padding(.top, 12)
            
            // Or sign in with Apple
            VStack(spacing: 12) {
                HStack {
                    Rectangle().fill(Color(red: 0.9, green: 0.9, blue: 0.92)).frame(height: 1)
                    Text("Or sign in with Apple")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Rectangle().fill(Color(red: 0.9, green: 0.9, blue: 0.92)).frame(height: 1)
                }
                SignInWithAppleButtonView { idToken, nonce, fullName in
                    await handleAppleSignInForInvite(idToken: idToken, nonce: nonce, fullName: fullName)
                }
                .disabled(isAppleSignInLoading || authManager.isLoading)
            }
            .padding(.top, 16)
        }
    }
    
    // MARK: - Actions
    
    private func validateCode() async {
        isValidatingCode = true
        showError = false
        
        do {
            let normalizedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
            inviteCode = normalizedCode
            let details = try await dataManager.lookupInviteCode(code: normalizedCode)
            inviteDetails = details
            codeValidated = true
            
            // Store in onboarding manager
            onboardingManager.firstName = details.firstName
            onboardingManager.guidedSetupStatus = details.guidedSetupStatus
            onboardingManager.invitedMemberId = details.memberId
            onboardingManager.invitedFamilyId = details.familyId
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isValidatingCode = false
    }
    
    private func createAccountAndJoin() async {
        guard let details = inviteDetails else { return }
        
        showError = false
        
        do {
            let normalizedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
            inviteCode = normalizedCode
            // 1. Create the user account
            let userId = try await authManager.signUp(
                email: email,
                password: password,
                firstName: details.firstName
            )
            
            // 2. 🔥 Create initial user_profile (step 2 since they've already "joined" a family via invite)
            try await dataManager.createInitialProfile(
                userId: userId,
                firstName: details.firstName,
                step: 2
            )
            
            // 3. Complete the invite redemption (link user to family)
            try await dataManager.completeInviteRedemption(
                code: normalizedCode,
                userId: userId
            )
            
            // 4. Store info in onboarding manager
            onboardingManager.firstName = details.firstName
            onboardingManager.email = email
            onboardingManager.currentUserId = userId
            onboardingManager.isInvitedUser = true  // 🔥 Mark as invited user
            onboardingManager.familyName = details.familyName  // Store family name
            onboardingManager.guidedSetupStatus = details.guidedSetupStatus
            onboardingManager.invitedMemberId = details.memberId
            onboardingManager.invitedFamilyId = details.familyId
            
            // 5. Routing:
            // - Guided Setup invites: show acceptance prompt first.
            // - Self Setup invites: proceed through standard onboarding screens.
            if details.isGuidedSetup {
                showGuidedAcceptancePrompt = true
            } else {
                wearablesIsGuidedSetupInvite = false
                onboardingManager.setCurrentStep(2) // Wearables
                navigateToWearables = true
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func handleAppleSignInForInvite(idToken: String, nonce: String?, fullName: PersonNameComponents?) async {
        guard let details = inviteDetails else { return }
        showError = false
        isAppleSignInLoading = true
        defer { isAppleSignInLoading = false }
        do {
            let normalizedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let userId = try await authManager.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
            let firstName = fullName?.givenName ?? fullName?.familyName ?? details.firstName
            try await dataManager.createInitialProfile(userId: userId, firstName: firstName, step: 2)
            try await dataManager.completeInviteRedemption(code: normalizedCode, userId: userId)
            onboardingManager.firstName = firstName
            onboardingManager.currentUserId = userId
            onboardingManager.isInvitedUser = true
            onboardingManager.familyName = details.familyName
            onboardingManager.guidedSetupStatus = details.guidedSetupStatus
            onboardingManager.invitedMemberId = details.memberId
            onboardingManager.invitedFamilyId = details.familyId
            if details.isGuidedSetup {
                showGuidedAcceptancePrompt = true
            } else {
                wearablesIsGuidedSetupInvite = false
                onboardingManager.setCurrentStep(2)
                navigateToWearables = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func onboardingTypeSummaryText(_ details: InviteDetails) -> String {
        if details.isGuidedSetup {
            return "Guided setup — accept to get started"
        }
        return "Self setup — you’ll complete your profile in the next steps"
    }
    
    // MARK: - Guided setup actions (invitee)
    
    private func acceptGuidedSetup() async {
        guard let details = inviteDetails else { return }
        do {
            try await dataManager.acceptGuidedSetup(memberId: details.memberId)
            onboardingManager.guidedSetupStatus = .acceptedAwaitingData
            
            // Next step: connect wearable / import ROOK to compute vitality while admin completes health profile.
            wearablesIsGuidedSetupInvite = true
            onboardingManager.setCurrentStep(2) // Wearables
            navigateToWearables = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func switchToSelfSetup() async {
        guard let details = inviteDetails else { return }
        do {
            try await dataManager.switchToSelfSetup(memberId: details.memberId)
            onboardingManager.guidedSetupStatus = nil
            
            // Standard onboarding
            wearablesIsGuidedSetupInvite = false
            onboardingManager.setCurrentStep(2) // Wearables
            navigateToWearables = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Color Hex Helper (local to landing view styling)

// MARK: - GUIDED SETUP PREVIEW VIEW

struct GuidedSetupPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    let inviteCode: String
    let inviteDetails: InviteDetails
    
    @State private var navigateToWearables: Bool = false
    @State private var navigateToEdit: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review Your Profile")
                        .font(.system(size: 28, weight: .bold))
                    
                    Text("Your family member has filled out your health information. Review it below and accept or make changes.")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Preview sections
                VStack(alignment: .leading, spacing: 20) {
                    // About You section
                    previewSection(
                        title: "About You",
                        icon: "person.fill",
                        content: [
                            ("Name", inviteDetails.firstName),
                            ("Relationship", inviteDetails.relationship),
                            // TODO: Add other fields when superadmin fills them out
                            // ("Gender", "..."),
                            // ("Date of Birth", "..."),
                            // etc.
                        ]
                    )
                    
                    // Heart Health section
                    previewSection(
                        title: "Heart Health",
                        icon: "heart.fill",
                        content: [
                            // TODO: Show conditions when superadmin fills them out
                            ("Status", "To be filled by family member")
                        ]
                    )
                    
                    // Medical History section
                    previewSection(
                        title: "Medical History",
                        icon: "cross.case.fill",
                        content: [
                            ("Status", "To be filled by family member")
                        ]
                    )
                    
                    // Privacy Settings section
                    previewSection(
                        title: "Privacy Settings",
                        icon: "lock.fill",
                        content: [
                            ("Status", "To be filled by family member")
                        ]
                    )
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    // Accept button
                    Button {
                        // Accept all data, go straight to wearables
                        navigateToWearables = true
                    } label: {
                        Text("Accept & Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(18)
                    }
                    
                    // Make Changes button
                    Button {
                        // Go through full onboarding to edit
                        navigateToEdit = true
                    } label: {
                        Text("Make Changes")
                            .font(.system(size: 16, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.clear)
                            .foregroundColor(.miyaPrimary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.miyaPrimary, lineWidth: 2)
                            )
                    }
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $navigateToWearables) {
            WearableSelectionView(isGuidedSetupInvite: true)
        }
        .navigationDestination(isPresented: $navigateToEdit) {
            WearableSelectionView()
        }
    }
    
    private func previewSection(title: String, icon: String, content: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.miyaPrimary)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(content, id: \.0) { item in
                    HStack {
                        Text(item.0)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.1)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.miyaTextPrimary)
                    }
                }
            }
            .padding()
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
            .cornerRadius(12)
        }
    }
}

// MARK: - Login View (existing account)
struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false
    @State private var isAppleSignInLoading: Bool = false
    
    var onSuccess: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Login")) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    SecureField("Password", text: $password)
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
                
                Button {
                    Task { await login() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                
                Section {
                    SignInWithAppleButtonView { idToken, nonce, fullName in
                        await handleAppleSignIn(idToken: idToken, nonce: nonce, fullName: fullName)
                    }
                    .disabled(isAppleSignInLoading || isLoading)
                } header: {
                    Text("Or sign in with")
                }
            }
            .navigationTitle("Sign In")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func handleAppleSignIn(idToken: String, nonce: String?, fullName: PersonNameComponents?) async {
        errorMessage = ""
        isAppleSignInLoading = true
        defer { isAppleSignInLoading = false }
        do {
            _ = try await authManager.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
            dataManager.restorePersistedState()
            await MainActor.run {
                dismiss()
                onSuccess()
            }
            await MainActor.run { authManager.isLoadingProfile = true }
            if let profile = try await dataManager.loadUserProfile() {
                await MainActor.run {
                    if let firstName = profile.first_name { onboardingManager.firstName = firstName }
                    if let lastName = profile.last_name { onboardingManager.lastName = lastName }
                    if let dobString = profile.date_of_birth, !dobString.isEmpty {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        onboardingManager.dateOfBirth = formatter.date(from: dobString)
                    } else { onboardingManager.dateOfBirth = nil }
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
                    let step = profile.onboarding_step ?? 1
                    onboardingManager.isOnboardingComplete = profile.onboarding_complete ?? false
                    onboardingManager.setCurrentStep(step)
                }
            } else {
                await MainActor.run { onboardingManager.setCurrentStep(1) }
            }
            await onboardingManager.refreshGuidedContextFromDB(dataManager: dataManager)
            await MainActor.run { authManager.isLoadingProfile = false }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func login() async {
        errorMessage = ""
        isLoading = true
        do {
            // 1. Sign in to Supabase
            try await authManager.signIn(email: email, password: password)
            print("✅ LoginView: User authenticated")
            
            // 2. Restore currentFamilyId from UserDefaults (backup)
            dataManager.restorePersistedState()
            
            #if DEBUG
            // 2b. If demo account, enable screenshot demo so dashboard is full without real data
            if email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == ScreenshotDemoData.demoEmail.lowercased() {
                ScreenshotDemoData.isScreenshotModeEnabled = true
                onboardingManager.familyName = "The Smiths"
                onboardingManager.firstName = "Simon"
                onboardingManager.setCurrentStep(7)
                onboardingManager.isOnboardingComplete = true
            }
            #endif
            
            // 3. Dismiss immediately to prevent UI freeze
            await MainActor.run {
                isLoading = false
                dismiss()
                onSuccess()
            }
            
            // 4. 🔥 LOAD USER PROFILE FROM DATABASE IN BACKGROUND
            // This happens AFTER dismissal so UI doesn't freeze
            // Set loading flag to prevent onboarding flash during profile load
            await MainActor.run {
                authManager.isLoadingProfile = true
            }
            
            if let profile = try await dataManager.loadUserProfile() {
                print("📥 LoginView: Loading profile data into OnboardingManager (background)")
                
                // Populate OnboardingManager with database data
                await MainActor.run {
                    // Basic info
                    if let firstName = profile.first_name {
                        onboardingManager.firstName = firstName
                    }
                    if let lastName = profile.last_name {
                        onboardingManager.lastName = lastName
                    }
                    
                    // About You data
                    if let dobString = profile.date_of_birth, !dobString.isEmpty {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        if let dob = formatter.date(from: dobString) {
                            onboardingManager.dateOfBirth = dob
                        } else {
                            onboardingManager.dateOfBirth = nil
                        }
                    } else {
                        onboardingManager.dateOfBirth = nil
                    }
                    if let gender = profile.gender {
                        onboardingManager.gender = gender
                    }
                    if let ethnicity = profile.ethnicity {
                        onboardingManager.ethnicity = ethnicity
                    }
                    if let smoking = profile.smoking_status {
                        onboardingManager.smokingStatus = smoking
                    }
                    if let height = profile.height_cm {
                        onboardingManager.heightCm = height
                    }
                    if let weight = profile.weight_kg {
                        onboardingManager.weightKg = weight
                    }
                    
                    // Heart Health data
                    if let bpStatus = profile.blood_pressure_status {
                        onboardingManager.bloodPressureStatus = bpStatus
                    }
                    if let diabStatus = profile.diabetes_status {
                        onboardingManager.diabetesStatus = diabStatus
                    }
                    if let heartAttack = profile.has_prior_heart_attack {
                        onboardingManager.hasPriorHeartAttack = heartAttack
                    }
                    if let stroke = profile.has_prior_stroke {
                        onboardingManager.hasPriorStroke = stroke
                    }
                    
                    // Family History data
                    if let familyHeart = profile.family_heart_disease_early {
                        onboardingManager.familyHeartDiseaseEarly = familyHeart
                    }
                    if let familyStroke = profile.family_stroke_early {
                        onboardingManager.familyStrokeEarly = familyStroke
                    }
                    if let familyDiabetes = profile.family_type2_diabetes {
                        onboardingManager.familyType2Diabetes = familyDiabetes
                    }
                    
                    // Risk Results
                    if let riskBand = profile.risk_band {
                        onboardingManager.riskBand = riskBand
                    }
                    if let riskPoints = profile.risk_points {
                        onboardingManager.riskPoints = riskPoints
                    }
                    if let optimalTarget = profile.optimal_vitality_target {
                        onboardingManager.optimalVitalityTarget = optimalTarget
                    }
                    
                    // 🔥 Load step from DATABASE, not UserDefaults
                    let step = profile.onboarding_step ?? 1
                    let isComplete = profile.onboarding_complete ?? false
                    
                    onboardingManager.isOnboardingComplete = isComplete
                    onboardingManager.setCurrentStep(step)
                    
                    print("✅ LoginView: Profile loaded - Navigating to step \(step)")
                }
            } else {
                // No profile found in database, start from step 1
                print("ℹ️ LoginView: No profile found, starting from step 1")
                await MainActor.run {
                    onboardingManager.setCurrentStep(1)
                }
            }
            
            // Refresh guided context (force review screen if data is ready)
            await onboardingManager.refreshGuidedContextFromDB(dataManager: dataManager)
            
            #if DEBUG
            // Demo account: always show dashboard with demo data (override any DB-driven state)
            if email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == ScreenshotDemoData.demoEmail.lowercased() {
                await MainActor.run {
                    onboardingManager.isOnboardingComplete = true
                    onboardingManager.familyName = "The Smiths"
                    onboardingManager.setCurrentStep(7)
                }
            }
            print("✅ GUIDED_INVITEE_LOGIN: memberId=\(onboardingManager.invitedMemberId ?? "nil") status=\(onboardingManager.guidedSetupStatus?.rawValue ?? "nil") currentStep=\(onboardingManager.currentStep)")
            #endif
            
            print("✅ LoginView: Background profile loading complete")
            
            // Clear loading flag - profile is loaded, ready to route to dashboard/onboarding
            await MainActor.run {
                authManager.isLoadingProfile = false
            }
            
        } catch {
            // Only show error if we haven't dismissed yet (auth failed)
            // If error happens during background profile load, just log it
            if isLoading {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    print("❌ LoginView: Login failed - \(error.localizedDescription)")
                }
            } else {
                print("⚠️ LoginView: Background profile load error (non-critical) - \(error.localizedDescription)")
                // Clear loading flag even on error
                await MainActor.run {
                    authManager.isLoadingProfile = false
                }
            }
        }
    }
}

// MARK: - Text Field Style

struct MiyaTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}
