//
//  AuthService.swift
//  Perch
//
//  Isolated auth surface. Mirrors a Supabase email sign-in flow but runs
//  locally for now, so it can be swapped for real Supabase Auth later without
//  changing any screen.
//

import Foundation

@Observable
@MainActor
final class AuthService {
    private(set) var email: String?
    var isSignedIn: Bool { email != nil }

    private let storageKey = "perch.auth.email"

    init() {
        email = UserDefaults.standard.string(forKey: storageKey)
    }

    /// Simulated email sign-in. Returns once "authenticated".
    func signIn(email address: String) async throws {
        // Simulate a brief network round-trip.
        try? await Task.sleep(for: .milliseconds(700))
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), trimmed.contains(".") else {
            throw AuthError.invalidEmail
        }
        email = trimmed
        UserDefaults.standard.set(trimmed, forKey: storageKey)
    }

    func signOut() {
        email = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

nonisolated enum AuthError: LocalizedError {
    case invalidEmail

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Please enter a valid email address."
        }
    }
}
