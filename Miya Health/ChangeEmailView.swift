//
//  ChangeEmailView.swift
//  Miya Health
//
//  Dedicated sheet for changing the user's email address.
//  Uses local loading state only — does not touch AuthManager.isLoading,
//  which prevents the full view hierarchy from re-rendering and freezing the app.
//
//  Flow:
//  1. User enters current password and new email, then taps Send confirmation link.
//  2. Current password is verified via re-authentication before the request is made.
//  3. Supabase sends a confirmation link to the new address.
//  4. User clicks the link — the app handles it via onOpenURL in Miya_HealthApp.
//  5. The email change is applied after confirmation.
//

import SwiftUI

struct ChangeEmailView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword: String = ""
    @State private var newEmail: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var didSend: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.miyaBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    if didSend {
                        confirmationView
                    } else {
                        formView
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .navigationTitle("Change email")
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
            Text("Confirm your current password, then enter the new email address. We'll send a confirmation link to it — the change won't take effect until you click the link.")
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
                    Text("New email address")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.miyaTextSecondary)
                    TextField("you@example.com", text: $newEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
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
                    Text(isSaving ? "Sending…" : "Send confirmation link")
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

    // MARK: - Confirmation

    private var confirmationView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.checkmark")
                .font(.system(size: 48))
                .foregroundColor(.miyaEmerald)

            Text("Check your inbox")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)

            Text("We sent a confirmation link to **\(newEmail)**. Tap the link in that email to complete the change.")
                .font(.system(size: 14))
                .foregroundColor(.miyaTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("The link will open the Miya app automatically. Your current email stays active until you confirm.")
                .font(.system(size: 13))
                .foregroundColor(.miyaTextSecondary.opacity(0.8))
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

    private var canSave: Bool {
        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return !currentPassword.isEmpty && trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    private func save() async {
        errorMessage = nil
        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !currentPassword.isEmpty else {
            errorMessage = "Please enter your current password."
            return
        }
        guard trimmed.contains("@"), trimmed.contains("."), trimmed.count >= 5 else {
            errorMessage = "Please enter a valid email address."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await authManager.verifyCurrentPassword(currentPassword)
            try await authManager.changeEmail(to: trimmed)
            newEmail = trimmed
            didSend = true
        } catch {
            if (error as? AuthError) != nil {
                errorMessage = "Current password is incorrect."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
