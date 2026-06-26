//
//  AccountSignInView.swift
//  Perch
//
//  Supabase email + password sign-in / sign-up. Quiet, minimal.
//

import SwiftUI

struct AccountSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(Database.self) private var db
    @Environment(PerchStore.self) private var store

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        ZStack {
            PerchBackground()
            VStack(spacing: Space.xl) {
                Spacer()
                Image(systemName: "envelope")
                    .font(.system(size: 42, weight: .thin))
                    .foregroundStyle(Palette.sage)
                VStack(spacing: Space.s) {
                    Text(isSignUp ? "Create your account" : "Sync across devices")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(isSignUp
                         ? "Sign up to keep your posture history safe."
                         : "Sign in to keep your posture history safe.")
                        .font(.body)
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                }

                // Email field
                TextField("you@email.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(Space.l)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Palette.surface)
                    )

                // Password field
                SecureField("Password", text: $password)
                    .textContentType(isSignUp ? .newPassword : .password)
                    .padding(Space.l)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Palette.surface)
                    )

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Palette.amber)
                        .multilineTextAlignment(.center)
                }

                PerchPrimaryButton(title: working ? "Please wait…" : (isSignUp ? "Sign up" : "Sign in")) {
                    Task { await submit() }
                }
                .disabled(working || email.isEmpty || password.isEmpty)

                // Toggle between sign-in and sign-up
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isSignUp.toggle()
                        error = nil
                    }
                } label: {
                    Text(isSignUp
                         ? "Already have an account? Sign in"
                         : "New here? Create an account")
                        .font(.footnote)
                        .foregroundStyle(Palette.sage)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, Space.xl)
        }
    }

    private func submit() async {
        working = true
        error = nil
        do {
            if isSignUp {
                try await auth.signUp(email: email, password: password)
                // After sign-up, ensure the profile row exists.
                try? await auth.ensureProfile()
            } else {
                try await auth.signIn(email: email, password: password)
            }
            // Load Supabase data into the store.
            await store.loadFromSupabase()
            store.profile.email = auth.email
            store.saveProfile()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        working = false
    }
}
