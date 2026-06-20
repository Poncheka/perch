//
//  PostureDay.swift
//  Perch
//
//  One rolled-up record per day. Mirrors the Supabase `posture_days` table.
//

import Foundation

struct PostureDay: Codable, Equatable, Identifiable {
    var id: String
    var userId: String
    /// Calendar day key (start of day).
    var date: Date
    /// 0...100 — share of monitored time spent upright.
    var uprightPct: Double
    var slouchEvents: Int

    /// Seconds counters used to recompute `uprightPct` as the day progresses.
    var uprightSeconds: Double
    var monitoredSeconds: Double

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
