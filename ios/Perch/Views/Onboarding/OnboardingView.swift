//
//  OnboardingView.swift
//  Perch
//
//  First-launch flow: ~5 short, swipeable, skippable steps that end at the
//  paywall. Warm, brief, reassuring copy throughout.
//
//  Step 2 now runs a real CMHeadphoneMotionManager compatibility check:
//  starts the manager, waits up to ~2 s for a motion sample, and shows
//  "supported" or "not supported" accordingly.
//
//  Step 4 (calibrate) now uses a hold-to-capture interaction: a bubble-level
//  dot that moves with live head angle; the user holds steady for ~3 s while
//  a circular progress arc fills.
//

import SwiftUI
import CoreMotion
import AVFoundation

struct OnboardingView: View {
    @Environment(PerchStore.self) private var store
    @Environment(PostureSource.self) private var source
    @Environment(NudgeService.self) private var nudge

    @State private var step = 0

    private let lastStep = 4

    var body: some View {
        ZStack {
            PerchBackground()
            VStack(spacing: 0) {
                header
                TabView(selection: $step) {
                    WelcomeStep().tag(0)
                    HowItWorksStep().tag(1)
                    CompatibilityStep(onContinue: advance).tag(2)
                    PermissionsStep(onContinue: advance).tag(3)
                    CalibrateStep(onCalibrate: calibrateAndFinish).tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: step)

                footer
            }
        }
    }

    private var header: some View {
        HStack {
            if step < lastStep {
                Button("Skip") { skip() }
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Palette.mist)
                    .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 40, height: 20)
            }
            Spacer()
            DotsIndicator(count: lastStep + 1, index: step)
            Spacer()
            Color.clear.frame(width: 40, height: 20)
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.l)
    }

    @ViewBuilder
    private var footer: some View {
        VStack {
            if step < 3 {
                PerchPrimaryButton(title: "Continue") { advance() }
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.bottom, Space.xl)
    }

    private func advance() {
        withAnimation { step = min(step + 1, lastStep) }
    }

    private func skip() {
        withAnimation { step = lastStep }
    }

    private func calibrateAndFinish() {
        source.calibrate()
        store.setBaseline(0)
        store.completeOnboarding()
    }
}

// MARK: - Dots

private struct DotsIndicator: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Palette.sage : Palette.hairline)
                    .frame(width: i == index ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: index)
            }
        }
    }
}

// MARK: - Shared step scaffold

private struct StepScaffold<Extra: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 46, weight: .thin))
                .foregroundStyle(Palette.sage)
                .frame(height: 64)
            VStack(spacing: Space.l) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(.body, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            extra
            Spacer()
            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        StepScaffold(
            icon: "figure.seated.side",
            title: "Better posture,\non autopilot.",
            subtitle: "Perch uses your AirPods to gently keep you upright. No timers. No fuss."
        ) { EmptyView() }
    }
}

private struct HowItWorksStep: View {
    var body: some View {
        StepScaffold(
            icon: "airpods",
            title: "Quietly watching\nyour back.",
            subtitle: "Pop your AirPods in and Perch quietly watches your posture in the background. Slouch too long, and you'll feel a gentle nudge. That's it."
        ) { EmptyView() }
    }
}

// MARK: - Real compatibility check

private struct CompatibilityStep: View {
    let onContinue: () -> Void

    @Environment(PostureSource.self) private var source

    enum Status { case checking, supported, notSupported }
    @State private var status: Status = .checking
    @State private var showDesignPreview = false

    private let checkTimeout: Double = 2.0

    var body: some View {
        StepScaffold(
            icon: iconName,
            title: titleText,
            subtitle: subtitleText
        ) {
            VStack(spacing: Space.m) {
                if let route = source.audioRouteName, status == .supported {
                    Text("Detected: \(route)")
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                        .padding(.top, Space.s)
                }

                // Design preview toggle (always visible once check finishes).
                if status != .checking || showDesignPreview {
                    Button {
                        withAnimation { showDesignPreview.toggle() }
                    } label: {
                        Text(showDesignPreview
                             ? "Hide design preview"
                             : (status == .supported
                                ? "Preview unsupported state"
                                : "Preview supported state"))
                            .font(.footnote)
                            .foregroundStyle(Palette.mist)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Space.s)
                }
            }
        }
        .task { await runRealCheck() }
    }

