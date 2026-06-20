//
//  NudgeService.swift
//  Perch
//
//  Delivers gentle nudges: soft haptics, an optional non-startling tone, and a
//  background local notification. Never loud, never sudden.
//

import SwiftUI
import AVFoundation
import UserNotifications
import AudioToolbox

@Observable
@MainActor
final class NudgeService {
    private var player: AVAudioPlayer?

    /// Fire a nudge respecting the user's chosen style. `intensity` (0...1)
    /// lets the engine escalate *slightly* if a slouch persists.
    func nudge(style: NudgeStyle, intensity: Double, appActive: Bool) {
        if style.usesHaptic {
            let generator = UIImpactFeedbackGenerator(style: intensity > 0.6 ? .medium : .soft)
            generator.prepare()
            generator.impactOccurred(intensity: 0.5 + intensity * 0.4)
        }
        if style.usesSound {
            playSoftTone()
        }
        if !appActive {
            scheduleNotification()
        }
    }

    /// A short, gentle wood-block style system sound — calm, never alarming.
    private func playSoftTone() {
        // 1306 is a soft "Tink"-like system sound; pleasant and quiet.
        AudioServicesPlaySystemSound(SystemSoundID(1306))
    }

    // MARK: - Notifications

    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func scheduleNotification() {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "A gentle nudge"
        content.body = "Ease your head back up — you've been leaning forward a while."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "perch.nudge.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
