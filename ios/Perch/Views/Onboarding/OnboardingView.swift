//
//  OnboardingView.swift
//  Perch
//
//  Three-page onboarding flow, each with its own dedicated screen:
//    0  Intro — animated figure + "Fix your posture with AirPods"
//    1  Connect your AirPods — detect via audio route
//    2  Allow notifications
//
//  Zero system prompts fire until the user reaches the relevant page.
//  Motion & Fitness permission now lives on its own dedicated screen
//  AFTER onboarding completes, BEFORE the paywall.
//

import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Environment(PerchStore.self) private var store
    @Environment(NudgeService.self) private var nudge

    @State private var step = 0
    private let lastStep = 2

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
        case 2: NotificationsPage(onFinish: finishOnboarding)
        default: EmptyView()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Color.clear.frame(height: 20)
    }

    // MARK: - Navigation

    private func advance() {
        step = min(step + 1, lastStep)
    }

    private func skipToEnd() {
        step = lastStep
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
                Text("Fix your posture\nwith AirPods")
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
                    Text("Connect your AirPods from Control Center or Settings → Bluetooth, then come back.")
                        .font(.system(.body, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }

            Spacer()

            PerchPrimaryButton(
                title: connected ? "Continue" : "Make sure your AirPods are in, then continue",
                fill: connected ? Palette.sage : Palette.amberSoft,
                foreground: connected ? Palette.cream : Palette.ink
            ) {
                onNext()
            }
        }
        .padding(.horizontal, Space.xl)
        .animation(.easeInOut(duration: 0.4), value: connected)
        .onAppear { source.updateAudioRoute() }
    }
}

// MARK: - Page 2: Allow notifications

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
        onFinish()
    }
}
