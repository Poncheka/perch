//
//  HomeView.swift
//  Perch
//
//  The main "Today" screen. Almost empty by design: a single breathing status
//  ring, one warm status line, and a quiet snooze button. All states use the
//  warm paper background — live state is conveyed through the ring color and
//  status line only.
//
//  On first launch after onboarding, a calm calibration overlay appears:
//  "Sit the way you'd like to sit all day" with a hold-steady capture.
//

import SwiftUI

struct HomeView: View {
    @Binding var showFirstCalibration: Bool

    @Environment(PerchStore.self) private var store
    @Environment(PostureSource.self) private var source
    @Environment(PostureEngine.self) private var engine

    @State private var showDevPanel = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showCircles = false
    @State private var tapCount = 0
    @State private var tapResetTask: Task<Void, Never>?

    /// Hold-steady calibration state for first-run (and optional re-trigger).
    @State private var calibrationPhase: CapturePhase = .ready

    private var slouchProgress: Double {
        let t = store.profile.slouchThreshold
        guard t > 0 else { return 0 }
        return min(1, max(0, source.neckAngle / t))
    }

    private let warmupThreshold: Double = 150
    private var isWarmingUp: Bool {
        engine.state.isMonitoring && engine.monitoredSeconds < warmupThreshold
    }

