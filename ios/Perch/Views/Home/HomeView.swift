//
//  HomeView.swift
//  Perch
//
//  The "Today" tab. Purely the live sensor: a single breathing status ring
//  and the quiet "Snooze 30 min" control.
//  Nothing else — Corrections, Streak, and analytics live on the Progress tab.
//

import SwiftUI

struct HomeView: View {
    @Environment(PerchStore.self) private var store
    @Environment(PostureSource.self) private var source
    @Environment(PostureEngine.self) private var engine

    @State private var showDevPanel = false
    @State private var tapCount = 0
    @State private var tapResetTask: Task<Void, Never>?

    private var slouchProgress: Double {
        let t = store.profile.slouchThreshold
        guard t > 0 else { return 0 }
        return min(1, max(0, source.neckAngle / t))
    }

    var body: some View {
        ZStack {
            PerchBackground()

            VStack(spacing: 0) {
                Spacer()
                ringBlock
                Spacer()
                footer
            }
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.xl)
        }
        .sheet(isPresented: $showDevPanel) { DevPanelView() }
    }

    // MARK: - Ring block

    private var ringBlock: some View {
        VStack(spacing: Space.xxl) {
            StatusRing(
                percent: engine.uprightPct,
                color: engine.state.ringColor,
                isMonitoring: engine.state.isMonitoring,
                slouchProgress: slouchProgress,
                isSnoozed: engine.isSnoozing,
                onResume: { engine.cancelSnooze() }
            )
            .overlay { if !engine.isSnoozing { ringNumberTapTarget } }

            statusLine
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
            if engine.state == .muted, let line = engine.muteStatusLine {
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

    // MARK: - Footer (snooze)

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
