//
//  PostureEngine.swift
//  Perch
//
//  The state machine. Samples PostureSource on a steady cadence, derives the
//  PostureState, fires nudges with a grace period, respects mute rules, and
//  rolls posture up into the day's upright %. All sensor input flows in through
//  PostureSource — the engine never touches AirPods APIs directly.
//

import SwiftUI

@Observable
@MainActor
final class PostureEngine {
    // MARK: - Live, observable outputs

    private(set) var state: PostureState = .idle
    /// Today's rolling upright percentage (0...100).
    private(set) var uprightPct: Double = 0
    /// Seconds the user has been monitored today (drives "warming up" state).
    var monitoredSeconds: Double { today.monitoredSeconds }
    /// Snooze countdown end, if active.
    private(set) var snoozeUntil: Date?

    // MARK: - Dependencies

    private let source: PostureSource
    private let store: PerchStore
    private let nudge: NudgeService

    // MARK: - Tuning

    /// Grace period a slouch must persist before nudging.
    private let graceSeconds: Double = 6
    /// Hysteresis so the ring doesn't flicker right at the threshold.
    private let recoverMargin: Double = 3
    /// Minimum gap between repeat nudges while still slouching.
    private let renudgeInterval: Double = 14

    // MARK: - Internal timing state

    private var sampleTimer: Timer?
    private let sampleInterval: Double = 0.25
    private var slouchStart: Date?
    private var lastNudge: Date?
    private var nudgeStreak = 0
    private var today: PostureDay

    var appIsActive = true

    init(source: PostureSource, store: PerchStore, nudge: NudgeService) {
        self.source = source
        self.store = store
        self.nudge = nudge
        self.today = store.todayRecord()
        self.uprightPct = today.uprightPct
        start()
    }

    func start() {
        sampleTimer?.invalidate()
        let t = Timer(timeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        sampleTimer = t
    }

    func stop() {
        sampleTimer?.invalidate()
        sampleTimer = nil
    }

    // MARK: - Snooze

    func snooze(minutes: Int) {
        snoozeUntil = Calendar.current.date(byAdding: .minute, value: minutes, to: Date())
    }

    func cancelSnooze() {
        snoozeUntil = nil
        // Immediately recompute posture state so the status line updates at once.
        sample()
    }

    var isSnoozing: Bool {
        guard let until = snoozeUntil else { return false }
        if until <= Date() {
            snoozeUntil = nil
            return false
        }
        return true
    }

    // MARK: - Sampling loop

    private func sample() {
        rolloverDayIfNeeded()

        let connected = source.airpodsConnected
        let angle = source.neckAngle
        let profile = store.profile

        guard connected else {
            transition(to: .idle)
            return
        }

        // Count monitored time + upright time for the daily roll-up.
        let isUpright = angle <= profile.slouchThreshold
        today.monitoredSeconds += sampleInterval
        if isUpright { today.uprightSeconds += sampleInterval }
        recomputeUpright()

        // Are we silently muted?
        if currentMuteReason() != nil {
            slouchStart = nil
            transition(to: .muted)
            persistThrottled()
            return
        }

        if isUpright {
            // Recovered (with hysteresis) — clear slouch tracking.
            if angle <= profile.slouchThreshold - recoverMargin || state != .nudging {
                slouchStart = nil
                nudgeStreak = 0
                lastNudge = nil
                transition(to: .monitoringGood)
            }
            persistThrottled()
            return
        }

        // Past threshold — slouching.
        if slouchStart == nil { slouchStart = Date() }
        let sustained = Date().timeIntervalSince(slouchStart ?? Date()) >= graceSeconds

        if sustained {
            maybeNudge(profile: profile)
            transition(to: .nudging)
        } else {
            transition(to: .monitoringSlouch)
        }
        persistThrottled()
    }

    private func maybeNudge(profile: Profile) {
        let now = Date()
        if let last = lastNudge, now.timeIntervalSince(last) < renudgeInterval {
            return
        }
        lastNudge = now
        nudgeStreak += 1
        if state != .nudging {
            today.slouchEvents += 1
        }
        // Escalate only slightly with continued slouching.
        let intensity = min(1.0, 0.3 + Double(nudgeStreak) * 0.2)
        nudge.nudge(style: profile.nudgeStyle, intensity: intensity, appActive: appIsActive)
    }

    // MARK: - Mute rules

    /// Returns a human-readable reason if monitoring should be silent.
    private func currentMuteReason() -> String? {
        if isSnoozing { return "Snoozed" }
        if isWithinQuietHours() { return "Quiet hours" }
        if store.profile.muteOnCall && source.isOnCall { return "On a call" }
        if store.profile.muteWhileMoving && source.isMoving { return "Moving" }
        return nil
    }

    var muteReason: String? { currentMuteReason() }

    /// Human-readable status line for each mute reason, so the UI never shows the ambiguous
    /// generic `.muted` copy when we know exactly why monitoring is silent.
    var muteStatusLine: String? {
        guard let reason = currentMuteReason() else { return nil }
        switch reason {
        case "Snoozed": return "Paused for now. Enjoy the moment."
        case "Quiet hours": return "Quiet hours — resting."
        case "On a call": return "Muted while you're on a call."
        case "Moving": return "Muted while you're moving."
        default: return nil
        }
    }

    private func isWithinQuietHours() -> Bool {
        let profile = store.profile
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMin = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let start = profile.quietStart.minutes
        let end = profile.quietEnd.minutes
        if start == end { return false }
        if start < end {
            return nowMin >= start && nowMin < end
        } else {
            // Range crosses midnight (e.g. 22:00 → 07:00).
            return nowMin >= start || nowMin < end
        }
    }

    // MARK: - State + persistence

    private func transition(to newState: PostureState) {
        guard state != newState else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            state = newState
        }
    }

    private func recomputeUpright() {
        guard today.monitoredSeconds > 0 else { uprightPct = 0; return }
        let pct = today.uprightSeconds / today.monitoredSeconds * 100
        today.uprightPct = pct
        uprightPct = pct
    }

    private var lastPersist = Date.distantPast
    private func persistThrottled() {
        guard Date().timeIntervalSince(lastPersist) > 3 else { return }
        lastPersist = Date()
        store.persistDay(today)
    }

    private func rolloverDayIfNeeded() {
        if !Calendar.current.isDateInToday(today.date) {
            store.persistDay(today)
            today = store.todayRecord()
            recomputeUpright()
        }
    }
}
