//
//  AccountSignInView.swift
//  Perch
//
//  Sign in with Apple or Google via Supabase Auth. After the first sign-in,
//  lets the user set or confirm a display_name — the name their circle-mates
//  see. All posture tracking remains fully anonymous / local until the user
//  signs in for Circles.
//

import SwiftUI
import AuthenticationServices

struct AccountSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(Database.self) private var db
    @Environment(PerchStore.self) private var store

    @State private var working = false
    @State private var error: String?
    @State private var displayName = ""
    @State private var showNamePrompt = false
    @State private var authMethod: AuthMethod?

    var body: some View {
        ZStack {
            PerchBackground()
            if showNamePrompt {
                namePrompt
            } else {
                signInContent
            }
        }
    }

    // MARK: - Sign in

    private var signInContent: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Palette.sage)
            VStack(spacing: Space.s) {
                Text("Sign in for Circles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Sign in to create or join a posture circle. Your daily score and streak will be visible to circle members.")
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: Space.m) {
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Palette.amber)
                        .multilineTextAlignment(.center)
                }

                if working {
                    HStack(spacing: Space.s) {
                        ProgressView()
                            .tint(Palette.sage)
                        Text(authMethod == .google ? "Signing in with Google…" : "Signing in with Apple…")
                            .font(.subheadline)
                            .foregroundStyle(Palette.mist)
                    }
                } else {
                    googleButton
                    appleButton
                }
            }

            Text("Your posture data stays on your phone until you sign in. Only your daily score and streak are shared with circles you join.")
                .font(.caption)
                .foregroundStyle(Palette.mist)
                .multilineTextAlignment(.center)
                .padding(.top, Space.s)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }

    // MARK: - Display name prompt

    private var namePrompt: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(Palette.sage)
            VStack(spacing: Space.s) {
                Text("Your display name")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("This is the name your circle-mates will see. You can change it later in Settings.")
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            TextField("Your name", text: $displayName)
                .textContentType(.name)
                .padding(Space.l)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Palette.surface)
                )

            PerchPrimaryButton(title: "Continue") {
                saveDisplayName()
            }
            .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            PerchTextButton(title: "Skip for now", color: Palette.mist) {
                finishSignIn()
            }

            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }

    // MARK: - Buttons

    private var googleButton: some View {
        Button {
            handleGoogleSignIn()
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "g.circle.fill")
                    .font(.title3)
                Text("Continue with Google")
                    .font(.system(.headline, design: .default, weight: .semibold))
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handleAppleResult(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(.rect(cornerRadius: Radius.control))
    }

    // MARK: - Actions

    private func handleGoogleSignIn() {
        Task {
            working = true
            authMethod = .google
            error = nil
            do {
                try await auth.signInWithGoogle()
                try? await auth.ensureProfile()
                await store.loadFromSupabase()

                if store.profile.displayName?.isEmpty == false {
                    finishSignIn()
                } else {
                    await MainActor.run { showNamePrompt = true }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
            await MainActor.run { working = false }
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        Task {
            do {
                let authorization = try result.get()
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let idTokenData = credential.identityToken,
                      let idToken = String(data: idTokenData, encoding: .utf8) else {
                    error = "Apple Sign In failed — no identity token received."
                    return
                }

                working = true
                authMethod = .apple
                error = nil

                // Exchange the Apple ID token with Supabase (no redundant ASAuthorizationController).
                try await auth.signInWithAppleToken(idToken)

                // Ensure profile exists, then load Supabase data.
                try? await auth.ensureProfile()
                await store.loadFromSupabase()

                // If profile has a display_name already, skip the prompt.
                if store.profile.displayName?.isEmpty == false {
                    finishSignIn()
                    return
                }

                // Pre-fill from Apple's fullName (only provided on first sign-in).
                let parts = [
                    credential.fullName?.givenName,
                    credential.fullName?.familyName
                ].compactMap { $0 }.filter { !$0.isEmpty }
                let appleName = parts.joined(separator: " ")

                await MainActor.run {
                    displayName = appleName.isEmpty ? "" : appleName
                    showNamePrompt = true
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
            await MainActor.run { working = false }
        }
    }

    private func saveDisplayName() {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.profile.displayName = trimmed
        store.saveProfile()
        finishSignIn()
    }

    private func finishSignIn() {
        dismiss()
    }

    // MARK: - Types

    private enum AuthMethod {
        case apple
        case google
    }
}
