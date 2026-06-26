//
//  Database.swift
//  Perch
//
//  The SINGLE persistence module. When the user is signed in to Supabase, all
//  reads and writes flow to the live Postgres database. When signed out, falls
//  back to UserDefaults so core posture tracking works without an account.
//
//  Circles use the Supabase RPCs `create_circle(p_name)` and
//  `join_circle_by_code(p_code)` — never insert into circles/circle_members
//  directly.
//

import Foundation
import Supabase
import SwiftUI

@Observable
@MainActor
final class Database {
    private let supabase: SupabaseClientService
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Key {
        static let profile = "perch.profile"
        static let subscription = "perch.subscription"
        static let days = "perch.posture_days"
        static let onboarded = "perch.hasOnboarded"
        static let calibrated = "perch.hasCalibrated"
        static let circles = "perch.circles"
        static let circleMembers = "perch.circle_members"
    }

    init(supabase: SupabaseClientService) {
        self.supabase = supabase
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Whether we should use Supabase (signed in) vs local fallback.
    private var usesRemote: Bool {
        supabase.client.auth.currentSession != nil
    }

    // MARK: - Onboarding flags (local only — not worth a table)

    var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    var hasCalibrated: Bool {
        get { defaults.bool(forKey: Key.calibrated) }
        set { defaults.set(newValue, forKey: Key.calibrated) }
    }

    // MARK: - profiles

    func loadProfile() async -> Profile? {
        if usesRemote {
            return try? await supabase.client
                .from("profiles")
                .select()
                .single()
                .execute()
                .value
        }
        return decode(Profile.self, forKey: Key.profile)
    }

    func saveProfile(_ profile: Profile) async {
        if usesRemote {
            do {
                try await supabase.client
                    .from("profiles")
                    .upsert(ProfileUpsertFull(profile))
                    .execute()
            } catch {
                print("Failed to save profile: \(error)")
            }
        }
        encode(profile, forKey: Key.profile)
    }

    // MARK: - subscription

    func loadSubscription() async -> Subscription? {
        if usesRemote {
            return try? await supabase.client
                .from("subscriptions")
                .select()
                .single()
                .execute()
                .value
        }
        return decode(Subscription.self, forKey: Key.subscription)
    }

    func saveSubscription(_ subscription: Subscription) async {
        if usesRemote {
            do {
                try await supabase.client
                    .from("subscriptions")
                    .upsert(SubscriptionUpsert(subscription))
                    .execute()
            } catch {
                print("Failed to save subscription: \(error)")
            }
        }
        encode(subscription, forKey: Key.subscription)
    }

    // MARK: - posture_days

    func loadDays() async -> [PostureDay] {
        if usesRemote {
            return (try? await supabase.client
                .from("posture_days")
                .select()
                .order("date", ascending: true)
                .execute()
                .value) ?? []
        }
        return decode([PostureDay].self, forKey: Key.days) ?? []
    }

    /// Insert or update a day row (keyed by calendar date + user).
    func upsertDay(_ day: PostureDay) async {
        if usesRemote {
            do {
                try await supabase.client
                    .from("posture_days")
                    .upsert(PostureDayUpsert(day))
                    .execute()
            } catch {
                print("Failed to upsert day: \(error)")
            }
        }
        // Always keep a local copy for fast reads.
        var days = decode([PostureDay].self, forKey: Key.days) ?? []
        if let index = days.firstIndex(where: {
            $0.userId == day.userId &&
            Calendar.current.isDate($0.date, inSameDayAs: day.date)
        }) {
            days[index] = day
        } else {
            days.append(day)
        }
        days.sort { $0.date < $1.date }
        if days.count > 120 { days = Array(days.suffix(120)) }
        encode(days, forKey: Key.days)
    }

    // MARK: - circles (RPC-backed)

    /// Creates a circle via the `create_circle(p_name)` RPC. Returns the
    /// newly-created circle row. The RPC also inserts the caller as the owner
    /// in `circle_members`.
    func createCircle(name: String) async throws -> CircleModel {
        struct RPCResponse: Decodable {
            let id: String
            let name: String
            let owner_id: String
            let invite_code: String
            let created_at: String?
        }
        let result: RPCResponse = try await supabase.client
            .rpc("create_circle", params: ["p_name": name])
            .execute()
            .value
        let circle = CircleModel(
            id: result.id,
            name: result.name,
            ownerId: result.owner_id,
            inviteCode: result.invite_code,
            createdAt: parseISO(result.created_at) ?? Date()
        )
        // Cache locally.
        var circles = decode([CircleModel].self, forKey: Key.circles) ?? []
        circles.append(circle)
        encode(circles, forKey: Key.circles)
        return circle
    }

    /// Joins a circle via the `join_circle_by_code(p_code)` RPC. Returns the
    /// circle row on success, or throws on failure (invalid code, already a
    /// member, etc.). The RPC also inserts the caller into `circle_members`.
    func joinCircleByCode(_ code: String) async throws -> CircleModel {
        struct RPCResponse: Decodable {
            let id: String
            let name: String
            let owner_id: String
            let invite_code: String
            let created_at: String?
        }
        let result: RPCResponse = try await supabase.client
            .rpc("join_circle_by_code", params: ["p_code": code.uppercased()])
            .execute()
            .value
        let circle = CircleModel(
            id: result.id,
            name: result.name,
            ownerId: result.owner_id,
            inviteCode: result.invite_code,
            createdAt: parseISO(result.created_at) ?? Date()
        )
        // Cache locally.
        var circles = decode([CircleModel].self, forKey: Key.circles) ?? []
        if !circles.contains(where: { $0.id == circle.id }) {
            circles.append(circle)
        }
        encode(circles, forKey: Key.circles)
        return circle
    }

    /// Renames a circle (owner only — enforced by RLS).
    func renameCircle(_ circleId: String, to name: String) async throws {
        try await supabase.client
            .from("circles")
            .update(["name": name])
            .eq("id", value: circleId)
            .execute()
        // Update local cache.
        var circles = decode([CircleModel].self, forKey: Key.circles) ?? []
        if let idx = circles.firstIndex(where: { $0.id == circleId }) {
            circles[idx].name = name
            encode(circles, forKey: Key.circles)
        }
    }

    func loadCircles() async -> [CircleModel] {
        if usesRemote {
            return (try? await supabase.client
                .from("circles")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value) ?? []
        }
        return decode([CircleModel].self, forKey: Key.circles) ?? []
    }

    func deleteCircle(_ id: String) async {
        if usesRemote {
            do {
                try await supabase.client
                    .from("circles")
                    .delete()
                    .eq("id", value: id)
                    .execute()
            } catch {
                print("Failed to delete circle: \(error)")
            }
        }
        var circles = decode([CircleModel].self, forKey: Key.circles) ?? []
        circles.removeAll { $0.id == id }
        encode(circles, forKey: Key.circles)
        var members = decode([CircleMember].self, forKey: Key.circleMembers) ?? []
        members.removeAll { $0.circleId == id }
        encode(members, forKey: Key.circleMembers)
    }

    func circlesForUser(_ userId: String) async -> [CircleModel] {
        let members = await loadCircleMembers()
        let memberIds = Set(members.filter { $0.userId == userId }.map(\.circleId))
        let allCircles = await loadCircles()
        return allCircles.filter { memberIds.contains($0.id) }
    }

    // MARK: - circle_members

    func loadCircleMembers() async -> [CircleMember] {
        if usesRemote {
            return (try? await supabase.client
                .from("circle_members")
                .select()
                .execute()
                .value) ?? []
        }
        return decode([CircleMember].self, forKey: Key.circleMembers) ?? []
    }

    func loadMembers(for circleId: String) async -> [CircleMember] {
        if usesRemote {
            return (try? await supabase.client
                .from("circle_members")
                .select()
                .eq("circle_id", value: circleId)
                .execute()
                .value) ?? []
        }
        return (decode([CircleMember].self, forKey: Key.circleMembers) ?? [])
            .filter { $0.circleId == circleId }
    }

    func removeMember(_ memberId: String) async {
        if usesRemote {
            do {
                try await supabase.client
                    .from("circle_members")
                    .delete()
                    .eq("id", value: memberId)
                    .execute()
            } catch {
                print("Failed to remove member: \(error)")
            }
        }
        var members = decode([CircleMember].self, forKey: Key.circleMembers) ?? []
        members.removeAll { $0.id == memberId }
        encode(members, forKey: Key.circleMembers)
    }

    /// Fetch posture stats for a specific user (used by circles for fellow member data).
    func loadDaysForUser(_ userId: String) async -> [PostureDay] {
        if usesRemote {
            return (try? await supabase.client
                .from("posture_days")
                .select()
                .eq("user_id", value: userId)
                .order("date", ascending: true)
                .execute()
                .value) ?? []
        }
        return (decode([PostureDay].self, forKey: Key.days) ?? [])
            .filter { $0.userId == userId }
    }

    /// Load a single profile by user ID (for showing display_name in circles).
    func loadProfile(userId: String) async -> Profile? {
        if usesRemote {
            return (try? await supabase.client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value)
        }
        // Local fallback: use own profile if id matches.
        if let p = decode(Profile.self, forKey: Key.profile), p.id == userId {
            return p
        }
        return nil
    }

    // MARK: - Reset

    func wipe() {
        [Key.profile, Key.subscription, Key.days, Key.onboarded,
         Key.calibrated, Key.circles, Key.circleMembers].forEach {
            defaults.removeObject(forKey: $0)
        }
    }

    // MARK: - Helpers

    private func parseISO(_ string: String?) -> Date? {
        guard let s = string else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: s) ?? {
            let fallback = ISO8601DateFormatter()
            return fallback.date(from: s)
        }()
    }

