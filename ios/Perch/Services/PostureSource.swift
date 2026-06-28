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
//  AUDIO SESSION KEEP-ALIVE:
//  Uses a silent .playback + .mixWithOthers audio loop so iOS keeps the app
//  alive in the background for continuous posture monitoring. The silent player
//  coexists with Spotify, podcasts, etc. and never interrupts or ducks other
//  playback. Observes interruption, route-change, and media-services-reset
//  notifications to pause/resume monitoring gracefully around calls and Siri.
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

    /// Whether any Bluetooth audio device (AirPods, Beats, etc.) is currently
    /// connected. Derived from the audio route — used by the onboarding
    /// "Connect your AirPods" step. Does NOT require motion permission.
    var isAirpodsConnected: Bool {
        audioRouteName != nil
    }

    // MARK: - Developer overrides (hidden Dev Panel)

    /// When true, `neckAngle` is held at `manualAngle` instead of live data.
    var manualOverride: Bool = false
    var manualAngle: Double = 0 {
        didSet { if manualOverride { neckAngle = manualAngle } }
    }

    // MARK: - Real sensor internals

    /// Nil until `startReal()` creates it — no Motion & Fitness prompt fires
    /// before the user is ready.
    private var motionManager: CMHeadphoneMotionManager?
    private var rawTilt: Double = 0      ///< Live uncalibrated pitch from sensor (degrees).
    private var rawRoll: Double = 0      ///< Live uncalibrated roll from sensor (degrees).
    private var baseline: Double = 0     ///< Pitch captured at calibration time.
    private var _sensorAirpodsConnected: Bool = false

    // MARK: - Audio session keep-alive

    /// A silent looping player that keeps the app alive in the background.
    /// Configured as .playback + .mixWithOthers so it coexists with other audio.
    private var keepAlivePlayer: AVAudioPlayer?
    /// Tracks whether monitoring was active before an audio interruption began,
    /// so we can decide whether to restart CMHeadphoneMotionManager on .ended.
    private var wasMonitoringBeforeInterruption = false

    // MARK: - Simulated internals

    private var simRawTilt: Double = 6
    private var simRawRoll: Double = 0
    private var simBaseline: Double = 6
    private var driftTarget: Double = 6
    private var rollDriftTarget: Double = 0
    private var ticksUntilNewTarget = 0
    private var simTimer: Timer?

    // MARK: - Init

    /// The source is created inert — it does NOT start the sensor or trigger
    /// any permission prompts. Call `start()` explicitly when motion monitoring
    /// should begin (after onboarding, or on relaunch if already onboarded).
    override init() {
        super.init()
        configureAudioSession()
        observeAudioNotifications()
        updateAudioRoute()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        motionManager?.stopDeviceMotionUpdates()
        stopKeepAlive()
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

    /// The live uncalibrated tilt (pitch), useful for the hold-to-capture
    /// bubble-level visualization during calibration.
    var liveRawTilt: Double {
        switch sourceMode {
        case .real: return rawTilt
        case .simulated: return simRawTilt
        }
    }

    /// The live uncalibrated roll (head tilt toward shoulder), for 2D
    /// bubble-level calibration.
    var liveRawRoll: Double {
        switch sourceMode {
        case .real: return rawRoll
        case .simulated: return simRawRoll
        }
    }

    // MARK: - Real sensor pipeline

    private func startReal() {
        let manager: CMHeadphoneMotionManager
        if let existing = motionManager {
            manager = existing
        } else {
            manager = CMHeadphoneMotionManager()
            manager.delegate = self
            motionManager = manager
        }

        guard manager.isDeviceMotionAvailable else {
            _sensorAirpodsConnected = false
            return
        }
        _sensorAirpodsConnected = true
        updateAudioRoute()
        startKeepAlive()

        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
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
        // attitude.roll is rotation around the y-axis in radians.
        // Positive roll ≈ tilting head toward right shoulder.
        rawRoll = motion.attitude.roll * 180.0 / .pi
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

        // Gentle roll drift around 0° so the 2D bubble moves side-to-side.
        if ticksUntilNewTarget <= 0 {
            rollDriftTarget = Double.random(in: -8...8)
        }
        simRawRoll += (rollDriftTarget - simRawRoll) * ease
        simRawRoll += Double.random(in: -0.2...0.2)

        neckAngle = simRawTilt - simBaseline
    }

    // MARK: - Audio session configuration

    /// Configures the shared AVAudioSession for background keep-alive.
    /// .playback + .mixWithOthers ensures the silent loop coexists with Spotify,
    /// podcasts, and phone calls without interrupting or ducking them.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playback
                || session.categoryOptions.rawValue != AVAudioSession.CategoryOptions.mixWithOthers.rawValue else {
            return
        }
        try? session.setCategory(.playback, options: .mixWithOthers)
    }

    // MARK: - Keep-alive silent audio

    /// Generates a minimal silent PCM WAV file in memory and starts an
    /// infinite-looping AVAudioPlayer. This keeps iOS from suspending the app
    /// while posture monitoring runs in the background.
    private func startKeepAlive() {
        guard keepAlivePlayer == nil else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)

        guard let player = makeSilentLoopPlayer() else { return }
        player.numberOfLoops = -1
        player.volume = 0
        player.play()
        keepAlivePlayer = player
    }

    /// Stops the silent keep-alive player and deactivates the audio session so
    /// other apps can use it freely.
    private func stopKeepAlive() {
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Builds an AVAudioPlayer from a short, silent WAV payload so we never
    /// need a bundled audio asset.
    private func makeSilentLoopPlayer() -> AVAudioPlayer? {
        let wav = makeSilentWAV()
        return try? AVAudioPlayer(data: wav)
    }

    /// Produces a valid 16-bit mono PCM WAV with 0.1 s of silence.
    private func makeSilentWAV() -> Data {
        let sampleRate: UInt32 = 8000
        let numSamples: UInt32 = 800          // 0.1 seconds
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = numSamples * UInt32(blockAlign)

        func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
            var v = value.littleEndian
            data.append(Data(bytes: &v, count: MemoryLayout<T>.size))
        }

        var data = Data()
        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        appendLE(UInt32(36 + dataSize), to: &data)
        data.append("WAVE".data(using: .ascii)!)
        // fmt sub-chunk
        data.append("fmt ".data(using: .ascii)!)
        appendLE(UInt32(16), to: &data)
        appendLE(UInt16(1), to: &data)       // PCM
        appendLE(numChannels, to: &data)
        appendLE(sampleRate, to: &data)
        appendLE(byteRate, to: &data)
        appendLE(blockAlign, to: &data)
        appendLE(bitsPerSample, to: &data)
        // data sub-chunk
        data.append("data".data(using: .ascii)!)
        appendLE(dataSize, to: &data)
        // Silent samples
        data.append(Data(count: Int(dataSize)))

        return data
    }

    // MARK: - Audio route (cosmetic)

    func updateAudioRoute() {
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

    // MARK: - Notification observers

    private func observeAudioNotifications() {
        let center = NotificationCenter.default

        center.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    // MARK: - Interruption handler

    /// Pauses monitoring on interruption begin (call, Siri, alarm) and resumes
    /// automatically when the interruption ends with `.shouldResume`.
    @objc private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // A call, Siri, or alarm is taking over audio. Pause everything.
            wasMonitoringBeforeInterruption = _sensorAirpodsConnected
            isOnCall = true
            stop()
            _sensorAirpodsConnected = false

        case .ended:
            isOnCall = false

            guard let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if options.contains(.shouldResume) {
                // The interruption (e.g. phone call) ended and we should resume.
                // Reactivate the audio session and restart monitoring if we were
                // monitoring before.
                configureAudioSession()
                try? AVAudioSession.sharedInstance().setActive(true)
                if wasMonitoringBeforeInterruption {
                    start()
                }
            }

        @unknown default:
            break
        }
    }

    // MARK: - Route-change handler

    /// Updates the cosmetic route name when audio hardware changes.
    /// Handles AirPods removal gracefully — the CMHeadphoneMotionManagerDelegate
    /// disconnect callback will also fire, but this provides an extra safety net.
    @objc private func handleRouteChange(_ notification: Notification) {
        updateAudioRoute()

        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Audio device (e.g. AirPods) was removed. The delegate disconnect
            // callback handles the sensor side; here we just refresh the label.
            updateAudioRoute()

        case .newDeviceAvailable:
            // New device appeared — could be AirPods being put in.
            updateAudioRoute()

        default:
            break
        }
    }

    // MARK: - Media-services-reset handler

    /// Rare: the media server died. Reconfigure the audio session so we can
    /// restart the keep-alive player when monitoring resumes.
    @objc private func handleMediaServicesReset(_ notification: Notification) {
        configureAudioSession()
        // If we were monitoring, restart the keep-alive player.
        if _sensorAirpodsConnected {
            startKeepAlive()
        }
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
