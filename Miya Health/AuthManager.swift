//
//  AuthManager.swift
//  Miya Health
//
//  This manages user authentication (sign up, sign in, sign out).
//  It's an "ObservableObject" which means SwiftUI views can watch it for changes.
//

import Foundation
import Combine
import Supabase

// MARK: - Auth Manager

@MainActor
class AuthManager: ObservableObject {
    
    // MARK: - Published Properties
    // These automatically update the UI when they change
    
    @Published var isAuthenticated: Bool = false
    @Published var currentUserId: UUID? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    // MARK: - Initialization
    
    init() {
        // Check if user is already logged in when app starts
        Task {
            await checkCurrentSession()
        }
    }
    
    // MARK: - Check Current Session
    
    /// Checks if the user is already logged in from a previous session
    func checkCurrentSession() async {
        do {
            let session = try await supabase.auth.session
            self.currentUserId = session.user.id
            self.isAuthenticated = true
        } catch {
            // No active session - user needs to log in
            self.isAuthenticated = false
            self.currentUserId = nil
        }
    }
    
    // MARK: - Sign Up
    
    /// Creates a new user account
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's chosen password (min 8 characters)
    ///   - firstName: User's first name
    /// - Returns: The new user's ID if successful
    func signUp(email: String, password: String, firstName: String) async throws -> UUID {
        isLoading = true
        errorMessage = nil
        
        defer {
            isLoading = false
        }
        
        do {
            // Create the account in Supabase Auth
            let response = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: [
                    "first_name": .string(firstName)
                ]
            )
            
            // Get the user ID from the response
            let userId = response.user.id
            
            // Update our state
            self.currentUserId = userId
            self.isAuthenticated = true
            
            print("✅ User signed up successfully: \(userId)")
            return userId
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("❌ Sign up error: \(error)")
            throw error
        }
    }
    
    // MARK: - Sign In
    
    /// Signs in an existing user
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        
        defer {
            isLoading = false
        }
        
        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            
            self.currentUserId = session.user.id
            self.isAuthenticated = true
            
            print("✅ User signed in successfully: \(session.user.id)")
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("❌ Sign in error: \(error)")
            throw error
        }
    }
    
    // MARK: - Sign Out
    
    /// Signs out the current user
    func signOut() async throws {
        isLoading = true
        errorMessage = nil
        
        defer {
            isLoading = false
        }
        
        do {
            try await supabase.auth.signOut()
            
            self.currentUserId = nil
            self.isAuthenticated = false
            
            print("✅ User signed out successfully")
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("❌ Sign out error: \(error)")
            throw error
        }
    }
}

// MARK: - Custom Errors

enum AuthError: LocalizedError {
    case noUserReturned
    
    var errorDescription: String? {
        switch self {
        case .noUserReturned:
            return "Account was created but no user ID was returned. Please try again."
        }
    }
}

