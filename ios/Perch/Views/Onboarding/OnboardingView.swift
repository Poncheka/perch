//
//  OnboardingView.swift
//  Perch
//
//  First-launch flow: ~6 short, swipeable, skippable steps that end at the
//  paywall. Warm, brief, reassuring copy throughout.
//
//  Steps:
//    0  Welcome
//    1  How it works
//    2  Motion & Fitness primer + real compatibility check
//    3  Notifications primer + authorization
//    4  Social proof / testimonials (placeholder)
//    5  Calibrate (hold-to-capture, skippable)
//
//  The paywall fires from RootView once onboarding completes.
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

    private let lastStep = 5

    var body: some View {
        ZStack {
            PerchBackground()
            VStack(spacing: 0) {
                header
                TabView(selection: $step) {
                    WelcomeStep().tag(0)
                    HowItWorksStep().tag(1)
                    MotionStep(onContinue: advance).tag(2)
                    NotificationsStep(onContinue: advance).tag(3)
                    SocialProofStep().tag(4)
                    CalibrateStep(onCalibrate: calibrateAndFinish, onSkip: skipCalibrate).tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: step)

                footer
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if step < lastStep {
                Button("Skip") { skipToLast() }
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

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack {
            // Show a generic Continue button for steps without their own action button.
            if step < 2 || step == 4 {
                PerchPrimaryButton(title: "Continue") { advance() }
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.bottom, Space.xl)
    }

    // MARK: - Navigation

    private func advance() {
        withAnimation { step = min(step + 1, lastStep) }
    }

    private func skipToLast() {
        withAnimation { step = lastStep }
    }

    private func calibrateAndFinish() {
        source.calibrate()
        store.setBaseline(0)
        store.completeOnboarding()
    }

    /// Skip calibration entirely — captures the current angle as-is and finishes.
    private func skipCalibrate() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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

// MARK: - Step 0: Animated Welcome

private struct WelcomeStep: View {
    /// 0…1 phase that drives both the figure rotation and text capitalization.
    /// Loops gently: slouch → upright → slouch.
    @State private var phase: Double = 0

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer()

            // Animated figure: rotates from slouch (~-22°) to upright (0°).
            Image(systemName: "figure.seated.side")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(Palette.sage)
                .rotationEffect(.degrees(-22 * (1 - phase)), anchor: .bottom)
                .frame(height: 90)

            VStack(spacing: Space.l) {
                AnimatedPostureTitle(phase: phase)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)

                Text("Perch uses your AirPods to gently keep you upright. No timers. No fuss.")
                    .font(.system(.body, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Space.l)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Space.xl)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}

/// Progressively capitalizes "posture" → "POSTURE" one letter at a time,
/// left to right, driven by `phase` (0…1). Timed to finish as the figure
/// reaches upright.
private struct AnimatedPostureTitle: View {
    let phase: Double

    private let target = "posture"

    var body: some View {
        let count = capitalizedCount
        let prefix = String(target.prefix(count))
        let suffix = String(target.suffix(target.count - count))

        return Text("Better \(prefix)\(suffix),\non autopilot.")
    }

    /// How many letters of "posture" should be uppercase right now.
    private var capitalizedCount: Int {
        min(target.count, max(0, Int((phase * Double(target.count)).rounded(.up))))
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

// MARK: - Step 2: Motion & Fitness primer + real compatibility check

private struct MotionStep: View {
    let onContinue: () -> Void

    @Environment(PostureSource.self) private var source

    enum Phase { case priming, checking, supported, deniedOrUnsupported }
    @State private var phase: Phase = .priming
    @State private var showDesignPreview = false

    private let checkTimeout: Double = 2.0

    var body: some View {
        ZStack {
            if phase == .deniedOrUnsupported {
                deniedRecovery
            } else {
                mainContent
            }
        }
    }

    // MARK: - Main content (priming / checking / supported)

    private var mainContent: some View {
        StepScaffold(
            icon: iconName,
            title: titleText,
            subtitle: subtitleText
        ) {
            VStack(spacing: Space.m) {
                if phase == .priming {
                    PerchPrimaryButton(title: "Allow access") {
                        startCheck()
                    }
                } else if phase == .checking {
                    ProgressView()
                        .tint(Palette.sage)
                        .padding(.top, Space.s)
                }

                // Audio route label (cosmetic).
                if let route = source.audioRouteName, phase == .supported {
                    Text("Detected: \(route)")
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                        .padding(.top, Space.s)
                }

                // Design preview toggle.
                if phase != .checking || showDesignPreview {
                    Button {
                        withAnimation { showDesignPreview.toggle() }
                    } label: {
                        Text(showDesignPreview
                             ? "Hide design preview"
                             : previewLabel)
                            .font(.footnote)
                            .foregroundStyle(Palette.mist)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Space.s)
                }
            }
            .padding(.top, Space.l)
        }
    }

    // MARK: - Denied / unsupported recovery

    private var deniedRecovery: some View {
        StepScaffold(
            icon: "gearshape",
            title: "Motion access\nis needed.",
            subtitle: "Perch uses Motion & Fitness to sense your posture. Enable it in Settings, or use different AirPods that support motion sensing."
        ) {
            VStack(spacing: Space.m) {
                PerchPrimaryButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .padding(.top, Space.l)

                PerchTextButton(title: "Continue anyway", color: Palette.mist) {
                    onContinue()
                }

                // Design preview toggle.
                Button {
                    withAnimation { showDesignPreview.toggle() }
                } label: {
                    Text(showDesignPreview ? "Hide design preview" : "Preview supported state")
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                }
                .buttonStyle(.plain)
                .padding(.top, Space.s)
            }
            .padding(.horizontal, Space.l)
        }
    }

    // MARK: - Icon / title / subtitle helpers

    private var iconName: String {
        if showDesignPreview {
            return phase == .supported ? "exclamationmark.triangle" : "checkmark.seal"
        }
        switch phase {
        case .priming: return "figure.walk.motion"
        case .checking: return "airpods"
        case .supported: return "checkmark.seal"
        case .deniedOrUnsupported: return "exclamationmark.triangle"
        }
    }

    private var titleText: String {
        if showDesignPreview {
            return phase == .supported
                ? "Not supported yet."
                : "You're all set."
        }
        switch phase {
        case .priming: return "Motion &\nFitness."
        case .checking: return "Checking your\nAirPods…"
        case .supported: return "You're all set."
        case .deniedOrUnsupported: return "Not supported yet."
        }
    }

    private var subtitleText: String {
        if showDesignPreview {
            return phase == .supported
                ? "These AirPods don't have a motion sensor. Perch needs AirPods (3rd gen), Pro, or Max."
                : "Your AirPods support motion sensing. Perch is ready to keep you upright."
        }
        switch phase {
        case .priming:
            return "Perch uses your AirPods motion sensor to sense your posture, even in the background. Tap below to get started."
        case .checking:
            return "One moment while we make sure your AirPods can sense motion."
        case .supported:
            return "Your AirPods support motion sensing. Perch is ready to keep you upright."
        case .deniedOrUnsupported:
            return "Motion access is needed. Check Settings, or confirm your AirPods support motion sensing."
        }
    }

    private var previewLabel: String {
        phase == .supported ? "Preview unsupported state" : "Preview supported state"
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

        // If device motion isn't available at all (pre-check), fail immediately.
        guard manager.isDeviceMotionAvailable else {
            withAnimation { phase = .deniedOrUnsupported }
            return
        }

        // Wait for the first motion sample with a timeout.
        var sampleArrived = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
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

        withAnimation {
            if sampleArrived {
                phase = .supported
                // Brief pause so the user sees "You're all set," then advance.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onContinue()
                }
            } else {
                phase = .deniedOrUnsupported
            }
        }
    }
}

// MARK: - Step 3: Notifications primer + authorization

private struct NotificationsStep: View {
    let onContinue: () -> Void
    @Environment(NudgeService.self) private var nudge

    enum Phase { case priming, requesting, authorized, denied }
    @State private var phase: Phase = .priming

    var body: some View {
        ZStack {
            if phase == .denied {
                deniedRecovery
            } else {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        StepScaffold(
            icon: "bell",
            title: "Gentle nudges.",
            subtitle: "Perch sends a quiet notification if you've been slouching too long while the app is in the background. No loud alerts, ever."
        ) {
            VStack(spacing: Space.m) {
                PerchPrimaryButton(title: requestingLabel) {
                    Task { await requestNotificationPermission() }
                }
                .disabled(phase == .requesting)
                .padding(.top, Space.l)

                PerchTextButton(title: "Not now", color: Palette.mist) {
                    onContinue()
                }
            }
            .padding(.horizontal, Space.l)
        }
    }

    private var deniedRecovery: some View {
        StepScaffold(
            icon: "gearshape",
            title: "Notifications\nare off.",
            subtitle: "Without notifications, Perch can't nudge you when you're slouching in the background. You can turn them on anytime in Settings."
        ) {
            VStack(spacing: Space.m) {
                PerchPrimaryButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .padding(.top, Space.l)

                PerchTextButton(title: "Continue anyway", color: Palette.mist) {
                    onContinue()
                }
            }
            .padding(.horizontal, Space.l)
        }
    }

    private var requestingLabel: String {
        phase == .requesting ? "Requesting…" : "Allow access"
    }

    private func requestNotificationPermission() async {
        phase = .requesting
        await nudge.requestNotificationPermission()

        // Check the actual authorization status after the prompt.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        withAnimation {
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                phase = .authorized
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    onContinue()
                }
            case .denied:
                phase = .denied
            case .notDetermined:
                phase = .priming
            @unknown default:
                phase = .priming
            }
        }
    }
}

// MARK: - Step 4: Social proof / testimonials (placeholders)

private struct SocialProofStep: View {
    @State private var currentPage = 0
    @State private var autoTimer: Timer?

    var body: some View {
        StepScaffold(
            icon: "heart",
            title: "People love\nliving upright.",
            subtitle: "Most people feel more aware of their posture within a few weeks of leaving Perch on."
        ) {
            VStack(spacing: Space.m) {
                // Paged carousel — each testimonial gets its own card.
                TabView(selection: $currentPage) {
                    ForEach(Array(testimonials.enumerated()), id: \.offset) { idx, t in
                        testimonialCard(t)
                            .tag(idx)
                            .padding(.horizontal, Space.xl)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 200)

                // Custom dot indicator.
                HStack(spacing: 8) {
                    ForEach(0..<testimonials.count, id: \.self) { i in
                        Capsule()
                            .fill(i == currentPage ? Palette.sage : Palette.hairline)
                            .frame(width: i == currentPage ? 18 : 7, height: 7)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)
                    }
                }
            }
            .padding(.top, Space.l)
            .onAppear { startAutoAdvance() }
            .onDisappear { autoTimer?.invalidate() }
        }
    }

    private func testimonialCard(_ t: Testimonial) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // 5-star row — soft amber stars, not loud.
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.amberSoft)
                }
            }

            Text(t.quote)
                .font(.system(.subheadline, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Text("— \(t.name)")
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(Palette.mist)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
    }

    /// Gently auto-advance through testimonials every 5 seconds.
    private func startAutoAdvance() {
        autoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in
                withAnimation { currentPage = (currentPage + 1) % testimonials.count }
            }
        }
    }
}

// TODO: Replace with real reviews before shipping.
private struct Testimonial: Identifiable {
    let id = UUID()
    let name: String
    let quote: String
}

private let testimonials: [Testimonial] = [
    Testimonial(
        name: "Jamie L.",
        quote: "I didn't think I'd notice a difference, but after two weeks my neck doesn't ache at the end of the day anymore. Quietest, most useful app I own."
    ),
    Testimonial(
        name: "Dr. Rivera",
        quote: "As a PT, I recommend Perch to patients who want a gentle reminder to sit tall during long desk days. It's the simplest posture tool I've seen."
    ),
    Testimonial(
        name: "Sam K.",
        quote: "I literally forget it's there until I feel that soft buzz. Then I sit up and go back to work. Effortless."
    ),
]

// MARK: - Step 5: Calibrate (hold-to-capture, skippable)

private struct CalibrateStep: View {
    let onCalibrate: () -> Void
    let onSkip: () -> Void
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

                if capturePhase != .captured {
                    PerchTextButton(title: "Skip for now", color: Palette.mist) {
                        onSkip()
                    }
                    .padding(.top, Space.m)
                }
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
