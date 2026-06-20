//
//  PostureSource.swift
//  Perch
//
//  The SINGLE source of truth for posture data. Today it produces a SIMULATED
//  signal so every screen and state can be demoed. Later, the simulated signal
//  can be swapped for a real AirPods motion module (CMHeadphoneMotionManager)
//  WITHOUT touching any UI — all screens read posture only through this type.
//

import SwiftUI
import Combine

@Observable
@MainActor
final class PostureSource {
    /// Forward head/neck tilt in degrees, relative to the calibrated baseline.
    /// 0° ≈ the user's "good posture"; positive values mean slouching forward.
    private(set) var neckAngle: Double = 0

    /// Whether supported AirPods are currently in the user's ears.
    var airpodsConnected: Bool = true

    /// Simulated motion/context signals (also surfaced through this single source
    /// so the engine never reaches outside PostureSource for any sensor data).
    var isMoving: Bool = false
    var isOnCall: Bool = false

    // MARK: - Developer override (hidden dev panel)

    /// When true, `neckAngle` is held at `manualAngle` instead of drifting.
    var manualOverride: Bool = false
    var manualAngle: Double = 0 {
        didSet { if manualOverride { neckAngle = manualAngle } }
    }

    // MARK: - Simulation internals

    /// The raw forward tilt before baseline subtraction (degrees).
    private var rawTilt: Double = 6
    /// The calibrated resting tilt captured at "This is my good posture".
    private var baseline: Double = 6
    /// Smooth target the drift eases toward, re-rolled periodically.
    private var driftTarget: Double = 6
    private var ticksUntilNewTarget = 0

    private var timer: Timer?

    init() {
        start()
    }

    /// Begin emitting the continuous simulated signal (~12 Hz).
    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Capture the current raw tilt as the new baseline (good posture = 0°).
    func calibrate() {
        baseline = rawTilt
        if manualOverride {
            neckAngle = manualAngle
        } else {
            neckAngle = 0
        }
    }

    private func tick() {
        guard !manualOverride else {
            neckAngle = manualAngle
            return
        }

        // Periodically pick a new gentle target so the value wanders slowly
        // between upright and slouch territory, keeping the demo feeling alive.
        if ticksUntilNewTarget <= 0 {
            // Bias slightly toward upright but let it drift into slouch at times.
            let roll = Double.random(in: 0...1)
            let upright = baseline + Double.random(in: -3...3)
            let slouch = baseline + Double.random(in: 14...24)
            driftTarget = roll < 0.62 ? upright : slouch
            ticksUntilNewTarget = Int.random(in: 35...110) // ~3–9 s per leg
        }
        ticksUntilNewTarget -= 1

        // Ease toward the target with a touch of natural jitter.
        let ease = 0.04
        rawTilt += (driftTarget - rawTilt) * ease
        rawTilt += Double.random(in: -0.25...0.25)

        neckAngle = rawTilt - baseline
    }
}
