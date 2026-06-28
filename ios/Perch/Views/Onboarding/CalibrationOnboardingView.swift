//
//  CalibrationOnboardingView.swift
//  Perch
//
//  A calm, one-time calibration step shown AFTER Motion & Fitness permission
//  and BEFORE the paywall. The user sits as they'd like to sit all day, holds
//  their head steady while a circular progress arc fills. On completion, the
//  baseline is set. The user can then "Continue" to the paywall or "Re-do"
//  to recapture. A "Skip for now" fallback is always available.
//

import SwiftUI

struct CalibrationOnboardingView: View {
    let onComplete: () -> Void

    @Environment(PerchStore.self) private var store
    @Environment(PostureSource.self) private var source

    @State private var capturePhase: CapturePhase = .ready

    var body: some View {
        ZStack {
            PerchBackground()

            VStack(spacing: Space.xxl) {
                Spacer()

                VStack(spacing: Space.l) {
                    Image(systemName: calibrationIcon)
                        .font(.system(size: 46, weight: .thin))
                        .foregroundStyle(Palette.sage)
                        .frame(height: 64)

                    Text(calibrationTitle)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)

                    Text(calibrationSubtitle)
                        .font(.system(.body, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                CalibrationHoldView(
                    liveAngle: source.liveRawTilt,
                    phase: $capturePhase,
                    onCaptured: {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        source.calibrate()
                        store.setBaseline(source.liveRawTilt)
                        store.completeCalibration()
                    }
                )
                .frame(width: 200, height: 200)

                // Show Continue + Re-do after successful capture.
                // Keep "Skip for now" as a secondary fallback when not yet captured.
                if capturePhase == .captured {
                    VStack(spacing: Space.m) {
                        PerchPrimaryButton(title: "Continue") {
                            onComplete()
                        }
                        PerchTextButton(title: "Re-do", color: Palette.sage) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                capturePhase = .ready
                            }
                        }
                    }
                } else {
                    PerchTextButton(title: "Skip for now", color: Palette.mist) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        source.calibrate()
                        store.setBaseline(source.liveRawTilt)
                        store.completeCalibration()
                        onComplete()
                    }
                    .padding(.top, Space.m)
                }

                Spacer()
            }
            .padding(.horizontal, Space.xl)
        }
    }

    private var calibrationIcon: String {
        switch capturePhase {
        case .ready: return "figure.seated.side"
        case .capturing: return "scope"
        case .captured: return "checkmark.circle"
        }
    }

    private var calibrationTitle: String {
        switch capturePhase {
        case .ready: return "Sit the way you'd\nlike to sit all day."
        case .capturing: return "Hold steady…"
        case .captured: return "Perfectly set."
        }
    }

    private var calibrationSubtitle: String {
        switch capturePhase {
        case .ready:
            return "Get comfortable and upright. Then hold your head still — the ring fills when you're steady."
        case .capturing:
            return "Almost there. Keep your head still just a moment longer."
        case .captured:
            return "That's your good posture. Perch will gently let you know whenever you drift away from it."
        }
    }
}