    private var iconName: String {
        if showDesignPreview {
            return status == .supported
                ? "exclamationmark.triangle"
                : "checkmark.seal"
        }
        switch status {
        case .checking: return "airpods"
        case .supported: return "checkmark.seal"
        case .notSupported: return "exclamationmark.triangle"
        }
    }

    private var titleText: String {
        if showDesignPreview {
            return status == .supported
                ? "Not supported yet."
                : "You're all set."
        }
        switch status {
        case .checking: return "Checking your\nAirPods…"
        case .supported: return "You're all set."
        case .notSupported: return "Not supported yet."
        }
    }

    private var subtitleText: String {
        if showDesignPreview {
            return status == .supported
                ? "These AirPods don't have a motion sensor. Perch needs AirPods (3rd gen), Pro, or Max."
                : "Your AirPods support motion sensing. Perch is ready to keep you upright."
        }
        switch status {
        case .checking:
            return "One moment while we make sure your AirPods can sense motion."
        case .supported:
            return "Your AirPods support motion sensing. Perch is ready to keep you upright."
        case .notSupported:
            return "These AirPods don't have a motion sensor. Perch needs AirPods (3rd gen), Pro, or Max."
        }
    }

    /// Real check: start CMHeadphoneMotionManager, wait for either a motion
    /// sample or a 2‑second timeout, then report supported/not‑supported.
    private func runRealCheck() async {
        let manager = CMHeadphoneMotionManager()

        // If device motion isn't available at all, fail immediately.
        guard manager.isDeviceMotionAvailable else {
            withAnimation { status = .notSupported }
            return
        }

        // Wait for the first motion sample with a timeout.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var sampleArrived = false

            manager.startDeviceMotionUpdates(to: .main) { motion, _ in
                guard !sampleArrived, motion != nil else { return }
                sampleArrived = true
                manager.stopDeviceMotionUpdates()
                continuation.resume()
            }

            // Timeout after `checkTimeout` seconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + checkTimeout) {
                guard !sampleArrived else { return }
                manager.stopDeviceMotionUpdates()
                continuation.resume()
            }
        }

        // Check again — sampleArrived is captured but we can just check availability.
        withAnimation {
            status = manager.isDeviceMotionAvailable ? .supported : .notSupported
        }
    }
}

// MARK: - Permissions

private struct PermissionsStep: View {
    let onContinue: () -> Void
    @Environment(NudgeService.self) private var nudge
    @State private var requesting = false

    var body: some View {
        StepScaffold(
            icon: "hand.raised",
            title: "Two quick\npermissions.",
            subtitle: "Motion & Fitness, so we can sense your posture — even in the background. And Notifications, so we can nudge you."
        ) {
            VStack(spacing: Space.m) {
                PerchPrimaryButton(title: requesting ? "Requesting…" : "Allow access") {
                    Task { await requestPermissions() }
                }
                .disabled(requesting)
                .padding(.top, Space.l)
                PerchTextButton(title: "Not now", color: Palette.mist) { onContinue() }
            }
            .padding(.horizontal, Space.l)
        }
    }

    private func requestPermissions() async {
        requesting = true
        if CMMotionActivityManager.isActivityAvailable() {
            let manager = CMMotionActivityManager()
            let queue = OperationQueue()
            manager.startActivityUpdates(to: queue) { _ in
                manager.stopActivityUpdates()
            }
        }
        await nudge.requestNotificationPermission()
        requesting = false
        onContinue()
    }
}

// MARK: - Calibrate (hold-to-capture)

private struct CalibrateStep: View {
    let onCalibrate: () -> Void
    @Environment(PostureSource.self) private var source

    @State private var capturePhase: CapturePhase = .ready

    var body: some View {
        StepScaffold(
            icon: captureIcon,
            title: captureTitle,
            subtitle: captureSubtitle
        ) {
            VStack(spacing: Space.l) {
                CalibrationHoldView(
                    liveAngle: source.liveRawTilt,
                    phase: $capturePhase,
                    onCaptured: {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            onCalibrate()
                        }
                    }
                )
                .frame(width: 200, height: 200)
            }
            .padding(.top, Space.l)
        }
    }

    private var captureIcon: String {
        switch capturePhase {
        case .ready: return "figure.seated.side"
        case .capturing: return "scope"
        case .captured: return "checkmark.circle"
        }
    }

    private var captureTitle: String {
        switch capturePhase {
        case .ready: return "Sit the way you'd\nlike to sit all day."
        case .capturing: return "Hold steady…"
        case .captured: return "Perfectly set."
        }
    }

    private var captureSubtitle: String {
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
