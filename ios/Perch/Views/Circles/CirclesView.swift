//
//  CirclesView.swift
//  Perch
//
//  Oura-style shared circles. Requires sign-in. Lists circles the user belongs
//  to, and offers Create / Join actions. Supportive, not competitive.
//

import SwiftUI

struct CirclesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PerchStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(Database.self) private var db

    @State private var userCircles: [CircleModel] = []
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showSignIn = false

    var body: some View {
        NavigationStack {
            ZStack {
                PerchBackground()
                if !auth.isSignedIn {
                    signInPrompt
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
            .sheet(isPresented: $showSignIn) { AccountSignInView() }
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

    // MARK: - Sign-in prompt

    private var signInPrompt: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Palette.sage)
            VStack(spacing: Space.s) {
                Text("Sign in for Circles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Share your posture journey with a small, supportive group. Sign in to create or join a circle.")
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            PerchPrimaryButton(title: "Sign in") { showSignIn = true }
                .padding(.top, Space.s)
            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }

    // MARK: - Empty state

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

    // MARK: - Circle list

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