    // MARK: - Codable helpers

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Encodable helpers for Supabase (snake_case)

nonisolated struct ProfileUpsertFull: Encodable, Sendable {
    let id: String
    let email: String?
    let display_name: String?
    let baseline_angle: Double
    let sensitivity: Double
    let nudge_style: String
    let quiet_start_hour: Int
    let quiet_start_minute: Int
    let quiet_end_hour: Int
    let quiet_end_minute: Int
    let mute_on_call: Bool
    let mute_while_moving: Bool
    let updated_at: Date

    init(_ p: Profile) {
        self.id = p.id
        self.email = p.email
        self.display_name = p.displayName
        self.baseline_angle = p.baselineAngle
        self.sensitivity = p.sensitivity
        self.nudge_style = p.nudgeStyle.rawValue
        self.quiet_start_hour = p.quietStart.hour
        self.quiet_start_minute = p.quietStart.minute
        self.quiet_end_hour = p.quietEnd.hour
        self.quiet_end_minute = p.quietEnd.minute
        self.mute_on_call = p.muteOnCall
        self.mute_while_moving = p.muteWhileMoving
        self.updated_at = Date()
    }
}

nonisolated struct SubscriptionUpsert: Encodable, Sendable {
    let user_id: String
    let plan: String
    let trial_ends_at: Date?
    let status: String

    init(_ s: Subscription) {
        self.user_id = s.userId
        self.plan = s.plan.rawValue
        self.trial_ends_at = s.trialEndsAt
        self.status = s.status.rawValue
    }
}

nonisolated struct PostureDayUpsert: Encodable, Sendable {
    let id: String
    let user_id: String
    let date: String  // YYYY-MM-DD
    let upright_pct: Double
    let slouch_events: Int
    let upright_seconds: Double
    let monitored_seconds: Double

    init(_ d: PostureDay) {
        self.id = d.id
        self.user_id = d.userId
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        self.date = fmt.string(from: d.date)
        self.upright_pct = d.uprightPct
        self.slouch_events = d.slouchEvents
        self.upright_seconds = d.uprightSeconds
        self.monitored_seconds = d.monitoredSeconds
    }
}

// Remove legacy direct-insert helpers for circles — use RPCs instead.
