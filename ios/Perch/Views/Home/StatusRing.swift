//
//  StatusRing.swift
//  Perch
//
//  The signature live status ring with a slow "breathing" pulse. Shows today's
//  upright % as a large, light-weight numeral inside. During the "warming up"
//  phase (<150 monitored seconds) it shows a soft dash instead of a volatile
//  number, then fades in the real value. When snoozed, the number is replaced
//  by a pause button that taps to resume.
//

import SwiftUI

struct StatusRing: View {
    let percent: Double
    let color: Color
    let isMonitoring: Bool
    /// 0...1 — how far toward the slouch threshold the user currently is.
    let slouchProgress: Double
    /// Whether the value is still warming up (monitoredSeconds < 150).
    let isWarmingUp: Bool
    /// When true, the big number is replaced by a pause icon that can be tapped.
    let isSnoozed: Bool
    /// Tap the pause icon to resume monitoring.
    var onResume: (() -> Void)?

    @State private var breathe = false

    private var displayValue: Int { Int(percent.rounded()) }

    var body: some View {
        ZStack {
            // Soft outer halo that breathes.
            Circle()
                .fill(color.opacity(isMonitoring ? (isWarmingUp ? 0.05 : 0.10) : 0.04))
                .scaleEffect(breathe ? 1.06 : 0.94)
                .blur(radius: 18)

            // Track.
            Circle()
                .stroke(Palette.hairline, lineWidth: 14)

            // Progress arc (today's upright %).
            Circle()
                .trim(from: 0, to: max(0.001, isWarmingUp ? 0 : percent / 100))
                .stroke(
                    color.opacity(isMonitoring ? (isWarmingUp ? 0.25 : 1) : 0.35),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: percent)

            // Inner breathing fill for depth.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(isMonitoring ? 0.14 : 0.05), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 150
                    )
                )
                .scaleEffect(breathe ? 1.04 : 0.96)

            // Inner numeral (or warming-up dash, or snooze pause button).
            VStack(spacing: 6) {
                if isWarmingUp {
                    Text("—")
                        .font(.system(size: 96, weight: .thin, design: .default))
                        .foregroundStyle(Palette.ink.opacity(0.5))
                } else if isSnoozed {
                    pauseButton
                } else {
                    Text("\(displayValue)")
                        .font(.system(size: 96, weight: .thin, design: .default))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: percent))
                        .animation(.easeInOut(duration: 0.5), value: displayValue)
                        .monospacedDigit()
                }
                Eyebrow(text: eyebrowText)
            }
        }
        .frame(width: 268, height: 268)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var eyebrowText: String {
        if isWarmingUp { return "Warming up" }
        if isSnoozed { return "Paused" }
        return "Upright score"
    }

    // MARK: - Pause button (shown when snoozed)

    private var pauseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            onResume?()
        } label: {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(Palette.mist)
        }
        .buttonStyle(.plain)
    }
}
