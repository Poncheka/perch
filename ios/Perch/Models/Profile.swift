//
//  Profile.swift
//  Perch
//
//  User profile + settings. Mirrors the Supabase `profiles` table so it can
//  later be persisted remotely without changing the rest of the app.
//

import Foundation

/// How Perch delivers a nudge when posture slips.
enum NudgeStyle: String, Codable, CaseIterable, Identifiable {
    case haptic
    case sound
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .haptic: return "Haptic"
        case .sound: return "Sound"
        case .both: return "Both"
        }
    }

    var usesHaptic: Bool { self == .haptic || self == .both }
    var usesSound: Bool { self == .sound || self == .both }
}

/// A simple time-of-day value (hour + minute) for quiet hours.
struct Clock: Codable, Equatable {
    var hour: Int
    var minute: Int

    /// Minutes since midnight, for easy range comparison.
    var minutes: Int { hour * 60 + minute }

    static let defaultQuietStart = Clock(hour: 22, minute: 0)
    static let defaultQuietEnd = Clock(hour: 7, minute: 0)
}

/// Mirrors the `profiles` table.
struct Profile: Codable, Equatable {
    var id: String
    var email: String?
    /// Calibrated baseline forward-tilt captured during onboarding (degrees).
    var baselineAngle: Double
    /// 0...1 — higher means more forgiving (larger slouch threshold).
    var sensitivity: Double
    var nudgeStyle: NudgeStyle
    var quietStart: Clock
    var quietEnd: Clock
    var muteOnCall: Bool
    var muteWhileMoving: Bool
    var createdAt: Date

    static func makeDefault(id: String = UUID().uuidString) -> Profile {
        Profile(
            id: id,
            email: nil,
            baselineAngle: 0,
            sensitivity: 0.5,
            nudgeStyle: .haptic,
            quietStart: .defaultQuietStart,
            quietEnd: .defaultQuietEnd,
            muteOnCall: true,
            muteWhileMoving: true,
            createdAt: Date()
        )
    }

    /// Slouch threshold in degrees, derived from sensitivity.
    /// Sensitivity 0 → strict (~8°), 1 → forgiving (~20°).
    var slouchThreshold: Double {
        8 + sensitivity * 12
    }
}
