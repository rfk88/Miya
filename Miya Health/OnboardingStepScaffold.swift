//
//  OnboardingStepScaffold.swift
//  Miya Health
//
//  Shared scaffold, keyboard utilities, and CTA bar used by all onboarding step views.
//

import SwiftUI
import UIKit

// MARK: - Auto-resume back (single NavigationLink) vs nested stack pop

/// When the user is deep in a `NavigationStack` from Get started, Back should `dismiss()`.
/// When the app auto-resumed onboarding via one push onto `AuthEntryScreen`, Back must decrement
/// `currentStep` instead, or the only `dismiss()` pops to Get started.
enum OnboardingBackBehavior: Sendable {
    case popNavigation
    case resumeStep
}

private struct OnboardingBackBehaviorKey: EnvironmentKey {
    static let defaultValue: OnboardingBackBehavior = .popNavigation
}

private struct OnboardingResumeStepBackKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var onboardingBackBehavior: OnboardingBackBehavior {
        get { self[OnboardingBackBehaviorKey.self] }
        set { self[OnboardingBackBehaviorKey.self] = newValue }
    }

    var onboardingResumeStepBack: (() -> Void)? {
        get { self[OnboardingResumeStepBackKey.self] }
        set { self[OnboardingResumeStepBackKey.self] = newValue }
    }
}

/// Shared Back action for onboarding screens (toolbar, custom HStacks, and `OnboardingCTABar`).
enum OnboardingBackAction {
    @MainActor
    static func perform(
        behavior: OnboardingBackBehavior,
        resumeStepBack: (() -> Void)?,
        dismiss: DismissAction,
        hideKeyboardFirst: Bool = false
    ) {
        if hideKeyboardFirst {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }
        switch behavior {
        case .popNavigation:
            dismiss()
        case .resumeStep:
            if let resumeStepBack {
                resumeStepBack()
            } else {
                dismiss()
            }
        }
    }
}

// MARK: - Keyboard dismiss helper

extension View {
    /// Dismisses the on-screen keyboard from any SwiftUI view.
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

// MARK: - Onboarding CTA Bar

/// Standard Back + Continue/primary action row, rendered inside a safe-area inset.
/// Always appears above the keyboard because `safeAreaInset` adjusts automatically.
struct OnboardingCTABar: View {
    @Environment(\.onboardingBackBehavior) private var onboardingBackBehavior
    @Environment(\.onboardingResumeStepBack) private var onboardingResumeStepBack

    var onBack: (() -> Void)?
    var backLabel: String = "Back"
    var backDisabled: Bool = false

    var onContinue: () -> Void
    var continueLabel: String
    var continueLoading: Bool = false
    var continueDisabled: Bool = false

    var showError: Bool = false
    var errorMessage: String = ""

    var body: some View {
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
                    .padding(.top, 8)
            }

            HStack(spacing: 12) {
                if let onBack {
                    Button {
                        switch onboardingBackBehavior {
                        case .popNavigation:
                            onBack()
                        case .resumeStep:
                            if let onboardingResumeStepBack {
                                hideKeyboard()
                                onboardingResumeStepBack()
                            } else {
                                onBack()
                            }
                        }
                    } label: {
                        Text(backLabel)
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
                    .disabled(backDisabled)
                }

                Button {
                    onContinue()
                } label: {
                    HStack(spacing: 8) {
                        if continueLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(continueLabel)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(continueDisabled ? Color.miyaPrimary.opacity(0.5) : Color.miyaPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                .disabled(continueDisabled || continueLoading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .padding(.bottom, 4)
        }
        .background(Color.miyaBackground)
    }
}
