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
        .environmentObject(AuthManager())
        .environmentObject(DataManager())
        .environmentObject(OnboardingManager())
        .environmentObject(SubscriptionManager())
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

// MARK: - Cold start / profile restore (visible loading, not blank)

#if DEBUG
/// Logs routing-relevant state when the authenticated “Syncing your profile…” gate is visible (plan: profile sync hang diagnosis).
private func debugLogSyncingProfileGate(authManager: AuthManager, onboardingManager: OnboardingManager) {
    print("""
    📛 SyncingGate DEBUG | branch=LandingView authenticated-hydration-gate (ContentView)
      isAuthenticated=\(authManager.isAuthenticated)
      isLoadingProfile=\(authManager.isLoadingProfile)
      isHydrated=\(onboardingManager.isHydrated)
      needsLaunchRestoreRetry=\(authManager.needsLaunchRestoreRetry)
      currentStep=\(onboardingManager.currentStep) isOnboardingComplete=\(onboardingManager.isOnboardingComplete)
    Repro matrix (record which case hangs):
      • Fresh install → Get started → sign up
      • Same session → sign out → Get started → sign up (do not kill app)
      • Kill app after sign-out vs stay in app before next sign-up
      • Invite sign-up vs superadmin Get started; login sheet vs embedded sign-up
    """)
}
#endif

private struct StartupGateView: View {
    var message: String = "Loading your account…"

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var onboardingManager: OnboardingManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false
    @State private var showReassurance = false

    var body: some View {
        ZStack {
            MiyaBackgroundWash()
            VStack(spacing: 20) {
                Image("e96bc988831220de186601645fd93835b8dede817e5045c208d02c6fb54bd4c8")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulsing ? 1.08 : 0.95)
                    .opacity(pulsing ? 1.0 : 0.7)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: pulsing
                    )

                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MiyaTheme.ink.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if message == "Syncing your profile…" {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: MiyaTheme.ink.opacity(0.45)))
                        .scaleEffect(1.05)
                        .accessibilityLabel("Loading profile")
                }

                if showReassurance {
                    Text("This can take a moment on slower connections.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(MiyaTheme.ink.opacity(0.4))
                        .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading")
        .onAppear {
            pulsing = true
#if DEBUG
            if message == "Syncing your profile…" {
                debugLogSyncingProfileGate(authManager: authManager, onboardingManager: onboardingManager)
            }
#endif
        }
        .task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) {
                showReassurance = true
            }
        }
    }
}

// MARK: - Auto-resume onboarding back (mirrors `LandingView.resumeDestination`)

/// Previous step index for the single-push resume link, or `nil` when Back should return to auth entry.
fileprivate func previousResumeStep(for m: OnboardingManager) -> Int? {
    if m.guidedSetupStatus == .dataCompletePendingReview, m.invitedMemberId != nil {
        return nil
    }
    if m.isInvitedGuidedSetupMember, (3...5).contains(m.currentStep) {
        return nil
    }
    let step = m.currentStep
    let invited = m.isInvitedUser
    if invited && step <= 1 {
        return nil
    }
    switch step {
    case 1:
        return nil
    case 2:
        if invited { return nil }
        return 1
    case 3: return 2
    case 4: return 3
    case 5: return 4
    case 6: return 5
    case 7: return 6
    case 8: return 7
    default:
        return nil
    }
}

/// Wraps `resumeDestination` so Back decrements `currentStep` instead of popping to Get started.
private struct OnboardingResumeShell<Content: View>: View {
    @Binding var navigateResume: Bool
    @EnvironmentObject private var onboardingManager: OnboardingManager
    private let content: Content

    init(navigateResume: Binding<Bool>, @ViewBuilder content: () -> Content) {
        _navigateResume = navigateResume
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.onboardingBackBehavior, .resumeStep)
            .environment(\.onboardingResumeStepBack, { performResumeBack() })
    }

    private func performResumeBack() {
        if let prev = previousResumeStep(for: onboardingManager) {
            onboardingManager.setCurrentStep(prev)
        } else {
            navigateResume = false
        }
    }
}

