//
//  CirclesView.swift
//  Perch
//
//  Oura-style shared circles. When not signed in, shows sign-in options
//  directly on this page (Apple + Google) — no two-step prompt → sheet.
//  When signed in, lists circles and offers Create / Join actions.
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct CirclesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PerchStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(Database.self) private var db

    @State private var userCircles: [CircleModel] = []
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showNamePrompt = false
    @State private var displayName = ""
    @State private var working = false
    @State private var signInError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                PerchBackground()
                if !auth.isSignedIn {
                    signInPage
                } else if showNamePrompt {
                    namePromptPage
                } else if userCircles.isEmpty {
                    emptyState
                } else {
                    circleList
                }
            }
            .navigationTitle("Circles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreate) { CreateCircleView() }
            .sheet(isPresented: $showJoin) { JoinCircleView() }
            .task { await loadCircles() }
            .onChange(of: auth.isSignedIn) { _, _ in
                Task { await loadCircles() }
            }
        }
    }

    private func loadCircles() async {
        guard let uid = auth.userId else { userCircles = []; return }
        userCircles = await db.circlesForUser(uid)
    }

    // MARK: - Sign-in page (Apple + Google on one page)

    private var signInPage: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Palette.sage)
            VStack(spacing: Space.s) {
                Text("Sign in for Circles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Share your posture journey with a small, supportive group. Sign in to create or join a circle.")
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            if let error = signInError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.amber)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Space.m) {
                if working {
                    HStack(spacing: Space.s) {
                        ProgressView()
                            .tint(Palette.sage)
                        Text("Signing in…")
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

    // MARK: - Name prompt (shown after first sign-in)

    private var namePromptPage: some View {
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
                showNamePrompt = false
            }

            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }

    // MARK: - Sign-in buttons

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
            signInError = nil

            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else {
                signInError = "Unable to present sign-in."
                working = false
                return
            }
            let topVC = topMostViewController(from: rootVC)

            do {
                try await auth.signInWithGoogle(presenting: topVC)
                try? await auth.ensureProfile()
                await store.loadFromSupabase()

                if store.profile.displayName?.isEmpty == false {
                    // Already has a name — done.
                } else {
                    await MainActor.run { showNamePrompt = true }
                }
            } catch {
                await MainActor.run {
                    signInError = error.localizedDescription
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
                    signInError = "Apple Sign In failed — no identity token received."
                    return
                }

                working = true
                signInError = nil

                try await auth.signInWithAppleToken(idToken)
                try? await auth.ensureProfile()
                await store.loadFromSupabase()

                if store.profile.displayName?.isEmpty == false {
                    // Already has a name — done.
                } else {
                    let parts = [
                        credential.fullName?.givenName,
                        credential.fullName?.familyName
                    ].compactMap { $0 }.filter { !$0.isEmpty }
                    let appleName = parts.joined(separator: " ")

                    await MainActor.run {
                        displayName = appleName.isEmpty ? "" : appleName
                        showNamePrompt = true
                    }
                }
            } catch {
                await MainActor.run {
                    signInError = error.localizedDescription
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
        showNamePrompt = false
    }

    private func topMostViewController(from root: UIViewController) -> UIViewController {
        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }

    // MARK: - Empty state (signed in, no circles)

    private var emptyState: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Palette.sage)
            VStack(spacing: Space.s) {
                Text("No circles yet")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Create one and invite a friend, or join theirs with a code.")
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            HStack(spacing: Space.l) {
                PerchPrimaryButton(title: "Create") { showCreate = true }
                PerchTextButton(title: "Join with code", color: Palette.sage) { showJoin = true }
            }
            .padding(.top, Space.s)
            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }

    // MARK: - Circle list (signed in, has circles)

    private var circleList: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                HStack(spacing: Space.l) {
                    Spacer()
                    PerchTextButton(title: "Create", color: Palette.sage) { showCreate = true }
                    PerchTextButton(title: "Join", color: Palette.sage) { showJoin = true }
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.s)

                ForEach(userCircles) { circle in
                    NavigationLink {
                        CircleDetailView(circle: circle)
                    } label: {
                        circleRow(circle)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Space.xl)
            }
            .padding(.bottom, Space.xl)
        }
    }

    private func circleRow(_ circle: CircleModel) -> some View {
        HStack(spacing: Space.l) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.sage)

            VStack(alignment: .leading, spacing: 2) {
                Text(circle.name)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(ownerLabel(circle))
                    .font(.footnote)
                    .foregroundStyle(Palette.mist)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.mist)
        }
        .padding(Space.l)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
    }

    private func ownerLabel(_ circle: CircleModel) -> String {
        circle.ownerId == (auth.userId ?? "") ? "You created this circle" : "Member"
    }
}
