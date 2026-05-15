//
//  AuthManager.swift
//  Miya Health
//
//  Manages user authentication with Supabase.
//

import SwiftUI
import Combine
import Supabase
import Auth
import Foundation

@MainActor
class AuthManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isLoading: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var isLoadingProfile: Bool = false  // Tracks profile/onboarding data loading after auth
    /// True when cold-start profile/family hydration timed out; user can tap Retry to re-run.
    @Published var needsLaunchRestoreRetry: Bool = false
    /// False until `performColdStartRestore` finishes (session probe + optional hydration). Used so we don’t show
    /// “Syncing your profile…” during automatic Keychain session restore — that copy implies the user just signed in.
    @Published private(set) var hasFinishedInitialLaunchRouting: Bool = false

    init() {
        // Until `performColdStartRestore` runs, avoid a one-frame window where the user could reach
        // sign-up before `.task` sets loading flags (`isHydrated` defaults false → spurious Syncing gate).
        isLoadingProfile = true
    }
    
    // MARK: - Supabase Client
    
    private let supabase = SupabaseConfig.client
    
    /// Explicit logout gate: if true, we do NOT auto-restore a previous session on app launch/rebuild.
    /// This prevents "restoreSession overrides logout" even in edge cases (e.g. token cache timing).
    private let explicitLogoutKey = "miya.explicit_logout"
    
    // MARK: - Authentication Methods
    
    /// Sign up a new user
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    ///   - firstName: User's first name (stored in metadata)
    /// - Returns: The newly created user's ID
    func signUp(email: String, password: String, firstName: String) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: [
                    "first_name": AnyJSON.string(firstName)
                ]
            )
            
            // response.user is non-optional in newer Supabase SDK
            let user = response.user
            
            isAuthenticated = true
            UserDefaults.standard.set(false, forKey: explicitLogoutKey)
#if DEBUG
            ScreenshotDemoData.syncForAuthenticatedUser(email: email)
#endif
            print("✅ AuthManager: User signed up successfully: \(user.id.uuidString)")
            
            return user.id.uuidString
            
        } catch {
            print("❌ AuthManager: Sign up error: \(error.localizedDescription)")
            throw AuthError.signUpFailed(error.localizedDescription)
        }
    }
    
    /// Sign in with Apple (native id token).
    /// - Parameters:
    ///   - idToken: The identity token from ASAuthorizationAppleIDCredential (as UTF-8 string).
    ///   - nonce: Optional nonce used for the request (Supabase may require it for verification).
    ///   - fullName: Person name from Apple (only provided on first authorization); if present, stored in user metadata.
    /// - Returns: The signed-in user's UUID string.
    func signInWithApple(idToken: String, nonce: String?, fullName: PersonNameComponents?) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        do {
            let credentials = OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
            let session = try await supabase.auth.signInWithIdToken(credentials: credentials)
            let user = session.user

            isAuthenticated = true
            UserDefaults.standard.set(false, forKey: explicitLogoutKey)
#if DEBUG
            ScreenshotDemoData.syncForAuthenticatedUser(email: user.email)
#endif
            print("✅ AuthManager: User signed in with Apple: \(user.id.uuidString)")

            if let name = fullName {
                let given = name.givenName ?? ""
                let family = name.familyName ?? ""
                let full = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
                var data: [String: AnyJSON] = [
                    "first_name": .string(given.isEmpty ? (family.isEmpty ? "User" : family) : given),
                    "full_name": .string(full.isEmpty ? "User" : full),
                    "given_name": .string(given),
                    "family_name": .string(family)
                ]
                try? await supabase.auth.update(user: UserAttributes(data: data))
            }

            return user.id.uuidString
        } catch {
            print("❌ AuthManager: Sign in with Apple error: \(error.localizedDescription)")
            throw AuthError.signInFailed(error.localizedDescription)
        }
    }

    /// Sign in an existing user
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            
            isAuthenticated = true
            UserDefaults.standard.set(false, forKey: explicitLogoutKey)
#if DEBUG
            ScreenshotDemoData.syncForAuthenticatedUser(email: email)