struct LandingView: View {
    @State private var showingSettings = false
    @State private var navigateResume = false
    @State private var showingLogin = false
    @State private var hasRefreshedGuidedContext = false
    @State private var hasAutoResumed = false
    @State private var familyBillingState: DataManager.FamilyBillingState?
    @State private var isRefreshingBillingState = false
    @State private var billingActionError: String?
    
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    private var isSuperAdminPaywallFlow: Bool {
        authManager.isAuthenticated
            && onboardingManager.isOnboardingComplete
            && onboardingManager.isSuperAdmin
    }

    private var shouldShowSubscriptionLoader: Bool {
        // Never block a fresh Get Started completion: brand-new superadmins have no subscription.
        guard !onboardingManager.freshlyCompletedGetStarted else { return false }
        return isSuperAdminPaywallFlow && !subscriptionManager.entitlementCheckComplete
    }

    /// Verified StoreKit subscription dismisses the superadmin paywall (App Store 3.1.1: no non-IAP unlock).
    private var hasActiveSubscriptionAccess: Bool {
        subscriptionManager.hasActiveSubscription
    }

    private var shouldShowPaywall: Bool {
        guard isSuperAdminPaywallFlow else { return false }
        if hasActiveSubscriptionAccess { return false }
        // New account on any device = paywall, regardless of stale sandbox/device subscriptions.
        // Cleared after successful verified purchase.
        if onboardingManager.freshlyCompletedGetStarted { return true }
        // Returning user without subscription: show paywall once entitlement check finishes.
        return subscriptionManager.entitlementCheckComplete
    }
    
    private var shouldShowBillingRecovery: Bool {
        authManager.isAuthenticated
            && onboardingManager.isOnboardingComplete
            && familyBillingState?.billingStatus == "billing_required"
    }

    /// Global loading flag (auth/data/profile/subscription). Keep UI consistent without touching workflows.
    /// When the dashboard is already visible, skip this overlay — the dashboard handles its own
    /// section-level loading states. This prevents a dark spinner flash on every background refresh.
    private var isGlobalLoading: Bool {
        let onDashboard = authManager.isAuthenticated && onboardingManager.isOnboardingComplete
            && !shouldShowPaywall && !shouldShowBillingRecovery
        if onDashboard { return false }
        let profileLoadingBlocksChrome = authManager.hasFinishedInitialLaunchRouting && authManager.isLoadingProfile
        return authManager.isLoading || dataManager.isLoading || profileLoadingBlocksChrome
            || shouldShowSubscriptionLoader
    }
    
    /// Returns the view for the saved onboarding step
    @ViewBuilder
    private var resumeDestination: some View {
        // HARD GATE (guided invites): if admin has completed the profile and member hasn't approved yet,
        // always route the member to the review screen until they confirm.
        if onboardingManager.guidedSetupStatus == .dataCompletePendingReview,
           let memberId = onboardingManager.invitedMemberId {
            GuidedSetupReviewView(memberId: memberId)
        } else if onboardingManager.isInvitedGuidedSetupMember,
                  (3...5).contains(onboardingManager.currentStep) {
            // Safety net if step was not clamped yet: guided invitees never use self-serve health steps 3–5.
            WearableSelectionView(isGuidedSetupInvite: true)
        } else {
        // Invited users should never be routed into superadmin-only onboarding screens (family creation / inviting others).
        // This is a deterministic guard against cross-account persisted steps.
        if onboardingManager.isInvitedUser && onboardingManager.currentStep <= 1 {
            WearableSelectionView(isGuidedSetupInvite: onboardingManager.isInvitedGuidedSetupMember)
        } else {
        switch onboardingManager.currentStep {
        case 1:
            SuperadminOnboardingView()
        case 2:
            WearableSelectionView(isGuidedSetupInvite: onboardingManager.isInvitedUser && onboardingManager.isInvitedGuidedSetupMember)
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
        case 8:
            AdditionalFamilyMembersCountView()
        default:
            SuperadminOnboardingView()
        }
        }
        }
    }
    
