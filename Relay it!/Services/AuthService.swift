//
//  AuthService.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import Foundation

/// Service for authentication operations
@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()
    
    @Published var currentUser: SupabaseClient.User?
    @Published var isAuthenticated = false
    @Published var isLoading = true
    
    private let client: SupabaseClient
    private let tokenKey = "relay_it_access_token"
    private let refreshTokenKey = "relay_it_refresh_token"
    
    private init() {
        self.client = SupabaseService.shared.client
        
        Task {
            await checkSession()
        }
    }
    
    // MARK: - Session Management
    
    /// Check for existing session and restore if valid
    func checkSession() async {
        isLoading = true
        defer { isLoading = false }
        
        // Try to restore session with saved token
        if let accessToken = UserDefaults.standard.string(forKey: tokenKey) {
            // Set the token on the client
            await client.setAccessToken(accessToken)
            
            // Check if the token gives us a valid user ID (JWT decode)
            if let userId = await client.currentUserId {
                // Token is valid (at least structurally)
                self.currentUser = SupabaseClient.User(id: userId, email: nil)
                self.isAuthenticated = true
                return
            }
        }
        
        currentUser = nil
        isAuthenticated = false
    }
    
    // MARK: - Email Auth
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async throws {
        let response = try await client.signIn(email: email, password: password)
        
        // Save tokens
        UserDefaults.standard.set(response.accessToken, forKey: tokenKey)
        UserDefaults.standard.set(response.refreshToken, forKey: refreshTokenKey)
        
        currentUser = response.user
        isAuthenticated = true
    }
    
    /// Sign up with email and password
    func signUp(email: String, password: String) async throws {
        let response = try await client.signUp(email: email, password: password)
        
        // Save tokens
        UserDefaults.standard.set(response.accessToken, forKey: tokenKey)
        UserDefaults.standard.set(response.refreshToken, forKey: refreshTokenKey)
        
        currentUser = response.user
        isAuthenticated = true
    }
    
    /// Sign out
    func signOut() async throws {
        // Clear saved tokens
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
        
        // Clear client token
        await client.setAccessToken("")
        
        currentUser = nil
        isAuthenticated = false
    }
    
    // MARK: - Password Reset
    
    /// Send password reset email
    func resetPassword(email: String) async throws {
        // Would need to implement reset password endpoint
        throw AuthError.notImplemented
    }
}

// MARK: - Errors
enum AuthError: LocalizedError {
    case notImplemented
    case invalidCredentials
    case signUpFailed
    
    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "This feature is not yet implemented"
        case .invalidCredentials:
            return "Invalid email or password"
        case .signUpFailed:
            return "Failed to create account"
        }
    }
}