    var body: some View {
        ZStack {
            PerchBackground()

            if showFirstCalibration {
                calibrationOverlay
                    .transition(.opacity)
            }

            content
        }
        .sheet(isPresented: $showDevPanel) { DevPanelView() }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showCircles) { CirclesView() }
        .task { refreshCirclesCount() }
        .onChange(of: auth.isSignedIn) { _, _ in refreshCirclesCount() }
    }

    // MARK: - Calibration overlay (first-run)

    private var calibrationOverlay: some View {
        ZStack {
            PerchBackground()

            VStack(spacing: Space.xxl) {
                Spacer()

                VStack(spacing: Space.l) {
                    Image(systemName: calibrationIcon)
                        .font(.system(size: 46, weight: .thin))
                        .foregroundStyle(Palette.sage)
                        .frame(height: 64)

                    Text(calibrationTitle)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)

                    Text(calibrationSubtitle)
                        .font(.system(.body, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                CalibrationHoldView(
                    liveAngle: source.liveRawTilt,
                    phase: $calibrationPhase,
                    onCaptured: {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        source.calibrate()
                        store.setBaseline(0)
                        store.completeCalibration()
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            withAnimation(.easeInOut(duration: 0.6)) {
                                showFirstCalibration = false
                            }
                        }
                    }
                )
                .frame(width: 200, height: 200)

                if calibrationPhase != .captured {
                    PerchTextButton(title: "Skip for now", color: Palette.mist) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        source.calibrate()
                        store.setBaseline(0)
                        store.completeCalibration()
                        withAnimation(.easeInOut(duration: 0.6)) {
                            showFirstCalibration = false
                        }
                    }
                    .padding(.top, Space.m)
                }

                Spacer()
            }
            .padding(.horizontal, Space.xl)
        }
        .zIndex(10)
    }

    private var calibrationIcon: String {
        switch calibrationPhase {
        case .ready: return "figure.seated.side"
        case .capturing: return "scope"
        case .captured: return "checkmark.circle"
        }
    }

    private var calibrationTitle: String {
        switch calibrationPhase {
        case .ready: return "Sit the way you'd\nlike to sit all day."
        case .capturing: return "Hold steady…"
        case .captured: return "Perfectly set."
        }
    }

    private var calibrationSubtitle: String {
        switch calibrationPhase {
        case .ready:
            return "Get comfortable and upright. Then hold your head still — the ring fills when you're steady."
        case .capturing:
            return "Almost there. Keep your head still just a moment longer."
        case .captured:
            return "That's your good posture. Perch will gently let you know whenever you drift away from it."
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            ringBlock
            Spacer()
            footer
        }
        .padding(.horizontal, Space.xl)
        .padding(.bottom, Space.xl)
    }

    private var topBar: some View {
        HStack {
            quietIcon("chart.bar") { showHistory = true }
            Spacer()
            Eyebrow(text: "Today", color: Palette.mist)
            Spacer()
            quietIcon("slider.horizontal.3") { showSettings = true }
        }
        .padding(.top, Space.s)
    }

    private func quietIcon(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.mist)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private var ringBlock: some View {
        VStack(spacing: Space.xxl) {
            StatusRing(
                percent: engine.uprightPct,
                color: engine.state.ringColor,
                isMonitoring: engine.state.isMonitoring,
                slouchProgress: slouchProgress,
                isWarmingUp: isWarmingUp,
                isSnoozed: engine.isSnoozing,
                onResume: { engine.cancelSnooze() }
            )
            .overlay { if !engine.isSnoozing && !isWarmingUp { ringNumberTapTarget } }

            statusLine
            circlesCard
        }
    }

    /// Invisible triple-tap target over the numeral to open the dev panel.
    private var ringNumberTapTarget: some View {
        Color.clear
            .frame(width: 160, height: 120)
            .contentShape(Rectangle())
            .onTapGesture { registerDevTap() }
            .offset(y: -10)
    }

    private var statusLine: some View {
        VStack(spacing: Space.s) {
            if isWarmingUp {
                Text("Warming up — keep your AirPods in a little longer.")
                    .font(.system(.title3, design: .default, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            } else if engine.state == .muted, let line = engine.muteStatusLine {
                Text(line)
                    .font(.system(.title3, design: .default, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .id(line)
                    .animation(.easeInOut(duration: 0.4), value: line)
            } else {
                Text(engine.state.statusLine)
                    .font(.system(.title3, design: .default, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .id(engine.state.statusLine)
                    .animation(.easeInOut(duration: 0.4), value: engine.state.statusLine)
            }
        }
        .frame(maxWidth: 320)
    }

    // MARK: - Circles card

    @ViewBuilder
    private var circlesCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            showCircles = true
        } label: {
            HStack(spacing: Space.l) {
                Image(systemName: "person.2")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Palette.sage)

                VStack(alignment: .leading, spacing: 2) {
                    Text(circlesCardTitle)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(circlesCardSubtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.mist)
            }
            .padding(Space.l)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.surface)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Space.s)
    }

    @Environment(Database.self) private var db
    @Environment(AuthService.self) private var auth

    @State private var circlesCount: Int = 0

    private var circlesCardTitle: String {
        guard auth.isSignedIn else { return "Circles" }
        return circlesCount > 0 ? "Your circles (\(circlesCount))" : "Circles"
    }

    private var circlesCardSubtitle: String {
        guard auth.isSignedIn else {
            return "Sign in to share posture with friends."
        }
        return circlesCount > 0
            ? "Tap to see your circle" + (circlesCount > 1 ? "s" : "")
            : "Create or join a supportive posture circle."
    }

    private func refreshCirclesCount() {
        guard let uid = auth.userId else { circlesCount = 0; return }
        Task {
            let count = (await db.circlesForUser(uid)).count
            await MainActor.run { circlesCount = count }
        }
    }

    private var footer: some View {
        VStack(spacing: Space.m) {
            if engine.isSnoozing, let until = engine.snoozeUntil {
                snoozeActive(until: until)
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    engine.snooze(minutes: 30)
                } label: {
                    Text("Snooze 30 min")
                        .font(.system(.subheadline, design: .default, weight: .medium))
                        .foregroundStyle(Palette.mist)
                        .padding(.vertical, Space.m)
                        .padding(.horizontal, Space.xl)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func snoozeActive(until: Date) -> some View {
        Button {
            engine.cancelSnooze()
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "moon.zzz.fill")
                Text("Snoozed until \(until.formatted(date: .omitted, time: .shortened)) · Resume")
            }
            .font(.system(.subheadline, design: .default, weight: .medium))
            .foregroundStyle(Palette.mist)
            .padding(.vertical, Space.m)
            .padding(.horizontal, Space.xl)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hidden dev panel trigger (triple-tap the number)

    private func registerDevTap() {
        tapCount += 1
        tapResetTask?.cancel()
        if tapCount >= 3 {
            tapCount = 0
            UISelectionFeedbackGenerator().selectionChanged()
            showDevPanel = true
            return
        }
        tapResetTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { tapCount = 0 }
        }
    }
}
