//
//  AuthService.swift
//  Perch
//
//  Real Supabase Auth service using native Supabase email/password sign-in.
//  Observes auth state changes and surfaces a reactive isSignedIn flag.
//

import Foundation
import Supabase

@Observable
@MainActor
final class AuthService {
    private(set) var isSignedIn = false
    private(set) var userId: String?
    private(set) var email: String?
    private(set) var isLoading = true
    private(set) var authError: String?

    private let supabase: SupabaseClientService

    init(supabase: SupabaseClientService) {
        self.supabase = supabase
        // Observe auth state changes.
        Task { await observeAuth() }
    }

    // MARK: - Auth state observation

    private func observeAuth() async {
        for await (event, session) in supabase.client.auth.authStateChanges {
            switch event {
            case .initialSession:
                if let session {
                    isSignedIn = true
                    userId = session.user.id.uuidString
                    email = session.user.email
                } else {
                    isSignedIn = false
                    userId = nil
                    email = nil
                }
                isLoading = false
            case .signedIn:
                isSignedIn = true
                userId = session?.user.id.uuidString
                email = session?.user.email
                isLoading = false
            case .signedOut:
                isSignedIn = false
                userId = nil
                email = nil
                isLoading = false
            case .tokenRefreshed:
                userId = session?.user.id.uuidString
                email = session?.user.email
            default:
                break
            }
        }
    }

    // MARK: - Sign up

    /// Sign up a new user with email + password.
    func signUp(email address: String, password: String) async throws {
        authError = nil
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), trimmed.contains(".") else {
            authError = "Please enter a valid email address."
            throw AuthError.invalidEmail
        }
        guard password.count >= 6 else {
            authError = "Password must be at least 6 characters."
            throw AuthError.weakPassword
        }
        do {
            _ = try await supabase.client.auth.signUp(email: trimmed, password: password)
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign in

    /// Sign in an existing user with email + password.
    func signIn(email address: String, password: String) async throws {
        authError = nil
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), trimmed.contains(".") else {
            authError = "Please enter a valid email address."
            throw AuthError.invalidEmail
        }
        do {
            _ = try await supabase.client.auth.signIn(
                email: trimmed,
                password: password
            )
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign out

    func signOut() async throws {
        authError = nil
        do {
            try await supabase.client.auth.signOut()
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Profile sync

    /// Ensure a profile row exists for the current user (idempotent upsert).
    func ensureProfile() async throws {
        guard let uid = userId, let em = email else { return }
        do {
            try await supabase.client
                .from("profiles")
                .upsert(ProfileUpsert(id: uid, email: em))
                .execute()
        } catch {
            // The handle_new_user trigger may have already created it — ignore.
            print("Profile upsert skipped (may already exist): \(error)")
        }
    }
}

// MARK: - Errors

nonisolated enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Please enter a valid email address."
        case .weakPassword: return "Password must be at least 6 characters."
        case .notSignedIn: return "You need to sign in first."
        }
    }
}

// MARK: - Encodable helpers for Supabase

nonisolated struct ProfileUpsert: Encodable, Sendable {
    let id: String
    let email: String
}
