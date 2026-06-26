//
//  CircleModel.swift
//  Perch
//
//  Oura-style shared circles. Users create or join circles to see each other's
//  posture scores — supportive, not competitive.
//
//  Supabase tables:
//    circles:        id, name, owner_id, invite_code (unique), created_at
//    circle_members: id, circle_id, user_id, joined_at, role
//
//  RLS: a user may read circle_members and shared posture metrics ONLY for
//  circles they belong to. No data is visible outside a user's circles.
//

import Foundation

// MARK: - Circle

nonisolated struct CircleModel: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var ownerId: String
    var inviteCode: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerId = "owner_id"
        case inviteCode = "invite_code"
        case createdAt = "created_at"
    }

    static func make(name: String, ownerId: String) -> CircleModel {
        CircleModel(
            id: UUID().uuidString,
            name: name,
            ownerId: ownerId,
            inviteCode: generateInviteCode(),
            createdAt: Date()
        )
    }

    /// 6-character alphanumeric invite code (uppercase, no ambiguous chars).
    static func generateInviteCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}

// MARK: - Circle member

nonisolated enum MemberRole: String, Codable, CaseIterable, Sendable {
    case owner
    case member
}

nonisolated struct CircleMember: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var circleId: String
    var userId: String
    var joinedAt: Date
    var role: MemberRole

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case role
    }

    static func make(circleId: String, userId: String, role: MemberRole) -> CircleMember {
        CircleMember(
            id: UUID().uuidString,
            circleId: circleId,
            userId: userId,
            joinedAt: Date(),
            role: role
        )
    }
}

// MARK: - Member summary (for display)

/// A flattened view of a circle member with their posture stats for today.
/// In Supabase this is built from a join across `circle_members`
/// and `posture_days`.
struct CircleMemberSummary: Identifiable {
    let id: String          ///< member id
    let name: String        ///< display name (from profile / email)
    let todayUprightPct: Double
    let streak: Int
    let weeklyAvg: Double

    var trendColor: String {
        switch weeklyAvg {
        case 80...100: return "sage"
        case 60..<80: return "amber"
        default: return "amberSoft"
        }
    }
}
