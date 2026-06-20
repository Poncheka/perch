//
//  OnboardingView.swift
//  Perch
//
//  First-launch flow: ~5 short, swipeable, skippable steps that end at the
//  paywall. Warm, brief, reassuring copy throughout.
//

import SwiftUI
import CoreMotion

struct OnboardingView: View {
    @Environment(PerchStore.self) private var store
    @Environment(PostureSource.self) private var source
    @Environment(NudgeService.self) private var nudge

    @State private var step = 0
    @State private var supportedDemo = true

    private let lastStep = 4

    var body: some View {
        ZStack {
            PerchBackground()
            VStack(spacing: 0) {
                header
                TabView(selection: $step) {
                    WelcomeStep().tag(0)
                    HowItWorksStep().tag(1)
                    CompatibilityStep(supported: $supportedDemo).tag(2)
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
            // Skippable dots area — show Skip until the calibrate step.
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
            // Steps 3 and 4 carry their own primary buttons.
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

private struct CompatibilityStep: View {
    @Binding var supported: Bool
    @State private var checking = true

    var body: some View {
        StepScaffold(
            icon: supported ? "checkmark.seal" : "exclamationmark.triangle",
            title: checking ? "Checking your\nAirPods…" : (supported ? "You're all set." : "Not supported yet."),
            subtitle: checking
                ? "One moment while we make sure your AirPods can sense motion."
                : (supported
                    ? "Your AirPods support motion sensing. Perch is ready to keep you upright."
                    : "These AirPods don't have a motion sensor. Perch needs AirPods (3rd gen), Pro, or Max.")
        ) {
            if !checking {
                // Quiet toggle so the "not supported" state can be previewed.
                Button {
                    withAnimation { supported.toggle() }
                } label: {
                    Text(supported ? "Preview unsupported state" : "Preview supported state")
                        .font(.footnote)
                        .foregroundStyle(Palette.mist)
                }
                .buttonStyle(.plain)
                .padding(.top, Space.s)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { checking = false }
        }
    }
}

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
        // Real Motion & Fitness prompt.
        if CMMotionActivityManager.isActivityAvailable() {
            let manager = CMMotionActivityManager()
            let queue = OperationQueue()
            manager.startActivityUpdates(to: queue) { _ in
                manager.stopActivityUpdates()
            }
        }
        // Real Notifications prompt.
        await nudge.requestNotificationPermission()
        requesting = false
        onContinue()
    }
}

private struct CalibrateStep: View {
    let onCalibrate: () -> Void
    @State private var confirmed = false

    var body: some View {
        StepScaffold(
            icon: confirmed ? "checkmark.circle" : "figure.seated.side",
            title: confirmed ? "Perfectly set." : "Sit the way you'd\nlike to sit all day.",
            subtitle: confirmed
                ? "That's your good posture. Perch will gently let you know whenever you drift away from it."
                : "Get comfortable and upright. When you're ready, capture it as your baseline."
        ) {
            if !confirmed {
                PerchPrimaryButton(title: "This is my good posture") {
                    withAnimation { confirmed = true }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        onCalibrate()
                    }
                }
                .padding(.top, Space.l)
                .padding(.horizontal, Space.l)
            }
        }
    }
}
