//
//  OnboardingView.swift
//  Perch
//
//  Four-page onboarding flow, then paywall, then first-run calibration.
//
//  Pages:
//    0  Intro — animated figure + "Fix your posture with AirPods"
//    1  Connect your AirPods — detect via audio route
//    2  Allow Motion & Fitness — real CMHeadphoneMotionManager permission + check
//    3  Allow notifications
//
//  No system prompts fire until the user reaches the relevant page. On finish,
//  mark onboarding complete → RootView presents the paywall.
//

import SwiftUI
import CoreMotion
import AVFoundation
import UserNotifications

struct OnboardingView: View {
    @Environment(PerchStore.self) private var store
    @Environment(PostureSource.self) private var source
    @Environment(NudgeService.self) private var nudge

    @State private var step = 0
    private let lastStep = 3

    var body: some View {
        ZStack {
            PerchBackground()
            VStack(spacing: 0) {
                header
                pageContent
                footer
            }
        }
    }

    // MARK: - Header (dots + skip)

    private var header: some View {
        HStack {
            if step < lastStep {
                Button("Skip") { skipToEnd() }
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

    // MARK: - Page content

    @ViewBuilder
    private var pageContent: some View {
        switch step {
        case 0: IntroPage(onNext: advance)
        case 1: ConnectAirPodsPage(onNext: advance)
        case 2: MotionPage(onNext: advance)
        case 3: NotificationsPage(onFinish: finishOnboarding)
        default: EmptyView()
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        // Each page has its own buttons, but for pages that don't
        // (pages 2 and 3 handle their own actions), show nothing extra.
        Color.clear.frame(height: 20)
    }

    // MARK: - Navigation

    private func advance() {
        withAnimation(.easeInOut(duration: 0.4)) {
            step = min(step + 1, lastStep)
        }
    }

    private func skipToEnd() {
        withAnimation(.easeInOut(duration: 0.4)) { step = lastStep }
    }

    private func finishOnboarding() {
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

private struct StepScaffold<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

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
            content
            Spacer()
            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }
}

// MARK: - Page 0: Intro

private struct IntroPage: View {
    let onNext: () -> Void

    @State private var phase: Double = 0

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer()

            Image(systemName: "figure.seated.side")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(Palette.sage)
                .rotationEffect(.degrees(-22 * (1 - phase)), anchor: .bottom)
                .frame(height: 90)

            VStack(spacing: Space.l) {
                AnimatedHeroTitle(phase: phase)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)

                Text("Get a gentle nudge whenever your posture slumps.")
                    .font(.system(.body, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Space.l)
            }

            Spacer()

            PerchPrimaryButton(title: "Get started", action: onNext)
        }
        .padding(.horizontal, Space.xl)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}

/// Progressively capitalizes "posture" → "POSTURE" left to right,
/// driven by `phase` (0…1). Timed to finish as the seated figure
/// reaches upright.
private struct AnimatedHeroTitle: View {
    let phase: Double
    private let target = "posture"

    var body: some View {
        let count = capitalizedCount
        let prefix = String(target.prefix(count))
        let suffix = String(target.suffix(target.count - count))
        return Text("Fix your \(prefix)\(suffix)\nwith AirPods")
    }

    private var capitalizedCount: Int {
        min(target.count, max(0, Int((phase * Double(target.count)).rounded(.up))))
    }
}

// MARK: - Page 1: Connect your AirPods

private struct ConnectAirPodsPage: View {
    let onNext: () -> Void
    @Environment(PostureSource.self) private var source

    var body: some View {
        let connected = source.isAirpodsConnected
        let route = source.audioRouteName

        VStack(spacing: Space.xl) {
            Spacer()

            Image(systemName: connected ? "airpods" : "airpods.gen3")
                .font(.system(size: 46, weight: .thin))
                .foregroundStyle(connected ? Palette.sage : Palette.mist)
                .frame(height: 64)

            VStack(spacing: Space.l) {
                Text("Connect your AirPods")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)

                if connected {
                    VStack(spacing: Space.s) {
                        if let route {
                            Text("Detected: \(route)")
                                .font(.system(.body, weight: .medium))
                                .foregroundStyle(Palette.sage)
                        }
                        Text("Your AirPods are connected — you're ready to go.")
                            .font(.system(.body, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                } else {
                    Text("Pop in your AirPods to continue")
                        .font(.system(.body, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    HStack(spacing: Space.s) {
                        ProgressView()
                            .tint(Palette.sage)
                        Text("Waiting for AirPods…")
                            .font(.system(.subheadline, weight: .regular))
                            .foregroundStyle(Palette.mist)
                    }
                    .padding(.top, Space.s)
                }
            }

            Spacer()

            VStack(spacing: Space.m) {
                PerchPrimaryButton(
                    title: "Continue",
                    fill: connected ? Palette.sage : Palette.hairline,
                    foreground: connected ? Palette.cream : Palette.mist
                ) {
                    onNext()
                }
                .disabled(!connected)

                if !connected {
                    PerchTextButton(title: "Open Bluetooth Settings", color: Palette.mist) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Space.xl)
        .animation(.easeInOut(duration: 0.4), value: connected)
    }
}

// MARK: - Page 2: Allow Motion & Fitness + compatibility

private struct MotionPage: View {
    let onNext: () -> Void
    @Environment(PostureSource.self) private var source

    enum Phase: Equatable {
        case priming
        case checking
        case supported
        case unsupported
        case denied
    }

    @State private var phase: Phase = .priming
    private let checkTimeout: Double = 2.0

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer()

            Image(systemName: iconName)
                .font(.system(size: 46, weight: .thin))
                .foregroundStyle(iconColor)
                .frame(height: 64)

            VStack(spacing: Space.l) {
                Text(titleText)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)

                Text(subtitleText)
                    .font(.system(.body, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()

            VStack(spacing: Space.m) {
                switch phase {
                case .priming:
                    PerchPrimaryButton(title: "Allow access") { startCheck() }
                case .checking:
                    ProgressView()
                        .tint(Palette.sage)
                        .padding(.top, Space.s)
                case .supported:
                    PerchPrimaryButton(title: "Continue") { onNext() }
                case .unsupported:
                    VStack(spacing: Space.m) {
                        PerchTextButton(title: "Try other AirPods", color: Palette.mist) {
                            // Go back to page 1 — parent handles navigation.
                            // For now, proceed anyway so user isn't hard-blocked.
                        }
                        PerchTextButton(title: "Continue anyway", color: Palette.sage) {
                            onNext()
                        }
                    }
                case .denied:
                    VStack(spacing: Space.m) {
                        PerchPrimaryButton(title: "Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        PerchTextButton(title: "Continue anyway", color: Palette.mist) {
                            onNext()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Space.xl)
    }

    // MARK: - Derived properties

    private var iconName: String {
        switch phase {
        case .priming: return "figure.walk.motion"
        case .checking: return "airpods"
        case .supported: return "checkmark.seal"
        case .unsupported, .denied: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch phase {
        case .supported: return Palette.sage
        case .unsupported, .denied: return Palette.amber
        default: return Palette.sage
        }
    }

    private var titleText: String {
        switch phase {
        case .priming: return "Allow Motion\n& Fitness"
        case .checking: return "Checking your\nAirPods…"
        case .supported: return "You're all set."
        case .unsupported: return "Not supported."
        case .denied: return "Motion access\nis needed."
        }
    }

    private var subtitleText: String {
        switch phase {
        case .priming:
            return "Perch reads the motion sensor in your AirPods to know when you're slouching — even in the background. Your motion data never leaves your phone."
        case .checking:
            return "One moment while we make sure your AirPods can sense motion."
        case .supported:
            return "Your AirPods can sense motion. Perch is ready to keep you upright."
        case .unsupported:
            return "These AirPods don't support motion sensing. Perch needs AirPods (3rd gen), AirPods Pro, AirPods Max, or Beats Fit Pro."
        case .denied:
            return "Perch uses Motion & Fitness to sense your posture. Enable it in Settings, or try different AirPods that support motion sensing."
        }
    }

    // MARK: - Real check logic

    private func startCheck() {
        phase = .checking
        Task { await runRealCheck() }
    }

    /// Start CMHeadphoneMotionManager — this triggers the OS Motion & Fitness
    /// permission prompt AND verifies motion capability in one step.
    private func runRealCheck() async {
        let manager = CMHeadphoneMotionManager()

        guard manager.isDeviceMotionAvailable else {
            // No motion hardware at all — not a denied-permission case.
            withAnimation { phase = .unsupported }
            return
        }

        var sampleArrived = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            manager.startDeviceMotionUpdates(to: .main) { motion, _ in
                guard !sampleArrived, motion != nil else { return }
                sampleArrived = true
                manager.stopDeviceMotionUpdates()
                continuation.resume()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + checkTimeout) {
                guard !sampleArrived else { return }
                manager.stopDeviceMotionUpdates()
                continuation.resume()
            }
        }

        // After the check, determine if permission was denied.
        // If CMHeadphoneMotionManager.authorizationStatus() is available (iOS 18+),
        // we can check. Otherwise, isDeviceMotionAvailable + no sample = likely denied.
        let isDenied: Bool
        if #available(iOS 18.0, *) {
            isDenied = CMHeadphoneMotionManager.authorizationStatus() == .denied
        } else {
            // Pre-iOS 18: if device says motion IS available but no sample arrived,
            // the user probably denied the prompt. (isDeviceMotionAvailable still
            // returns true when permission is denied, annoyingly.)
            isDenied = !sampleArrived
        }

        withAnimation {
            if sampleArrived {
                phase = .supported
            } else if isDenied {
                phase = .denied
            } else {
                phase = .unsupported
            }
        }
    }
}

// MARK: - Page 3: Allow notifications

private struct NotificationsPage: View {
    let onFinish: () -> Void
    @Environment(NudgeService.self) private var nudge

    enum Phase { case priming, requesting }
    @State private var phase: Phase = .priming

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer()

            Image(systemName: "bell")
                .font(.system(size: 46, weight: .thin))
                .foregroundStyle(Palette.sage)
                .frame(height: 64)

            VStack(spacing: Space.l) {
                Text("Allow notifications")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)

                Text("So Perch can nudge you when you've been slouching a while — gently, never alarming.")
                    .font(.system(.body, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()

            VStack(spacing: Space.m) {
                PerchPrimaryButton(
                    title: phase == .requesting ? "Requesting…" : "Allow"
                ) {
                    Task { await requestPermission() }
                }
                .disabled(phase == .requesting)

                PerchTextButton(title: "Not now", color: Palette.mist) {
                    onFinish()
                }
            }
        }
        .padding(.horizontal, Space.xl)
    }

    private func requestPermission() async {
        phase = .requesting
        await nudge.requestNotificationPermission()
        // Proceed regardless of the user's choice.
        onFinish()
    }
}
