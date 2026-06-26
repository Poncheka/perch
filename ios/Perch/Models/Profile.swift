//
//  Profile.swift
//  Perch
//
//  User profile + settings. Mirrors the Supabase `profiles` table.
//  Marked nonisolated + Sendable for Supabase decoding on background threads.
//

import Foundation

/// How Perch delivers a nudge when posture slips.
nonisolated enum NudgeStyle: String, Codable, CaseIterable, Identifiable, Sendable {
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
nonisolated struct Clock: Codable, Equatable, Sendable {
    var hour: Int
    var minute: Int

    /// Minutes since midnight, for easy range comparison.
    var minutes: Int { hour * 60 + minute }

    static let defaultQuietStart = Clock(hour: 22, minute: 0)
    static let defaultQuietEnd = Clock(hour: 7, minute: 0)
}

/// Mirrors the `profiles` table (native Supabase Auth — id references auth.users).
nonisolated struct Profile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var email: String?
    /// The name fellow circle members see. Set once after first sign-in.
    var displayName: String?
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

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case baselineAngle = "baseline_angle"
        case sensitivity
        case nudgeStyle = "nudge_style"
        case quietStartHour = "quiet_start_hour"
        case quietStartMinute = "quiet_start_minute"
        case quietEndHour = "quiet_end_hour"
        case quietEndMinute = "quiet_end_minute"
        case muteOnCall = "mute_on_call"
        case muteWhileMoving = "mute_while_moving"
        case createdAt = "created_at"
    }

    init(id: String, email: String?, displayName: String?, baselineAngle: Double,
         sensitivity: Double, nudgeStyle: NudgeStyle, quietStart: Clock,
         quietEnd: Clock, muteOnCall: Bool, muteWhileMoving: Bool,
         createdAt: Date) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.baselineAngle = baselineAngle
        self.sensitivity = sensitivity
        self.nudgeStyle = nudgeStyle
        self.quietStart = quietStart
        self.quietEnd = quietEnd
        self.muteOnCall = muteOnCall
        self.muteWhileMoving = muteWhileMoving
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        baselineAngle = try c.decodeIfPresent(Double.self, forKey: .baselineAngle) ?? 0
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 0.5
        nudgeStyle = (try? c.decodeIfPresent(NudgeStyle.self, forKey: .nudgeStyle)) ?? .haptic
        let sh = try c.decodeIfPresent(Int.self, forKey: .quietStartHour) ?? 22
        let sm = try c.decodeIfPresent(Int.self, forKey: .quietStartMinute) ?? 0
        quietStart = Clock(hour: sh, minute: sm)
        let eh = try c.decodeIfPresent(Int.self, forKey: .quietEndHour) ?? 7
        let em = try c.decodeIfPresent(Int.self, forKey: .quietEndMinute) ?? 0
        quietEnd = Clock(hour: eh, minute: em)
        muteOnCall = try c.decodeIfPresent(Bool.self, forKey: .muteOnCall) ?? true
        muteWhileMoving = try c.decodeIfPresent(Bool.self, forKey: .muteWhileMoving) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encode(baselineAngle, forKey: .baselineAngle)
        try c.encode(sensitivity, forKey: .sensitivity)
        try c.encode(nudgeStyle, forKey: .nudgeStyle)
        try c.encode(quietStart.hour, forKey: .quietStartHour)
        try c.encode(quietStart.minute, forKey: .quietStartMinute)
        try c.encode(quietEnd.hour, forKey: .quietEndHour)
        try c.encode(quietEnd.minute, forKey: .quietEndMinute)
        try c.encode(muteOnCall, forKey: .muteOnCall)
        try c.encode(muteWhileMoving, forKey: .muteWhileMoving)
        try c.encode(createdAt, forKey: .createdAt)
    }

    static func makeDefault(id: String = UUID().uuidString) -> Profile {
        Profile(
            id: id,
            email: nil,
            displayName: nil,
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
