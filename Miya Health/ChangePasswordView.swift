//
//  ChangePasswordView.swift
//  Miya Health
//
//  Dedicated sheet for changing the user's password.
//  Uses local loading state only — does not touch AuthManager.isLoading,
//  which prevents the full view hierarchy from re-rendering and freezing the app.
//
//  Flow:
//  1. User enters current password — re-authenticated against Supabase before proceeding.
//  2. User enters and confirms the new password.
//  3. Password is updated only after re-auth succeeds.
//

import SwiftUI

struct ChangePasswordView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var didSave: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.miyaBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    if didSave {
                        successView
                    } else {
                        formView
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Form

    private var formView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm your current password, then choose a new one (at least 8 characters).")
                .font(.system(size: 14))
                .foregroundColor(.miyaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current password")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.miyaTextSecondary)
                    SecureField("Enter current password", text: $currentPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("New password")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.miyaTextSecondary)
                    SecureField("At least 8 characters", text: $newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Confirm new password")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.miyaTextSecondary)
                    SecureField("Repeat new password", text: $confirmPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(passwordsMatch ? Color.black.opacity(0.08) : Color.red.opacity(0.4), lineWidth: 1)
                        )
                    if !confirmPassword.isEmpty && !passwordsMatch {
                        Text("Passwords don't match.")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await save() }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 4)
                    }
                    Text(isSaving ? "Saving…" : "Update password")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(canSave ? Color.miyaEmerald : Color.miyaEmerald.opacity(0.4))
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .disabled(!canSave || isSaving)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.miyaEmerald)

            Text("Password updated")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)

            Text("Your password has been changed successfully. Use the new password next time you sign in.")
                .font(.system(size: 14))
                .foregroundColor(.miyaTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.miyaEmerald)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var passwordsMatch: Bool {
        confirmPassword.isEmpty || newPassword == confirmPassword
    }

    private var canSave: Bool {
        !currentPassword.isEmpty && newPassword.count >= 8 && newPassword == confirmPassword
    }

    private func save() async {
        errorMessage = nil

        guard !currentPassword.isEmpty else {
            errorMessage = "Please enter your current password."
            return
        }
        guard newPassword.count >= 8 else {
            errorMessage = "New password must be at least 8 characters."
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords don't match."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await authManager.verifyCurrentPassword(currentPassword)
            try await authManager.changePassword(to: newPassword)
            didSave = true
        } catch {
            if (error as? AuthError) != nil {
                errorMessage = "Current password is incorrect."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
