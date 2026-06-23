//
//  PostureSource.swift
//  Perch
//
//  The SINGLE source of truth for posture data. Supports two internal sources
//  switched at runtime from the hidden Dev Panel:
//
//    • REAL   – CMHeadphoneMotionManager (CoreMotion) for actual AirPods sensors.
//    • SIMULATED – a gentle drift signal for demos and Simulator previews.
//
//  Defaults: Real on device, Simulated in the iOS Simulator. All screens and the
//  PostureEngine read ONLY through this type — never touch AirPods APIs directly.
//

import SwiftUI
import Combine
import CoreMotion
import AVFoundation

@Observable
@MainActor
final class PostureSource: NSObject {

    // MARK: - Source mode

    enum SourceMode: String, CaseIterable {
        case simulated
        case real
    }

    /// Which sensor backend is currently active. Toggleable from the Dev Panel.
    /// Defaults to `.real` on device, `.simulated` in the Simulator.
    var sourceMode: SourceMode = {
        #if targetEnvironment(simulator)
        return .simulated
        #else
        return .real
        #endif
    }()

    // MARK: - Observable outputs (read by PostureEngine + UI)

    /// Forward head/neck tilt in degrees, relative to the calibrated baseline.
    /// 0° ≈ the user's "good posture"; positive values mean slouching forward.
    private(set) var neckAngle: Double = 0

    /// Whether supported AirPods are connected and streaming motion.
    /// Real: set by CMHeadphoneMotionManagerDelegate + isDeviceMotionAvailable.
    /// Simulated: always true while running.
    /// Dev Panel can override via `manualAirpodsOverride` / `manualAirpodsValue`.
    var airpodsConnected: Bool {
        if manualAirpodsOverride { return manualAirpodsValue }
        return _sensorAirpodsConnected
    }

    /// When true, the dev panel's AirPods toggle overrides the real sensor state.
    var manualAirpodsOverride: Bool = false
    /// The value forced when `manualAirpodsOverride` is true.
    var manualAirpodsValue: Bool = true

    /// Simulated context signals (surfaced here so the engine never reaches
    /// outside PostureSource for any sensor data).
    var isMoving: Bool = false
    var isOnCall: Bool = false

    /// Cosmetic: the current audio route port name (e.g. "John's AirPods Pro").
    /// Read from AVAudioSession. Never gated on — cosmetic only.
    private(set) var audioRouteName: String?

    // MARK: - Developer overrides (hidden Dev Panel)

    /// When true, `neckAngle` is held at `manualAngle` instead of live data.
    var manualOverride: Bool = false
    var manualAngle: Double = 0 {
        didSet { if manualOverride { neckAngle = manualAngle } }
    }

    // MARK: - Real sensor internals

    private let motionManager = CMHeadphoneMotionManager()
    private var rawTilt: Double = 0      ///< Live uncalibrated pitch from sensor (degrees).
    private var baseline: Double = 0     ///< Pitch captured at calibration time.
    private var _sensorAirpodsConnected: Bool = false

    // MARK: - Simulated internals

    private var simRawTilt: Double = 6
    private var simBaseline: Double = 6
    private var driftTarget: Double = 6
    private var ticksUntilNewTarget = 0
    private var simTimer: Timer?

    // MARK: - Init

    override init() {
        super.init()
        motionManager.delegate = self
        updateAudioRoute()
        start()
    }

    // MARK: - Lifecycle

    /// Begin streaming from the active source.
    func start() {
        stop()
        _sensorAirpodsConnected = false

        switch sourceMode {
        case .real:
            startReal()
        case .simulated:
            startSimulated()
        }
    }

    func stop() {
        simTimer?.invalidate()
        simTimer = nil
        motionManager.stopDeviceMotionUpdates()
    }

    /// Switch between real and simulated at runtime (used by Dev Panel).
    func setSourceMode(_ mode: SourceMode) {
        guard mode != sourceMode else { return }
        sourceMode = mode
        manualOverride = false
        start()
    }

    // MARK: - Calibration

    /// Capture the current raw tilt as the new baseline (good posture = 0°).
    func calibrate() {
        switch sourceMode {
        case .real:
            baseline = rawTilt
            neckAngle = manualOverride ? manualAngle : 0
        case .simulated:
            simBaseline = simRawTilt
            neckAngle = manualOverride ? manualAngle : 0
        }
    }

    /// The live uncalibrated tilt, useful for the hold-to-capture bubble-level
    /// visualization during calibration.
    var liveRawTilt: Double {
        switch sourceMode {
        case .real: return rawTilt
        case .simulated: return simRawTilt
        }
    }

    // MARK: - Real sensor pipeline

    private func startReal() {
        guard motionManager.isDeviceMotionAvailable else {
            _sensorAirpodsConnected = false
            return
        }
        _sensorAirpodsConnected = true
        updateAudioRoute()

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, let motion = motion else { return }
            self.handleRealMotion(motion)
        }
    }

    private func handleRealMotion(_ motion: CMDeviceMotion) {
        guard !manualOverride else {
            neckAngle = manualAngle
            return
        }

        // attitude.pitch is rotation around the x-axis in radians.
        // Positive pitch ≈ device tilting forward (head drooping).
        // Convert to degrees and subtract the calibration baseline.
        rawTilt = motion.attitude.pitch * 180.0 / .pi
        neckAngle = rawTilt - baseline
    }

    // MARK: - Simulated sensor pipeline

    private func startSimulated() {
        _sensorAirpodsConnected = true
        let t = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.simTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        simTimer = t
    }

    private func simTick() {
        guard !manualOverride else {
            neckAngle = manualAngle
            return
        }

        if ticksUntilNewTarget <= 0 {
            let roll = Double.random(in: 0...1)
            let upright = simBaseline + Double.random(in: -3...3)
            let slouch = simBaseline + Double.random(in: 14...24)
            driftTarget = roll < 0.62 ? upright : slouch
            ticksUntilNewTarget = Int.random(in: 35...110)
        }
        ticksUntilNewTarget -= 1

        let ease = 0.04
        simRawTilt += (driftTarget - simRawTilt) * ease
        simRawTilt += Double.random(in: -0.25...0.25)

        neckAngle = simRawTilt - simBaseline
    }

    // MARK: - Audio route (cosmetic)

    /// Lazily configure AVAudioSession for route-name queries.
    /// `.ambient` category — never interrupts other audio, no setActive needed.
    private func ensureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .ambient else { return }
        try? session.setCategory(.ambient, mode: .default)
    }

    private func updateAudioRoute() {
        ensureAudioSession()
        let session = AVAudioSession.sharedInstance()
        for output in session.currentRoute.outputs {
            if output.portType == .bluetoothA2DP
                || output.portType == .bluetoothHFP
                || output.portType == .bluetoothLE
                || output.portType == .headphones
            {
                audioRouteName = output.portName.isEmpty ? nil : output.portName
                return
            }
        }
        audioRouteName = nil
    }
}

// MARK: - CMHeadphoneMotionManagerDelegate

extension PostureSource: CMHeadphoneMotionManagerDelegate {

    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self._sensorAirpodsConnected = true
            self.updateAudioRoute()
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self._sensorAirpodsConnected = false
            self.updateAudioRoute()
        }
    }
}
