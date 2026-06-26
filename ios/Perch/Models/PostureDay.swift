//
//  PostureDay.swift
//  Perch
//
//  One rolled-up record per day. Mirrors the Supabase `posture_days` table.
//

import Foundation

nonisolated struct PostureDay: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var userId: String
    /// Calendar day key (start of day).
    var date: Date
    /// 0...100 — share of monitored time spent upright.
    var uprightPct: Double
    var slouchEvents: Int
    var uprightSeconds: Double
    var monitoredSeconds: Double

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case uprightPct = "upright_pct"
        case slouchEvents = "slouch_events"
        case uprightSeconds = "upright_seconds"
        case monitoredSeconds = "monitored_seconds"
    }

    static func makeEmpty(userId: String, date: Date) -> PostureDay {
        PostureDay(
            id: UUID().uuidString,
            userId: userId,
            date: Calendar.current.startOfDay(for: date),
            uprightPct: 0,
            slouchEvents: 0,
            uprightSeconds: 0,
            monitoredSeconds: 0
        )
    }
}
