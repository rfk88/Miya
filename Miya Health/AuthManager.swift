//
//  AuthManager.swift
//  Miya Health
//
//  Manages user authentication with Supabase.
//

import SwiftUI
import Combine
import Supabase
import Foundation

@MainActor
class AuthManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isLoading: Bool = false
    @Published var isAuthenticated: Bool = false
    
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
            print("✅ AuthManager: User signed up successfully: \(user.id.uuidString)")
            
            return user.id.uuidString
            
        } catch {
            print("❌ AuthManager: Sign up error: \(error.localizedDescription)")
            throw AuthError.signUpFailed(error.localizedDescription)
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
            print("✅ AuthManager: User signed in successfully: \(session.user.id.uuidString)")
            
        } catch {
            print("❌ AuthManager: Sign in error: \(error.localizedDescription)")
            throw AuthError.signInFailed(error.localizedDescription)
        }
    }
    
    /// Restore user session on app launch
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
            isAuthenticated = false
            print("⚠️ AuthManager: No active session found")
        }
    }
    
    /// Sign out the current user
    func signOut() async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await supabase.auth.signOut()
            isAuthenticated = false
            UserDefaults.standard.set(true, forKey: explicitLogoutKey)
            print("✅ AuthManager: User signed out successfully")
            
            // Notify app to reset all state (zero leakage)
            NotificationCenter.default.post(name: .userDidLogout, object: nil)
            
        } catch {
            print("❌ AuthManager: Sign out error: \(error.localizedDescription)")
            throw AuthError.signOutFailed(error.localizedDescription)
        }
    }
    
    /// Get the current authenticated user's ID
    /// - Returns: The user's UUID string, or nil if not authenticated
    func getCurrentUserId() async -> String? {
        guard isAuthenticated else {
            return nil
        }
        
        do {
            let session = try await supabase.auth.session
            return session.user.id.uuidString
        } catch {
            print("⚠️ AuthManager: Failed to get current user ID: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case signUpFailed(String)
    case signInFailed(String)
    case signOutFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .signUpFailed(let message):
            return "Failed to create account: \(message)"
        case .signInFailed(let message):
            return "Failed to sign in: \(message)"
        case .signOutFailed(let message):
            return "Failed to sign out: \(message)"
        }
    }
}
