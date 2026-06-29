//
//  CalibrationHoldView.swift
//  Perch
//
//  A polished, sensor-reactive "find your center, then hold" calibration.
//  Think Face ID enrollment meets a spirit level meets a camera-scan ring.
//
//  The bubble moves in 2D inside a large ring — horizontal from head ROLL,
//  vertical from PITCH (yaw ignored). Center the dot and hold still; a
//  progress arc sweeps from 12 o'clock, filling over 3 seconds. Haptic ticks
//  at 25/50/75%. If you drift, the arc unwinds smoothly. On completion a
//  checkmark draws itself in the center via stroke-trim animation.
//
//  Magnet assist: within ~1.3× the center zone, the rendered dot eases
//  slightly toward exact center so docking feels satisfying (visual only —
//  steadiness is always computed from the true sensor position).
//
//  Live-data gate: if no motion samples have arrived recently, the arc
//  never fills. The UI shows "Waiting for AirPods…" instead of the copy.
//

import SwiftUI
import Combine

enum CapturePhase: Equatable {
    /// Bubble outside the center zone — amber, "Center your head."
    case aligning
    /// Bubble inside center zone + steady — sage, progress arc fills.
    case holding
    /// Calibration complete — checkmark drawn, "Calibrated."
    case captured
}

/// A simple checkmark path designed for stroke-trim animation.
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.18, y: h * 0.52))
        path.addLine(to: CGPoint(x: w * 0.44, y: h * 0.78))
        path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.20))
        return path
    }
}

struct CalibrationHoldView: View {
    /// Live uncalibrated pitch from PostureSource (degrees).
    let livePitch: Double
    /// Live uncalibrated roll from PostureSource (degrees).
    let liveRoll: Double
    /// Timestamp of the most recent live motion sample. Used to detect
    /// whether the sensor is actually streaming vs. a frozen/zero signal.
    let lastMotionTimestamp: Date?

    @Binding var phase: CapturePhase
    /// Called when the 3-second hold completes (before checkmark animation).
    /// Parent should call source.calibrate() here to capture the baseline.
    let onCaptured: () -> Void

    // MARK: - Tuning

    private let ringDiameter: CGFloat = 220
    private let ringRadius: CGFloat = 88          ///< Max dot offset from center (pts).
    private let dotSize: CGFloat = 16
    private let dotRange: Double = 20             ///< ° of sensor mapped to ring radius.
    private let captureDuration: Double = 3.0     ///< Seconds the user must hold steady.
    private let varianceThreshold: Double = 1.8   ///< Max 2D std-dev before reset.
    private let sampleWindow: Double = 0.8        ///< Seconds of samples in the window.
    private let tickInterval: Double = 0.08
    private let centerZoneRadius: CGFloat = 31    ///< ringRadius * ~0.35
    private let magnetZoneRadius: CGFloat = 40    ///< centerZoneRadius * ~1.3
    private let staleThreshold: Double = 1.5      ///< Seconds without fresh data → "Waiting".
    private let settleDuration: Double = 0.5      ///< Seconds of steady+centered before holding.

    // MARK: - Internal state

    @State private var positionSamples: [CGPoint] = []
    @State private var elapsed: Double = 0
    @State private var steadyTime: Double = 0     ///< Accumulated seconds of center+steady.
    @State private var checkmarkProgress: Double = 0
    @State private var checkmarkScale: Double = 0.3
    @State private var lastHapticTick: Int = 0    ///< 0=none, 1=25%, 2=50%, 3=75%

    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    // MARK: - Computed helpers

    /// True when the most recent motion sample is fresh enough.
    private var hasLiveData: Bool {
        guard let ts = lastMotionTimestamp else { return false }
        return Date().timeIntervalSince(ts) < staleThreshold
    }

    /// Raw 2D position from sensor (no magnet assist).
    private var sensorPosition: CGPoint {
        let clampedPitch = max(-dotRange, min(dotRange, livePitch))
        let clampedRoll = max(-dotRange, min(dotRange, liveRoll))
        return CGPoint(
            x: (clampedRoll / dotRange) * ringRadius,
            y: (clampedPitch / dotRange) * ringRadius
        )
    }

