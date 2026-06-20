//
//  RecalibrateView.swift
//  Perch
//
//  Re-runs the calibration step from Settings.
//

import SwiftUI

struct RecalibrateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PerchStore.self) private var store
    @Environment(PostureSource.self) private var source

    @State private var confirmed = false

    var body: some View {
        ZStack {
            PerchBackground()
            VStack(spacing: Space.xl) {
                Spacer()
                Image(systemName: confirmed ? "checkmark.circle" : "scope")
                    .font(.system(size: 46, weight: .thin))
                    .foregroundStyle(Palette.sage)
                Text(confirmed ? "Baseline updated." : "Sit the way you'd\nlike to sit all day.")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text(confirmed
                     ? "Perch will measure from this new posture."
                     : "Get comfortable and upright, then capture your new baseline.")
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                Spacer()
                if !confirmed {
                    PerchPrimaryButton(title: "This is my good posture") {
                        source.calibrate()
                        store.setBaseline(0)
                        withAnimation { confirmed = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            dismiss()
                        }
                    }
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.xl)
        }
    }
}
