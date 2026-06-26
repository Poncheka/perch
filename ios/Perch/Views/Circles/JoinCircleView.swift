//
//  JoinCircleView.swift
//  Perch
//
//  Enter a 6-character invite code to join a friend's circle. Uses the
//  `join_circle_by_code(p_code)` RPC. Shows a clear one-line consent note
//  when joining.
//

import SwiftUI

struct JoinCircleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(Database.self) private var db

    @State private var code = ""
    @State private var working = false
    @State private var error: String?
    @State private var joinedCircle: CircleModel?

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
                    let filtered = newValue.uppercased().filter { $0.isLetter || $0.isNumber }
                    if filtered.count <= 6 { code = filtered }
                }

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.amber)
                    .multilineTextAlignment(.center)
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
                Task { await doJoin() }
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
                Text("Your circle is ready. You'll see each other's posture progress below.")
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
            PerchPrimaryButton(title: "Done") { dismiss() }
            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }

    private func doJoin() async {
        working = true
        error = nil
        do {
            let circle = try await db.joinCircleByCode(code)
            await MainActor.run {
                withAnimation { joinedCircle = circle }
            }
        } catch let err {
            await MainActor.run {
                error = err.localizedDescription
            }
        }
        await MainActor.run { working = false }
    }
}