    var body: some View {
        Group {
            // Until cold-start routing finishes, keep one gate (don’t use “Syncing profile” — that’s for explicit sign-in).
            if !authManager.hasFinishedInitialLaunchRouting {
                StartupGateView(
                    message: authManager.isAuthenticated
                        ? "Restoring your session…"
                        : "Loading your account…"
                )
            }
            // HARD GATE: Invited members with admin-filled data awaiting their review
            else if authManager.isAuthenticated,
               onboardingManager.guidedSetupStatus == .dataCompletePendingReview,
               let memberId = onboardingManager.invitedMemberId {
                NavigationStack {
                    GuidedSetupReviewView(memberId: memberId)
                }
            }
            // LOADING GUARD: Signed-in user but profile/onboarding not hydrated yet (e.g. Log In sheet path).
            else if authManager.isAuthenticated && !onboardingManager.isHydrated {
                StartupGateView(message: "Syncing your profile…")
            }
            // Superadmin waiting for subscription check: show loading until entitlement is known
            else if shouldShowSubscriptionLoader {
                StartupGateView(message: "Checking subscription…")
                    .task {
                        await subscriptionManager.loadProductsAndCheckEntitlements()
                    }
            }
            // Superadmin with no active subscription: show paywall
            else if shouldShowPaywall {
                NavigationStack {
                    PaywallView(
                        onStartTrial: {
                            Task {
                                await subscriptionManager.purchase()
                                // Consume the one-time fresh flag as soon as payment lands so
                                // shouldShowPaywall can re-evaluate without it holding the gate open.
                                if subscriptionManager.hasActiveSubscription {
                                    onboardingManager.freshlyCompletedGetStarted = false
#if DEBUG
                                    print("✅ PaywallGate purchase succeeded — freshFlag cleared, shouldShowPaywall=\(shouldShowPaywall)")
#endif
                                } else {
#if DEBUG
                                    print("⚠️ PaywallGate purchase attempt completed — hasActive=false error=\(subscriptionManager.purchaseError ?? "none")")
#endif
                                }
                            }
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
                .task {
                    // Always refresh products when the paywall is shown (fixes empty product / “Item Unavailable” after failed load).
                    await subscriptionManager.loadProductsAndCheckEntitlements()
                }
            }
            else if shouldShowBillingRecovery {
                NavigationStack {
                    BillingRecoveryView(
                        errorMessage: billingActionError,
                        isLoading: isRefreshingBillingState,
                        onTakeOverBilling: {
                            Task {
                                await claimFamilyBillingOwner()
                            }
                        }
                    )
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
                        destination: OnboardingResumeShell(navigateResume: $navigateResume) {
                            resumeDestination
                                .environmentObject(onboardingManager)
                                .environmentObject(dataManager)
                        }
                        .environmentObject(onboardingManager),
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
        .overlay(alignment: .top) {
            if authManager.needsLaunchRestoreRetry,
               authManager.isAuthenticated,
               !authManager.isLoadingProfile {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MiyaTheme.ink.opacity(0.85))
                    Text("We couldn’t finish syncing. Check your connection and try again.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MiyaTheme.ink.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Retry") {
                        NotificationCenter.default.post(name: .miyaColdStartHydrationRetry, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.miyaPrimary)
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                .padding(.horizontal, MiyaTheme.hPad)
                .padding(.top, 8)
            }
        }
        .task(id: "\(authManager.isAuthenticated)-\(onboardingManager.isOnboardingComplete)-\(onboardingManager.isSuperAdmin)-\(subscriptionManager.entitlementCheckComplete)-\(subscriptionManager.hasActiveSubscription)-\(onboardingManager.freshlyCompletedGetStarted)-\(onboardingManager.isHydrated)") {
#if DEBUG
            do {
                let route: String
                if !authManager.hasFinishedInitialLaunchRouting {
                    route = "startup-gate (initial launch routing)"
                } else if authManager.isAuthenticated && !onboardingManager.isHydrated {
                    route = "startup-gate (signed-in, hydrating profile)"
                } else if authManager.isAuthenticated && !onboardingManager.isOnboardingComplete {
                    route = "auth-entry + onboarding-resume (step=\(onboardingManager.currentStep) hydrated=\(onboardingManager.isHydrated) autoResumed=\(hasAutoResumed))"
                } else if authManager.isAuthenticated && onboardingManager.isOnboardingComplete {
                    if shouldShowPaywall { route = "paywall" }
                    else if shouldShowBillingRecovery { route = "billing-recovery" }
                    else { route = "dashboard" }
                } else {
                    route = "auth-entry (not authenticated)"
                }
                print("🗺️ RouteDecision [\(route)] auth=\(authManager.isAuthenticated) loading=\(authManager.isLoadingProfile) complete=\(onboardingManager.isOnboardingComplete) step=\(onboardingManager.currentStep) hydrated=\(onboardingManager.isHydrated)")
            }
            if authManager.isAuthenticated && onboardingManager.isOnboardingComplete {
                let reason: String
                if !onboardingManager.isSuperAdmin {
                    reason = "not-superadmin → dashboard"
                } else if onboardingManager.freshlyCompletedGetStarted {
                    reason = "fresh-new-account → PAYWALL (hasActive=\(subscriptionManager.hasActiveSubscription) ignored)"
                } else if hasActiveSubscriptionAccess {
                    reason = "has-active-subscription → dashboard"
                } else if !subscriptionManager.entitlementCheckComplete {
                    reason = "entitlement-pending → loader"
                } else {
                    reason = "no-access → PAYWALL"
                }
                print("🔎 PaywallGate [\(reason)] shouldShowPaywall=\(shouldShowPaywall)")
            }
#endif
            await refreshFamilyBillingState()
        }
        // Auto-resume: .task handles the common case where hydration finished during splash
        // (before this view mounted). .onChange handles the rare case where hydration
        // finishes after this view is already on screen.
        .task { autoResumeOnboardingIfNeeded() }
        /// Re-query StoreKit after Miya profile is ready (no `AppStore.sync()` — avoids Apple ID prompts right after Sign in with Apple).
        .task(id: "\(authManager.isAuthenticated)-\(onboardingManager.isHydrated)-\(onboardingManager.isSuperAdmin)-\(onboardingManager.isOnboardingComplete)-\(onboardingManager.freshlyCompletedGetStarted)") {
            guard authManager.isAuthenticated,
                  onboardingManager.isHydrated,
                  onboardingManager.isOnboardingComplete,
                  onboardingManager.isSuperAdmin,
                  !onboardingManager.freshlyCompletedGetStarted,
                  !subscriptionManager.hasActiveSubscription else { return }
            await subscriptionManager.reloadSubscriptionAfterMiyaProfileHydratedIfNeeded()
        }
        .onChange(of: onboardingManager.isHydrated) { _, _ in autoResumeOnboardingIfNeeded() }
    }

    /// Push the user to their saved onboarding step after cold-start hydration,
    /// instead of leaving them stuck at the Get Started / Log In screen.
    private func autoResumeOnboardingIfNeeded() {
        guard onboardingManager.isHydrated,
              authManager.isAuthenticated,
              !onboardingManager.isOnboardingComplete,
              !navigateResume,
              !hasAutoResumed else { return }
        hasAutoResumed = true
        navigateResume = true
#if DEBUG
        print("🔁 AutoResume: navigating to step \(onboardingManager.currentStep)")
#endif
    }
    
    @MainActor
    private func refreshFamilyBillingState() async {
        guard authManager.isAuthenticated, onboardingManager.isOnboardingComplete else {
            familyBillingState = nil
            billingActionError = nil
            return
        }
        isRefreshingBillingState = true
        defer { isRefreshingBillingState = false }
        do {
            familyBillingState = try await dataManager.fetchMyFamilyBillingState()
            billingActionError = nil
        } catch {
            billingActionError = "Couldn't verify family billing state."
        }
    }
    
    @MainActor
    private func claimFamilyBillingOwner() async {
        isRefreshingBillingState = true
        defer { isRefreshingBillingState = false }
        do {
            try await dataManager.claimFamilyBillingOwnership()
            familyBillingState = try await dataManager.fetchMyFamilyBillingState()
            billingActionError = nil
        } catch {
            billingActionError = "Could not take over billing. Please try again."
        }
    }
}

private struct BillingRecoveryView: View {
    let errorMessage: String?
    let isLoading: Bool
    let onTakeOverBilling: () -> Void
    
    var body: some View {
        ZStack {
            MiyaBackgroundWash()
            VStack(spacing: 16) {
                Image(systemName: "creditcard.trianglebadge.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundColor(.miyaPrimary)
                Text("Billing required")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.miyaTextPrimary)
                Text("Your family's billing grace period ended. Take over billing to restore access.")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button(action: onTakeOverBilling) {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        }
                        Text(isLoading ? "Processing..." : "Take over billing")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.miyaPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isLoading)
                .padding(.horizontal, 24)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
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
    
    // Account creation state (Sign in with Apple only on iOS)
    @State private var firstName: String = ""
    /// Inline hint when user taps Sign in with Apple before entering name (no alert).
    @State private var authNameInlineHint: String?

    // Guided setup acceptance (only for Guided Setup invites)
    @State private var showGuidedAcceptancePrompt: Bool = false
    @State private var wearablesIsGuidedSetupInvite: Bool = false
    
    // Navigation and error state
    @State private var navigateToWearables: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isAppleSignInLoading: Bool = false

    private var isCodeValid: Bool {
        inviteCode.trimmingCharacters(in: .whitespaces).count >= 4
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
                    // STEP 2: Create account (code validated) — Sign in with Apple only
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
        .onChange(of: firstName) { _ in
            if !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                authNameInlineHint = nil
                showError = false
            }
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
    }
    
    // MARK: - Enter Code Section
    
    private var enterCodeSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text("Enter your invite code")
                .font(.system(size: 28, weight: .bold))
            
            Text("Enter the code your family shared with you to join them in Miya.")
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
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Name")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("Your name", text: $firstName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                    .cornerRadius(12)
            }

            let nameMissing = firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let appleBlocked = isAppleSignInLoading || authManager.isLoading

            ZStack {
                SignInWithAppleButtonView { idToken, nonce, fullName in
                    await handleAppleSignInForInvite(idToken: idToken, nonce: nonce, fullName: fullName)
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

            Text("Sign in with Apple uses your Apple ID — same as your App Store subscription.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let hint = authNameInlineHint {
                Text(hint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            onboardingManager.invitedMemberOnboardingType = details.onboardingType
            onboardingManager.guidedSetupStatus = details.guidedSetupStatus
            onboardingManager.invitedMemberId = details.memberId
            onboardingManager.invitedFamilyId = details.familyId
            if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                firstName = details.firstName
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isValidatingCode = false
    }
    
    private func handleAppleSignInForInvite(idToken: String, nonce: String?, fullName: PersonNameComponents?) async {
        guard let details = inviteDetails else { return }
        showError = false
        isAppleSignInLoading = true
        defer { isAppleSignInLoading = false }
        do {
            let normalizedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let userId = try await authManager.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
            let resolvedFirstName = fullName?.givenName ?? fullName?.familyName ?? firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            try await dataManager.createInitialProfile(userId: userId, firstName: resolvedFirstName, step: 2)
            try await dataManager.completeInviteRedemption(code: normalizedCode, userId: userId)
            onboardingManager.firstName = resolvedFirstName
            onboardingManager.currentUserId = userId
            onboardingManager.isInvitedUser = true
            onboardingManager.familyName = details.familyName
            onboardingManager.invitedMemberOnboardingType = details.onboardingType
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
            return "Your family chose to set up your profile for you — accept to continue"
        }
        return "You’ll create your own profile in the next steps"
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
            onboardingManager.invitedMemberOnboardingType = "Self Setup"
            
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

// MARK: - Login View (existing account — Sign in with Apple)
struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var errorMessage: String = ""
    @State private var isAppleSignInLoading: Bool = false
    
    var onSuccess: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Use Sign in with Apple with the same Apple ID you use for your Miya subscription and App Store purchases.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                
                SignInWithAppleButtonView { idToken, nonce, fullName in
                    await handleAppleSignIn(idToken: idToken, nonce: nonce, fullName: fullName)
                }
                .frame(maxWidth: .infinity)
                .frame(height: MiyaTheme.buttonH)
                .disabled(isAppleSignInLoading)
                
                if isAppleSignInLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.miyaPrimary))
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MiyaTheme.hPad)
            .padding(.top, 24)
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
                authManager.isLoadingProfile = true
                onboardingManager.isHydrated = false
                dismiss()
                onSuccess()
            }
            await AuthenticatedLaunchHydration.hydrateAuthenticatedUser(
                dataManager: dataManager,
                onboardingManager: onboardingManager
            )
            await MainActor.run {
                onboardingManager.isHydrated = true
                authManager.isLoadingProfile = false
            }
        } catch {
            await MainActor.run {
                authManager.isLoadingProfile = false
                onboardingManager.isHydrated = true
                errorMessage = error.localizedDescription
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
