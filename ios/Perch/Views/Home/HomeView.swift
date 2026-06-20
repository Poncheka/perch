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
    @State private var tapCount = 0
    @State private var tapResetTask: Task<Void, Never>?

    /// Deep navy focus surface while actively monitoring (good or slouching).
    private var useFocusSurface: Bool {
        switch engine.state {
        case .monitoringGood, .monitoringSlouch, .nudging: return true
        case .idle, .muted: return false
        }
    }

    private var slouchProgress: Double {
        let t = store.profile.slouchThreshold
        guard t > 0 else { return 0 }
        return min(1, max(0, source.neckAngle / t))
    }

    var body: some View {
        ZStack {
            background
            content
        }
        .animation(.easeInOut(duration: 0.8), value: useFocusSurface)
        .sheet(isPresented: $showDevPanel) { DevPanelView() }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if useFocusSurface {
            ZStack {
                Palette.navy
                RadialGradient(
                    colors: [engine.state.ringColor.opacity(0.16), .clear],
                    center: .center,
                    startRadius: 40,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        } else {
            PerchBackground()
        }
    }

    private var onFocus: Bool { useFocusSurface }
    private var primaryText: Color { onFocus ? Palette.cream : Palette.ink }
    private var secondaryText: Color { onFocus ? Color(hex: 0x9FB0B6) : Palette.mist }

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
            Eyebrow(text: "Today", color: secondaryText)
            Spacer()
            quietIcon("slider.horizontal.3") { showSettings = true }
        }
        .padding(.top, Space.s)
    }

    private func quietIcon(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(secondaryText)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private var ringBlock: some View {
        VStack(spacing: Space.xxl) {
            StatusRing(
                percent: engine.uprightPct,
                color: ringColorForSurface,
                isMonitoring: engine.state.isMonitoring,
                slouchProgress: slouchProgress
            )
            .overlay { ringNumberTapTarget }

            statusLine
        }
    }

    /// On the navy focus surface the inner numeral needs to read cream.
    private var ringColorForSurface: Color { engine.state.ringColor }

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
            Text(engine.state.statusLine)
                .font(.system(.title3, design: .default, weight: .regular))
                .foregroundStyle(primaryText)
                .multilineTextAlignment(.center)
                .transition(.opacity)
                .id(engine.state.statusLine)
                .animation(.easeInOut(duration: 0.4), value: engine.state.statusLine)

            if let reason = engine.muteReason {
                Eyebrow(text: reason, color: secondaryText)
            }
        }
        .frame(maxWidth: 320)
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
                        .foregroundStyle(secondaryText)
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
            .foregroundStyle(secondaryText)
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