    /// Distance from center in points.
    private var distanceFromCenter: CGFloat {
        let p = sensorPosition
        return sqrt(p.x * p.x + p.y * p.y)
    }

    /// Rendered position with magnet assist applied (visual only).
    private var renderedPosition: CGPoint {
        let raw = sensorPosition
        let dist = distanceFromCenter
        guard dist < magnetZoneRadius, dist > 0.5 else { return raw }
        let blend = 1.0 - (dist / magnetZoneRadius)
        let eased = blend * blend
        return CGPoint(x: raw.x * (1 - eased), y: raw.y * (1 - eased))
    }

    /// Opacity of the center home target (brightens as bubble approaches).
    private var homeTargetOpacity: Double {
        if phase == .captured { return 0 }
        let dist = distanceFromCenter
        if dist <= centerZoneRadius { return 0.5 }
        let range = magnetZoneRadius - centerZoneRadius
        let extra = dist - centerZoneRadius
        return max(0.12, 0.5 - 0.38 * (extra / range))
    }

    /// Whether the bubble is inside the center zone.
    private var isInCenterZone: Bool {
        distanceFromCenter <= centerZoneRadius
    }

    /// Dot color: amber when aligning, sage when holding.
    private var dotColor: Color {
        phase == .holding ? Palette.sage : Palette.amber
    }

    /// The progress fraction (0…1) for the arc.
    private var progressFraction: CGFloat {
        CGFloat(min(1, elapsed / captureDuration))
    }

    /// Copy under the ring.
    private var copyText: String {
        if !hasLiveData { return "Waiting for AirPods…" }
        switch phase {
        case .aligning: return "Center your head."
        case .holding: return "Hold steady…"
        case .captured: return "Calibrated."
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Ring + bubble + checkmark
            ringContent
                .frame(width: ringDiameter, height: ringDiameter)

            // Instructional copy
            Text(copyText)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(phase == .captured ? Palette.sage : Palette.inkSoft)
                .animation(.easeInOut(duration: 0.3), value: copyText)
        }
        .onAppear { handleAppear() }
        .onChange(of: phase) { _, newPhase in handlePhaseChange(newPhase) }
        .onReceive(timer) { _ in sampleTick() }
    }

    // MARK: - Ring content

    @ViewBuilder
    private var ringContent: some View {
        ZStack {
            // Outer hairline track that breathes while holding.
            Circle()
                .stroke(Palette.hairline, lineWidth: 2)
                .scaleEffect(phase == .holding ? 1.02 : 1)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: phase == .holding)

            // Progress arc — sweeps from 12 o'clock.
            if phase == .holding || (phase == .aligning && elapsed > 0) {
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(
                        Palette.sage,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: tickInterval), value: progressFraction)
                    // Glow on the leading edge while filling.
                    .shadow(color: Palette.sage.opacity(0.4), radius: 6)
            }

            // Center home target — crosshair + small dot.
            if phase != .captured {
                centerTarget
                    .opacity(homeTargetOpacity)
                    .animation(.easeInOut(duration: 0.3), value: homeTargetOpacity)
            }

