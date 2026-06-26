//
//  AuthService.swift
//  Perch
//
//  Supabase Auth service with native Apple Sign In and Google Sign In.
//  Both providers exchange the platform identity token with Supabase via
//  signInWithIdToken — no web redirects. Observes auth state changes and
//  surfaces a reactive isSignedIn flag. Anonymous posture tracking works
//  without sign-in; sign-in is required only for Circles.
//

import Foundation
import Supabase
import AuthenticationServices
import GoogleSignIn
import ObjectiveC

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

    // MARK: - Google Sign In (native, via GoogleSignIn SDK → signInWithIdToken)

    /// Launches the native Google Sign In flow. The GoogleSignIn SDK presents
    /// its own sign-in UI (using the Google app if installed, or an in-app
    /// browser). Once complete, the ID token is exchanged with Supabase via
    /// signInWithIdToken — no web redirect to Supabase's OAuth endpoint.
    func signInWithGoogle(presenting viewController: UIViewController) async throws {
        authError = nil

        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
        } catch {
            authError = error.localizedDescription
            throw error
        }

        guard let idToken = result.user.idToken?.tokenString else {
            authError = "Google Sign In failed — no ID token received."
            throw AuthError.googleSignInFailed
        }

        do {
            _ = try await supabase.client.auth.signInWithIdToken(
                credentials: .init(provider: .google, idToken: idToken)
            )
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Apple Sign In

    /// Call this when you already have an Apple ID token (e.g. from
    /// SignInWithAppleButton). Exchanges the token with Supabase.
    func signInWithAppleToken(_ idToken: String) async throws {
        authError = nil
        do {
            _ = try await supabase.client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken)
            )
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    /// Programmatic Apple Sign In via ASAuthorizationController. Returns the
    /// user's full name on first sign-in, or nil on subsequent sign-ins.
    /// Prefer using SignInWithAppleButton + signInWithAppleToken(_:) in views;
    /// this method exists for programmatic use where a SwiftUI button isn't suitable.
    func signInWithApple() async throws -> String? {
        authError = nil
        let credential = try await performAppleSignIn()
        guard let appleCred = credential as? ASAuthorizationAppleIDCredential,
              let idTokenData = appleCred.identityToken,
              let idToken = String(data: idTokenData, encoding: .utf8) else {
            authError = "Apple Sign In failed — no identity token received."
            throw AuthError.appleSignInFailed
        }

        try await signInWithAppleToken(idToken)

        // Apple only provides fullName on the very first sign-in for this Apple ID.
        if let fullName = appleCred.fullName {
            let parts = [
                fullName.givenName,
                fullName.familyName
            ].compactMap { $0 }.filter { !$0.isEmpty }
            let name = parts.joined(separator: " ")
            if !name.isEmpty {
                return name
            }
        }
        return nil
    }

    /// Wraps ASAuthorizationController in an async continuation so callers
    /// can `await` the native Apple Sign In sheet.
    private func performAppleSignIn() async throws -> ASAuthorizationCredential {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = AppleSignInDelegate(continuation: continuation)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            // Retain the delegate until the flow completes.
            objc_setAssociatedObject(controller, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            controller.performRequests()
        }
    }

    // MARK: - Sign out

    func signOut() async throws {
        authError = nil
        // Also sign out of Google so the next sign-in shows the account picker.
        GIDSignIn.sharedInstance.signOut()
        do {
            try await supabase.client.auth.signOut()
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Profile sync

    /// Ensure a profile row exists for the current user. First checks if the
    /// row already exists; only inserts if missing. This way we never clobber
    /// an existing display_name or settings. The DB trigger handle_new_user
    /// also creates the row on signup; this is a safety net.
    func ensureProfile() async throws {
        guard let uid = userId else { return }
        // Check if a profile already exists for this user.
        let existing: [Profile] = (try? await supabase.client
            .from("profiles")
            .select()
            .eq("id", value: uid)
            .execute()
            .value) ?? []
        if !existing.isEmpty { return }
        // Insert a new row only. If there's a race, the duplicate-key error
        // is harmless (the row already exists, which is what we want).
        do {
            try await supabase.client
                .from("profiles")
                .insert(ProfileNewRow(id: uid, email: email))
                .execute()
        } catch {
            print("Profile insert skipped (likely already exists): \(error)")
        }
    }
}

// MARK: - Errors

nonisolated enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case appleSignInFailed
    case googleSignInFailed
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Please enter a valid email address."
        case .weakPassword: return "Password must be at least 6 characters."
        case .appleSignInFailed: return "Sign in with Apple failed. Please try again."
        case .googleSignInFailed: return "Sign in with Google failed. Please try again."
        case .notSignedIn: return "You need to sign in first."
        }
    }
}

// MARK: - ASAuthorizationController delegate

/// Single-use delegate for the Apple Sign In flow. Bridges the callback-based
/// ASAuthorizationController API into an async continuation.
private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let continuation: CheckedContinuation<ASAuthorizationCredential, Error>

    init(continuation: CheckedContinuation<ASAuthorizationCredential, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation.resume(returning: authorization.credential)
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        continuation.resume(throwing: error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - Encodable helpers for Supabase

/// Minimal profile insert for first-time row creation. Only sets id + email;
/// all other columns use their DB defaults. Never used as an upsert, so it
/// won't overwrite an existing display_name.
nonisolated struct ProfileNewRow: Encodable, Sendable {
    let id: String
    let email: String?
}
