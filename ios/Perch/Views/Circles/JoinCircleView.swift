//
//  JoinCircleView.swift
//  Perch
//
//  Enter a 6-character invite code to join a friend's circle. Shows a clear
//  one-line consent note when joining.
//

import SwiftUI

struct JoinCircleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

    @State private var code = ""
    @State private var working = false
    @State private var error: String?
    @State private var joinedCircle: CircleModel?

    private let db = Database()

    var body: some View {
        NavigationStack {
            ZStack {
                PerchBackground()
                if let circle = joinedCircle {
                    joinedState(circle)
                } else {
                    joinForm
                }
            }
            .navigationTitle("Join a circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Join form

    private var joinForm: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            Image(systemName: "envelope")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(Palette.sage)
            VStack(spacing: Space.s) {
                Text("Enter invite code")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Ask a friend for their 6-letter circle code.")
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }

            TextField("ABCDEF", text: $code)
                .font(.system(.title2, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .padding(Space.l)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Palette.surface)
                )
                .onChange(of: code) { _, newValue in
                    // Auto-uppercase and limit to 6 chars.
                    let filtered = newValue.uppercased().filter { $0.isLetter || $0.isNumber }
                    if filtered.count <= 6 { code = filtered }
                }

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.amber)
            }

            // Consent note.
            VStack(spacing: Space.s) {
                Image(systemName: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(Palette.mist)
                Text("Your daily posture score and streak will be visible to members of this circle.")
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Space.s)

            PerchPrimaryButton(title: working ? "Joining…" : "Join circle") {
                Task { await join() }
            }
            .disabled(code.count < 6 || working)

            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }

    // MARK: - Joined state

    private func joinedState(_ circle: CircleModel) -> some View {
        VStack(spacing: Space.xl) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Palette.sage)
            VStack(spacing: Space.s) {
                Text("You're in\n\(circle.name).")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text("Your circle is ready. You'll see each other's posture progress right on the Home screen.")
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
            PerchPrimaryButton(title: "Done") { dismiss() }
            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }

    private func join() async {
        working = true
        error = nil
        // Simulate a brief network round-trip.
        try? await Task.sleep(for: .milliseconds(600))

        guard let email = auth.email else {
            error = "Please sign in first."
            working = false
            return
        }

        guard let circle = db.findCircleByInviteCode(code) else {
            error = "No circle found with that code. Check the spelling and try again."
            working = false
            return
        }

        // Check user isn't already a member.
        let existing = db.loadMembers(for: circle.id)
        if existing.contains(where: { $0.userId == email }) {
            withAnimation { joinedCircle = circle }
            working = false
            return
        }

        let membership = CircleMember.make(circleId: circle.id, userId: email, role: .member)
        db.saveCircleMember(membership)
        withAnimation { joinedCircle = circle }
        working = false
    }
}
