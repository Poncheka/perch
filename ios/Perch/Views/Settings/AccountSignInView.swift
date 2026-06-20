//
//  AccountSignInView.swift
//  Perch
//
//  Quiet email sign-in. Mirrors a Supabase email flow through AuthService.
//

import SwiftUI

struct AccountSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(PerchStore.self) private var store

    @State private var email = ""
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
                    Text("Sync across devices")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Sign in to keep your posture history safe.")
                        .font(.body)
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                }

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

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Palette.amber)
                }

                PerchPrimaryButton(title: working ? "Signing in…" : "Continue") {
                    Task { await signIn() }
                }
                .disabled(working)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, Space.xl)
        }
    }

    private func signIn() async {
        working = true
        error = nil
        do {
            try await auth.signIn(email: email)
            store.profile.email = auth.email
            store.saveProfile()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        working = false
    }
}
