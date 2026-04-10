import SwiftUI

// MARK: - Explainer (info button / sheet body)

struct MiyaAIDataSharingExplainerContent: View {
    /// OpenAI's published privacy policy (consumer / API processing).
    private static let openAIPrivacyPolicyURLString = "https://openai.com/policies/privacy-policy/"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How Miya uses AI")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.miyaTextPrimary)

            Text(
                """
                When you turn on optional AI features, Miya sends limited content to OpenAI using OpenAI's APIs. OpenAI processes that content to generate chat replies, insights, and similar responses for you.

                Depending on what you use, this can include:
                • Health and wellness-related data from your account (such as sleep, activity, recovery, or related summaries)
                • The text of messages or questions you send in Miya
                • Profile details used for context (such as your first name)
                • Short summaries tied to patterns or notifications when a feature needs them to stay relevant

                Your information is not sold. It is used only to provide these optional features for you and your family. You can turn this off anytime; when it is off, we do not send your information to OpenAI for these features.
                """
            )
            .font(.system(size: 15))
            .foregroundColor(.miyaTextSecondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                if let miyaURL = URL(string: PaywallConfig.privacyPolicyURLString) {
                    Link(destination: miyaURL) {
                        Text("Miya Privacy Policy")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                if let openAIURL = URL(string: Self.openAIPrivacyPolicyURLString) {
                    Link(destination: openAIURL) {
                        Text("OpenAI's privacy policy")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Onboarding two-step AI nudge (optional)

/// Step 1: short reminder before leaving optional AI off.
struct OnboardingAIReminderSheet: View {
    let onTurnOn: () -> Void
    let onNoThanks: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Don't forget optional AI")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)

                    Text("You left optional AI off. Turning it on unlocks Miya chat, richer pattern insights, and helpful message suggestions — all powered by OpenAI, all optional. You can change this anytime in Settings.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        Button(action: onTurnOn) {
                            Text("Enable Miya AI (sends data to OpenAI)")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.miyaPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)

                        Button(action: onNoThanks) {
                            Text("No thanks, keep it off")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.miyaPrimary.opacity(0.12))
                                .foregroundColor(.miyaPrimary)
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .background(Color.miyaBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Step 2: benefits + explicit affirmative consent.
struct OnboardingAIBenefitsSheet: View {
    let onTurnOnAndContinue: () -> Void
    let onContinueWithoutAI: () -> Void

    @State private var showExplainer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Enable Miya AI — powered by OpenAI")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)

                    Text("Miya uses OpenAI's API to power these optional features:\n\n• Family chat — ask questions in plain language and get supportive, personalized guidance.\n• Deeper insights — clearer reads on patterns in your wellbeing data.\n• Smarter suggestions — help drafting check-in messages when you reach out to family.\n\nEnabling this sends limited health context to OpenAI. Miya sends only what's needed for each feature. You stay in control.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("This feature is off by default. You can change this anytime in Settings.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showExplainer = true
                    } label: {
                        Label("See exactly what data is shared", systemImage: "info.circle")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.miyaPrimary)

                    VStack(spacing: 10) {
                        Button(action: onTurnOnAndContinue) {
                            Text("Enable Miya AI (sends data to OpenAI)")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.miyaPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)

                        Button(action: onContinueWithoutAI) {
                            Text("Continue without AI")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.miyaPrimary.opacity(0.12))
                                .foregroundColor(.miyaPrimary)
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .background(Color.miyaBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showExplainer) {
                NavigationStack {
                    ScrollView {
                        MiyaAIDataSharingExplainerContent()
                            .padding(24)
                    }
                    .background(Color.miyaBackground.ignoresSafeArea())
                    .navigationTitle("How Miya uses AI")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showExplainer = false }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Legacy transparency (one-time after migration)

struct LegacyAIThirdPartyTransparencySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onManageSettings: () -> Void

    @State private var showExplainer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("A quick update on AI")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)

                    Text("Miya uses optional AI features powered by OpenAI's API — for example family chat and deeper pattern insights.\n\nYou're currently opted in so your experience stays the same. You can review details, read our Privacy Policy, or turn this off anytime in Settings.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showExplainer = true
                    } label: {
                        Label("Learn how this works", systemImage: "info.circle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.miyaPrimary)

                    VStack(spacing: 10) {
                        Button(action: onManageSettings) {
                            Text("Manage in Settings")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.miyaPrimary.opacity(0.12))
                                .foregroundColor(.miyaPrimary)
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)

                        Button {
                            dismiss()
                        } label: {
                            Text("Got it")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.miyaPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .background(Color.miyaBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showExplainer) {
                NavigationStack {
                    ScrollView {
                        MiyaAIDataSharingExplainerContent()
                            .padding(24)
                    }
                    .background(Color.miyaBackground.ignoresSafeArea())
                    .navigationTitle("About Miya AI")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showExplainer = false }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Gate when user opens Miya Chat without consent

/// Shown inline whenever the user tries to open Miya Chat and has not yet consented.
/// `onEnable` is called when the user taps the affirmative button — the caller is responsible
/// for saving consent and opening the chat. `onOpenSettings` is a fallback path to Settings.
struct AIThirdPartyConsentRequiredSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Called when the user explicitly taps "Enable Miya AI". Caller saves consent + opens chat.
    var onEnable: (() -> Void)? = nil
    /// Called when the user chooses to manage from Settings instead.
    let onOpenSettings: () -> Void

    @State private var showExplainer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Enable Miya AI to use this feature")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)

                    Text("Miya Chat and AI insights are powered by OpenAI's API. These features are off by default — you need to enable them before Miya can send any data to OpenAI.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("This feature is off by default. You can turn it off again anytime in Settings.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showExplainer = true
                    } label: {
                        Label("See exactly what data is shared with OpenAI", systemImage: "info.circle")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.miyaPrimary)

                    VStack(spacing: 10) {
                        if let onEnable {
                            Button(action: {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    onEnable()
                                }
                            }) {
                                Text("Enable Miya AI (sends data to OpenAI)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.miyaPrimary)
                                    .foregroundColor(.white)
                                    .cornerRadius(14)
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onOpenSettings()
                            }
                        }) {
                            Text(onEnable != nil ? "Manage in Settings instead" : "Open Settings")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.miyaPrimary.opacity(0.12))
                                .foregroundColor(.miyaPrimary)
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)

                        Button("Not now") {
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.miyaTextSecondary)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .background(Color.miyaBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showExplainer) {
                NavigationStack {
                    ScrollView {
                        MiyaAIDataSharingExplainerContent()
                            .padding(24)
                    }
                    .background(Color.miyaBackground.ignoresSafeArea())
                    .navigationTitle("About Miya AI")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showExplainer = false }
                        }
                    }
                }
            }
        }
    }
}
