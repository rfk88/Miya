//
//  AuthEntryScreen.swift
//  Miya Health
//
//  Home and login entry screen (unauthenticated).
//

import SwiftUI

private let authEntryValueProps: [String] = [    "Understand your family's health at a glance with a simple score that highlights sleep, activity and recovery patterns.",
    "Spot changes early as Miya connects health signals over time and notifies you when something starts drifting.",
    "Turn wearable data into real insights so you don't have to interpret endless charts and numbers.",
    "Build healthier habits together through family challenges and shared accountability that make routines stick."
]

struct AuthEntryScreen: View {
    @Binding var showingSettings: Bool
    @Binding var showingLogin: Bool
    @State private var valuePropPage: Int = 0
    #if DEBUG
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var onboardingManager: OnboardingManager
    @EnvironmentObject private var dataManager: DataManager
    @State private var isDemoLoading = false
    @State private var demoError: String?
    #endif

    var body: some View {
        ZStack {
            MiyaBackgroundWash()

            VStack(spacing: 0) {
                // Logo + Miya Health + hero title only (keep exactly where it is)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: -35) {
                        Image("e96bc988831220de186601645fd93835b8dede817e5045c208d02c6fb54bd4c8")
                            .resizable()
                            .renderingMode(.original)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 112, height: 112)

                        Text("Miya Health")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.miyaPrimary)
                            .kerning(-0.2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, MiyaTheme.hPad)
                    .offset(x: -19)

                    Text("Your family's\nhealth, at a glance.")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(MiyaTheme.ink)
                        .kerning(-0.6)
                        .lineSpacing(4)
                        .padding(.horizontal, MiyaTheme.hPad)
                        .padding(.top, 4)
                }
                .offset(y: -44)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Value props + dots (pushed further down)
                VStack(alignment: .leading, spacing: 0) {
                    TabView(selection: $valuePropPage) {
                        ForEach(Array(authEntryValueProps.enumerated()), id: \.offset) { index, text in
                            Text(text)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(MiyaTheme.ink.opacity(0.7))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 120)

                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(index == valuePropPage ? MiyaTheme.ink : MiyaTheme.ink.opacity(0.25))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, MiyaTheme.hPad)
                .padding(.top, 56)

                // CTAs
                VStack(spacing: MiyaTheme.ctaGap) {
                    // Primary - Create a new family (NavigationLink preserved)
                    NavigationLink {
                        SuperadminOnboardingView()
                    } label: {
                        Text("Get started")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.white)
                            .kerning(-0.2)
                    }
                    .buttonStyle(MiyaPrimaryButtonStyle())

                    // Secondary - Enter Code (NavigationLink preserved)
                    NavigationLink {
                        EnterCodeView()
                    } label: {
                        Text("Join with code")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(MiyaTheme.ink)
                    }
                    .buttonStyle(MiyaSecondaryButtonStyle())

                    // Tertiary - I already have an account (Button action preserved)
                    Button(action: { showingLogin = true }) {
                        Text("I already have an account")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(MiyaTheme.ink.opacity(0.42))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                    .buttonStyle(.plain)

                    #if DEBUG
                    // Demo: one-tap login with fake data so dashboard is always full (no backend setup needed).
                    Button(action: { Task { await runDemoLogin() } }) {
                        if isDemoLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: MiyaTheme.ink))
                                .scaleEffect(0.9)
                        } else {
                            Text("Try demo")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(MiyaTheme.ink.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .disabled(isDemoLoading)
                    .buttonStyle(.plain)
                    if let err = demoError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 4)
                    }
                    #endif
                }
                .padding(.horizontal, MiyaTheme.hPad)
                .padding(.top, 80)
                .padding(.bottom, 20)
            }
        }
        #if DEBUG
        .task(id: demoError) {
            if demoError != nil {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                demoError = nil
            }
        }
        #endif
    }

    #if DEBUG
    private func runDemoLogin() async {
        isDemoLoading = true
        demoError = nil
        defer { isDemoLoading = false }
        do {
            // Sign in; if account doesn't exist, create it (signUp signs in).
            do {
                try await authManager.signIn(email: ScreenshotDemoData.demoEmail, password: ScreenshotDemoData.demoPassword)
            } catch {
                _ = try? await authManager.signUp(email: ScreenshotDemoData.demoEmail, password: ScreenshotDemoData.demoPassword, firstName: "Simon")
            }
            guard authManager.isAuthenticated else {
                demoError = "Could not sign in or create demo account."
                return
            }
            dataManager.restorePersistedState()
            ScreenshotDemoData.isScreenshotModeEnabled = true
            onboardingManager.familyName = "The Smiths"
            onboardingManager.firstName = "Simon"
            onboardingManager.setCurrentStep(7)
            onboardingManager.isOnboardingComplete = true
        } catch {
            demoError = error.localizedDescription
        }
    }
    #endif
}

#Preview {
    NavigationStack {
        AuthEntryScreen(
            showingSettings: .constant(false),
            showingLogin: .constant(false)
        )
    }
}
