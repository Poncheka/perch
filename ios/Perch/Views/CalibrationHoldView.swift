//
//  CalibrationHoldView.swift
//  Perch
//
//  2D bubble-level calibration: a dot moves with live head pitch (vertical)
//  + roll (horizontal) inside a ring.  Yaw is intentionally ignored — turning
//  the head left/right does not move the bubble.
//
//  The user centers the dot and holds still; after a 0.6 s settle the
//  capturing phase begins.  A progress arc fills over ~3 s while the head
//  stays steady (2D variance below threshold).  If the user moves too much,
//  the arc resets.  On completion the `.captured` phase fires the callback.
//

import SwiftUI
import Combine

/// Phases of the hold-to-capture calibration flow.
enum CapturePhase: Equatable {
    case ready
    case capturing
    case captured
}

struct CalibrationHoldView: View {
    /// Live uncalibrated pitch from PostureSource (degrees).
    let livePitch: Double
    /// Live uncalibrated roll from PostureSource (degrees).
    let liveRoll: Double
    @Binding var phase: CapturePhase
    let onCaptured: () -> Void

    // MARK: - Tuning

    private let captureDuration: Double = 3.0       ///< Seconds the user must hold steady.
    private let settleDelay: Double = 0.6            ///< Seconds to settle before auto-capturing.
    private let varianceThreshold: Double = 1.8     ///< Max allowed 2D std-dev before reset.
    private let sampleWindow: Double = 0.8          ///< Seconds of samples in the variance window.
    private let dotRange: Double = 20               ///< ° range mapped across the bubble circle.
    private let ringRadius: CGFloat = 56            ///< Max dot offset from center in points.

    // MARK: - Internal state

    @State private var positionSamples: [CGPoint] = []
    @State private var elapsed: Double = 0

    private let tickInterval: Double = 0.08

    // Use a timer publisher for SwiftUI-idiomatic updates.
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: Space.l) {
            // Bubble-level ring
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Palette.hairline, lineWidth: 2)

                // Progress arc (fills as user holds steady)
                Circle()
                    .trim(from: 0, to: min(1, elapsed / captureDuration))
                    .stroke(
                        Palette.sage,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: tickInterval), value: elapsed)

                // Moving dot — 2D: horizontal from roll, vertical from pitch
                Circle()
                    .fill(Palette.sage)
                    .frame(width: 12, height: 12)
                    .offset(x: rollOffset, y: pitchOffset)
                    .animation(.easeInOut(duration: tickInterval), value: rollOffset)
                    .animation(.easeInOut(duration: tickInterval), value: pitchOffset)

                // Center crosshair (subtle)
                Circle()
                    .fill(Palette.sageSoft.opacity(0.5))
                    .frame(width: 6, height: 6)

                // Captured checkmark
                if phase == .captured {
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Palette.sage)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 160, height: 160)

            // Instructional text
            Text(captureLabel)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .animation(.easeInOut(duration: 0.3), value: captureLabel)
        }
        .onAppear {
            // Auto-transition from .ready to .capturing after a short settle
            // so the arc actually begins filling without requiring an extra tap.
            if phase == .ready {
                DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
                    if phase == .ready {
                        phase = .capturing
                    }
                }
            }
        }
        .onChange(of: phase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
        .onReceive(timer) { _ in
            guard phase == .capturing else { return }
            sampleTick()
        }
    }

    // MARK: - 2D dot position

    /// Horizontal offset from roll (head tilt toward shoulder).
    private var rollOffset: CGFloat {
        let clamped = max(-dotRange, min(dotRange, liveRoll))
        let fraction = clamped / dotRange
        return fraction * ringRadius
    }

    /// Vertical offset from pitch (head tilt forward/back).
    /// Positive pitch (head drooping forward) moves the dot downward.
    private var pitchOffset: CGFloat {
        let clamped = max(-dotRange, min(dotRange, livePitch))
        let fraction = clamped / dotRange
        return fraction * ringRadius
    }

    /// Current 2D dot position in the ring coordinate system.
    private var currentPosition: CGPoint {
        CGPoint(x: rollOffset, y: pitchOffset)
    }

    // MARK: - Labels

    private var captureLabel: String {
        switch phase {
        case .ready: return "Hold your head still"
        case .capturing: return "Keep holding…"
        case .captured: return "Captured"
        }
    }

    // MARK: - State machine

    private func handlePhaseChange(_ newPhase: CapturePhase) {
        switch newPhase {
        case .ready:
            reset()
        case .capturing:
            startCapturing()
        case .captured:
            break
        }
    }

    private func reset() {
        positionSamples.removeAll()
        elapsed = 0
    }

    private func startCapturing() {
        positionSamples.removeAll()
        elapsed = 0

        // Seed samples from the current position so variance starts low.
        let seed = currentPosition
        let count = Int(sampleWindow / tickInterval)
        positionSamples = Array(repeating: seed, count: count)
    }

    // MARK: - 2D steadiness check

    private func sampleTick() {
        // Add new sample, prune old.
        positionSamples.append(currentPosition)
        let maxCount = Int(sampleWindow / tickInterval)
        if positionSamples.count > maxCount {
            positionSamples.removeFirst(positionSamples.count - maxCount)
        }

        guard positionSamples.count >= 2 else {
            elapsed += tickInterval
            return
        }

        // 2D variance: mean squared distance from the mean position.
        let meanX = positionSamples.map(\.x).reduce(0, +) / CGFloat(positionSamples.count)
        let meanY = positionSamples.map(\.y).reduce(0, +) / CGFloat(positionSamples.count)
        let variance = positionSamples.map { pt -> CGFloat in
            let dx = pt.x - meanX
            let dy = pt.y - meanY
            return dx * dx + dy * dy
        }.reduce(0, +) / CGFloat(positionSamples.count)
        let stdDev = sqrt(Double(variance))

        if stdDev < varianceThreshold {
            elapsed += tickInterval
            if elapsed >= captureDuration {
                phase = .captured
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onCaptured()
            }
        } else {
            // Head moved too much — reset progress.
            elapsed = 0
        }
    }
}