#endif
            print("✅ AuthManager: User signed in successfully: \(session.user.id.uuidString)")
            
        } catch {
            print("❌ AuthManager: Sign in error: \(error.localizedDescription)")
            throw AuthError.signInFailed(error.localizedDescription)
        }
    }
    
    /// Restore user session on app launch.
    /// Uses a single retry on failure to avoid logging out due to transient network or refresh errors.
    func restoreSession() async {
        // If user explicitly logged out, do not restore a session automatically.
        if UserDefaults.standard.bool(forKey: explicitLogoutKey) {
            isAuthenticated = false
            print("🧹 AuthManager: Skipping restoreSession() due to explicit logout")
            return
        }
        do {
            let session = try await supabase.auth.session
            isAuthenticated = true
            print("✅ AuthManager: Session restored for user: \(session.user.id.uuidString)")
        } catch {
            // One retry: transient network or refresh failures should not log the user out.
            let hasStoredSession = supabase.auth.currentSession != nil
            if hasStoredSession {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                do {
                    let session = try await supabase.auth.refreshSession()
                    isAuthenticated = true
                    print("✅ AuthManager: Session restored after retry for user: \(session.user.id.uuidString)")
                    return
                } catch {
                    print("⚠️ AuthManager: Retry refresh failed: \(error.localizedDescription)")
                }
            }
            isAuthenticated = false
            print("⚠️ AuthManager: No active session found")
        }
    }
    
    /// Sign out the current user
    func signOut() async throws {
        isLoading = true
        defer { isLoading = false }

        var serverError: Error?
        do {
            try await supabase.auth.signOut()
            print("✅ AuthManager: User signed out successfully")
        } catch {
            print("❌ AuthManager: Sign out server error (local state cleared anyway): \(error.localizedDescription)")
            serverError = error
        }

        // Always clear local state so the user is never stuck in a
        // half-logged-in limbo when the network call fails.
        isAuthenticated = false
        needsLaunchRestoreRetry = false
        UserDefaults.standard.set(true, forKey: explicitLogoutKey)
#if DEBUG
        ScreenshotDemoData.disableDemoMode()
#endif
        NotificationCenter.default.post(name: .userDidLogout, object: nil)

        if let serverError {
            throw AuthError.signOutFailed(serverError.localizedDescription)
        }
    }
    
    /// Get the current authenticated user's ID.
    /// - Returns: The user's UUID string, or nil if no active session is available.
    func getCurrentUserId() async -> String? {
        do {
            let session = try await supabase.auth.session
            return session.user.id.uuidString
        } catch {
            print("⚠️ AuthManager: Failed to get current user ID: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get the current authenticated user's email (if available).
    func getCurrentEmail() async throws -> String? {
        let session = try await supabase.auth.session
        return session.user.email
    }

    /// Re-authenticate by signing in again with email + password.
    /// This refreshes the session and satisfies "recent login" requirements for sensitive changes.
    func reauthenticate(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await supabase.auth.signIn(email: email, password: password)
            isAuthenticated = true
            UserDefaults.standard.set(false, forKey: explicitLogoutKey)
        } catch {
            throw AuthError.signInFailed(error.localizedDescription)
        }
    }

    /// Verify the current user's password without touching the global isLoading state.
    /// Use this from screens that manage their own local loading state (e.g. ChangePasswordView, ChangeEmailView).
    /// Throws AuthError.signInFailed if the password is wrong.
    func verifyCurrentPassword(_ password: String) async throws {
        guard let email = try await getCurrentEmail() else {
            throw AuthError.signInFailed("Could not determine current account email.")
        }
        do {
            _ = try await supabase.auth.signIn(email: email, password: password)
        } catch {
            throw AuthError.signInFailed(error.localizedDescription)
        }
    }

    /// Request an email change for the current authenticated user.
    /// Note: Supabase may require confirmation via email depending on project settings.
    func updateEmail(to newEmail: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await supabase.auth.update(user: UserAttributes(email: newEmail))
        } catch {
            throw AuthError.updateFailed(error.localizedDescription)
        }
    }

    /// Update the password for the current authenticated user.
    func updatePassword(to newPassword: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await supabase.auth.update(user: UserAttributes(password: newPassword))
        } catch {
            throw AuthError.updateFailed(error.localizedDescription)
        }
    }

    /// Change email using a local loading state only — does NOT set the global isLoading flag,
    /// preventing the full view hierarchy from re-rendering and freezing the app.
    /// Supabase sends a confirmation link to the new address; the change is not applied until confirmed.
    func changeEmail(to newEmail: String) async throws {
        do {
            _ = try await supabase.auth.update(user: UserAttributes(email: newEmail))
        } catch {
            throw AuthError.updateFailed(error.localizedDescription)
        }
    }

    /// Change password using a local loading state only — does NOT set the global isLoading flag.
    /// No re-authentication is required by Supabase for password changes.
    func changePassword(to newPassword: String) async throws {
        do {
            _ = try await supabase.auth.update(user: UserAttributes(password: newPassword))
        } catch {
            throw AuthError.updateFailed(error.localizedDescription)
        }
    }
    
    /// Called from `Miya_HealthApp.performColdStartRestore` defer when launch routing is done (success, timeout, or no session).
    func markInitialLaunchRoutingFinished() {
        hasFinishedInitialLaunchRouting = true
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case signUpFailed(String)
    case signInFailed(String)
    case signOutFailed(String)
    case updateFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .signUpFailed(let message):
            return "Failed to create account: \(message)"
        case .signInFailed(let message):
            return "Failed to sign in: \(message)"
        case .signOutFailed(let message):
            return "Failed to sign out: \(message)"
        case .updateFailed(let message):
            return message
        }
    }
}
