//
//  HomeView.swift
//  Perch
//
//  The main "Today" screen. Almost empty by design: a single breathing status
//  ring, one warm status line, and a quiet snooze button. The "monitoring"
//  state shifts the surface to deep navy for an Oura-like focus moment.
//

import SwiftUI

struct HomeView: View {
    @Environment(PerchStore.self) private var store
    @Environment(PostureSource.self) private var source
    @Environment(PostureEngine.self) private var engine

    @State private var showDevPanel = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showCircles = false
    @State private var tapCount = 0
    @State private var tapResetTask: Task<Void, Never>?

    private var slouchProgress: Double {
        let t = store.profile.slouchThreshold
        guard t > 0 else { return 0 }
        return min(1, max(0, source.neckAngle / t))
    }

    /// The monitoredSeconds threshold for showing a real value (150 s).
    private let warmupThreshold: Double = 150
    private var isWarmingUp: Bool {
        engine.state.isMonitoring && engine.monitoredSeconds < warmupThreshold
    }

    var body: some View {
        ZStack {
            PerchBackground()
            content
        }
        .sheet(isPresented: $showDevPanel) { DevPanelView() }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showCircles) { CirclesView() }
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
                isWarmingUp: isWarmingUp
            )
            .overlay { ringNumberTapTarget }

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

    private var circlesCardTitle: String {
        guard let email = auth.email else { return "Circles" }
        let count = circlesCount
        return count > 0 ? "Your circles (\(count))" : "Circles"
    }

    private var circlesCardSubtitle: String {
        guard let email = auth.email else {
            return "Sign in to share posture with friends."
        }
        let count = circlesCount
        return count > 0
            ? "Tap to see your circle" + (count > 1 ? "s" : "")
            : "Create or join a supportive posture circle."
    }

    /// Number of circles the signed-in user belongs to.
    private var circlesCount: Int {
        guard let email = auth.email else { return 0 }
        let db = Database()
        return db.circlesForUser(email).count
    }

    // MARK: - Environment helpers

    @Environment(AuthService.self) private var auth

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
