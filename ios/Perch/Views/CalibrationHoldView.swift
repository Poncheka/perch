//
//  CalibrationHoldView.swift
//  Perch
//
//  Hold-to-capture calibration: a bubble-level dot moves with live head angle.
//  The user centers it and holds still while a circular progress arc fills over
//  ~3 seconds. If angle variance exceeds a small threshold, the arc resets.
//  On completion, fires the `onCaptured` callback.
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
    /// Live uncalibrated angle from PostureSource (degrees).
    let liveAngle: Double
    @Binding var phase: CapturePhase
    let onCaptured: () -> Void

    // MARK: - Tuning

    private let captureDuration: Double = 3.0       ///< Seconds the user must hold steady.
    private let varianceThreshold: Double = 1.2     ///< Max allowed ° variance before reset.
    private let sampleWindow: Double = 0.8          ///< Seconds of samples in the variance window.
    private let dotRange: Double = 20               ///< ° range mapped across the bubble circle.

    // MARK: - Internal state

    @State private var samples: [Double] = []
    @State private var elapsed: Double = 0
    @State private var tick = 0

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

                // Moving dot — horizontal position reflects live angle
                Circle()
                    .fill(Palette.sage)
                    .frame(width: 12, height: 12)
                    .offset(x: dotOffset)
                    .animation(.easeInOut(duration: tickInterval), value: dotOffset)

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
        .onChange(of: phase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
        .onReceive(timer) { _ in
            guard phase == .capturing else { return }
            sampleTick()
        }
    }

    // MARK: - Helpers

    private var dotOffset: CGFloat {
        let clamped = max(-dotRange, min(dotRange, liveAngle))
        let fraction = clamped / dotRange
        return fraction * 56
    }

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
        samples.removeAll()
        elapsed = 0
    }

    private func startCapturing() {
        samples.removeAll()
        elapsed = 0

        // Seed samples from the current angle so variance starts low.
        samples = Array(repeating: liveAngle, count: Int(sampleWindow / tickInterval))
    }

    private func sampleTick() {
        // Add new sample, prune old.
        samples.append(liveAngle)
        let maxCount = Int(sampleWindow / tickInterval)
        if samples.count > maxCount {
            samples.removeFirst(samples.count - maxCount)
        }

        guard samples.count >= 2 else {
            elapsed += tickInterval
            return
        }

        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.map({ ($0 - mean) * ($0 - mean) }).reduce(0, +) / Double(samples.count)
        let stdDev = sqrt(variance)

        if stdDev < varianceThreshold {
            elapsed += tickInterval
            if elapsed >= captureDuration {
                phase = .captured
                onCaptured()
            }
        } else {
            elapsed = 0
        }
    }
}