            // Glow halo behind the bubble.
            if phase != .captured {
                Circle()
                    .fill(dotColor.opacity(0.25))
                    .frame(width: 34, height: 34)
                    .blur(radius: 14)
                    .offset(x: renderedPosition.x, y: renderedPosition.y)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: renderedPosition.x)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: renderedPosition.y)
            }

            // Live bubble dot.
            if phase != .captured {
                Circle()
                    .fill(dotColor)
                    .frame(width: dotSize, height: dotSize)
                    .offset(x: renderedPosition.x, y: renderedPosition.y)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: renderedPosition.x)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: renderedPosition.y)
            }

            // Checkmark drawn in center on capture.
            if phase == .captured {
                CheckmarkShape()
                    .trim(from: 0, to: checkmarkProgress)
                    .stroke(
                        Palette.sage,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 36, height: 28)
                    .scaleEffect(checkmarkScale)
            }
        }
    }

    /// Small inner circle + crosshair, pulsing softly.
    private var centerTarget: some View {
        Circle()
            .fill(Palette.sage.opacity(0.4))
            .frame(width: 8, height: 8)
            .overlay {
                Path { path in
                    path.move(to: CGPoint(x: -16, y: 0))
                    path.addLine(to: CGPoint(x: 16, y: 0))
                    path.move(to: CGPoint(x: 0, y: -16))
                    path.addLine(to: CGPoint(x: 0, y: 16))
                }
                .stroke(Palette.sage.opacity(0.3), lineWidth: 1)
            }
    }

    // MARK: - Lifecycle

    private func handleAppear() {
        if phase == .aligning {
            reset()
        }
    }

    private func handlePhaseChange(_ newPhase: CapturePhase) {
        switch newPhase {
        case .aligning:
            reset()
        case .holding:
            startHolding()
        case .captured:
            playCapturedAnimation()
        }
    }

    private func reset() {
        positionSamples.removeAll()
        elapsed = 0
        steadyTime = 0
        lastHapticTick = 0
    }

    private func startHolding() {
        positionSamples.removeAll()
        elapsed = 0
        steadyTime = 0
        lastHapticTick = 0
        // Seed samples from current position so variance starts low.
        let seed = sensorPosition
        let count = Int(sampleWindow / tickInterval)
        positionSamples = Array(repeating: seed, count: count)
    }

    // MARK: - Captured animation

    private func playCapturedAnimation() {
        checkmarkProgress = 0
        checkmarkScale = 0.3
        withAnimation(.easeOut(duration: 0.4)) {
            checkmarkProgress = 1
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            checkmarkScale = 1
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Sampling tick

    private func sampleTick() {
        guard phase == .holding || phase == .aligning else { return }

        // Add current position, prune old.
        positionSamples.append(sensorPosition)
        let maxCount = Int(sampleWindow / tickInterval)
        if positionSamples.count > maxCount {
            positionSamples.removeFirst(positionSamples.count - maxCount)
        }

        // Compute 2D variance (std-dev of distance from mean).
        guard positionSamples.count >= 4 else { return }
        let meanX = positionSamples.map(\.x).reduce(0, +) / CGFloat(positionSamples.count)
        let meanY = positionSamples.map(\.y).reduce(0, +) / CGFloat(positionSamples.count)
        let variance = positionSamples.map { pt -> CGFloat in
            let dx = pt.x - meanX
            let dy = pt.y - meanY
            return dx * dx + dy * dy
        }.reduce(0, +) / CGFloat(positionSamples.count)
        let stdDev = sqrt(Double(variance))

        let steady = stdDev < varianceThreshold
        let centered = isInCenterZone

        if phase == .holding {
            // --- HOLDING: fill progress, check for drift ---
            guard hasLiveData else {
                // Frozen signal — don't fill or unwind, just wait.
                return
            }

            if centered && steady {
                // Accumulate progress, fire haptic ticks.
                elapsed += tickInterval
                checkHapticTicks()
                if elapsed >= captureDuration {
                    phase = .captured
                    onCaptured()
                }
            } else {
                // Drifted out — unwind progress.
                unwindProgress()
            }
        } else {
            // --- ALIGNING: check if user has found center ---
            if hasLiveData && centered && steady {
                steadyTime += tickInterval
                if steadyTime >= settleDuration {
                    phase = .holding
                }
            } else {
                steadyTime = max(0, steadyTime - tickInterval * 2)
                // Unwind any leftover progress from a previous holding attempt.
                if elapsed > 0 {
                    unwindProgress()
                }
            }
        }
    }

    /// Smoothly decrease elapsed at 1.5× fill speed. When elapsed reaches 0
    /// we're fully unwound.
    private func unwindProgress() {
        elapsed = max(0, elapsed - tickInterval * 1.5)
        if elapsed <= 0 {
            lastHapticTick = 0
        }
    }

    /// Fire light-impact haptic at 25%, 50%, 75% of capture.
    private func checkHapticTicks() {
        let progress = elapsed / captureDuration
        if progress >= 0.25 && lastHapticTick < 1 {
            lastHapticTick = 1
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if progress >= 0.50 && lastHapticTick < 2 {
            lastHapticTick = 2
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if progress >= 0.75 && lastHapticTick < 3 {
            lastHapticTick = 3
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
