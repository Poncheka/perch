//
//  RecalibrateView.swift
//  Perch
//
//  Re-runs the calibration step from Settings using the hold-to-capture
//  interaction: a bubble-level dot, steady-hold progress arc, and success
//  haptic. Matches the first-run calibration flow on Home.
//

import SwiftUI

struct RecalibrateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PerchStore.self) private var store
    @Environment(PostureSource.self) private var source

    @State private var capturePhase: CapturePhase = .ready

    var body: some View {
        ZStack {
            PerchBackground()
            VStack(spacing: Space.xl) {
                Spacer()
                Image(systemName: capturePhase == .captured ? "checkmark.circle" : "scope")
                    .font(.system(size: 46, weight: .thin))
                    .foregroundStyle(Palette.sage)
                Text(capturePhase == .captured
                     ? "Baseline updated."
                     : "Sit the way you'd\nlike to sit all day.")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text(capturePhase == .captured
                     ? "Perch will measure from this new posture."
                     : "Get comfortable and upright. Hold your head still — the ring fills when you're steady.")
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)

                CalibrationHoldView(
                    liveAngle: source.liveRawTilt,
                    phase: $capturePhase,
                    onCaptured: {
                        source.calibrate()
                        store.setBaseline(0)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        Task {
                            try? await Task.sleep(for: .seconds(1.0))
                            dismiss()
                        }
                    }
                )
                .frame(width: 180, height: 180)

                Spacer()
            }
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.xl)
        }
    }
}
