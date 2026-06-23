//
//  CreateCircleView.swift
//  Perch
//
//  Name a circle, generate an invite code, and share it with a friend.
//

import SwiftUI

struct CreateCircleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(PerchStore.self) private var store

    @State private var name = ""
    @State private var createdCircle: CircleModel?
    @State private var showShare = false

    private let db = Database()

    var body: some View {
        NavigationStack {
            ZStack {
                PerchBackground()
                if let circle = createdCircle {
                    createdState(circle)
                } else {
                    createForm
                }
            }
            .navigationTitle("New circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Create form

    private var createForm: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(Palette.sage)
            VStack(spacing: Space.s) {
                Text("Name your circle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Pick a name your friends will recognize.")
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }

            TextField("e.g. Desk crew, Yoga gang", text: $name)
                .padding(Space.l)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Palette.surface)
                )

            PerchPrimaryButton(title: "Create circle") {
                createCircle()
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }

    // MARK: - Created state

    private func createdState(_ circle: CircleModel) -> some View {
        VStack(spacing: Space.xl) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Palette.sage)
            VStack(spacing: Space.s) {
                Text("\(circle.name)\nis ready.")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text("Share the invite code below with a friend so they can join.")
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }

            // Invite code display.
            VStack(spacing: Space.s) {
                Eyebrow(text: "Invite code")
                Text(circle.inviteCode)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.sage)
                    .tracking(6)
            }
            .padding(Space.xl)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.surface)
                    .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
            )

            PerchPrimaryButton(title: "Invite a friend") {
                showShare = true
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(activityItems: [
                    "Join my Perch circle \"\(circle.name)\"! Use invite code \(circle.inviteCode) or download Perch: https://perch.app"
                ])
                .presentationDetents([.medium])
            }

            PerchTextButton(title: "Done", color: Palette.mist) {
                dismiss()
            }

            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }

    private func createCircle() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let email = auth.email else { return }
        let circle = CircleModel.make(name: trimmed, ownerId: email)
        db.saveCircle(circle)
        let membership = CircleMember.make(circleId: circle.id, userId: email, role: .owner)
        db.saveCircleMember(membership)
        withAnimation { createdCircle = circle }
    }
}
