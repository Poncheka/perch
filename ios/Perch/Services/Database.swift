//
//  Database.swift
//  Perch
//
//  The SINGLE module for all persistence. Today it stores data locally via
//  UserDefaults; the API surface mirrors the Supabase tables (profiles,
//  posture_days, subscription) so it can be swapped for real Supabase calls
//  without touching any screen.
//

import Foundation

@MainActor
final class Database {
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Key {
        static let profile = "perch.profile"
        static let subscription = "perch.subscription"
        static let days = "perch.posture_days"
        static let onboarded = "perch.hasOnboarded"
        static let circles = "perch.circles"
        static let circleMembers = "perch.circle_members"
    }

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Onboarding flag

    var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    // MARK: - profiles

    func loadProfile() -> Profile? {
        decode(Profile.self, forKey: Key.profile)
    }

    func saveProfile(_ profile: Profile) {
        encode(profile, forKey: Key.profile)
    }

    // MARK: - subscription

    func loadSubscription() -> Subscription? {
        decode(Subscription.self, forKey: Key.subscription)
    }

    func saveSubscription(_ subscription: Subscription) {
        encode(subscription, forKey: Key.subscription)
    }

    // MARK: - posture_days

    func loadDays() -> [PostureDay] {
        decode([PostureDay].self, forKey: Key.days) ?? []
    }

    /// Insert or update a day row (keyed by calendar date + user).
    func upsertDay(_ day: PostureDay) {
        var days = loadDays()
        if let index = days.firstIndex(where: {
            $0.userId == day.userId &&
            Calendar.current.isDate($0.date, inSameDayAs: day.date)
        }) {
            days[index] = day
        } else {
            days.append(day)
        }
        // Keep a rolling window of recent history.
        days.sort { $0.date < $1.date }
        if days.count > 120 {
            days = Array(days.suffix(120))
        }
        encode(days, forKey: Key.days)
    }

    /// Reset everything (used on sign out for a clean demo).
    func wipe() {
        [Key.profile, Key.subscription, Key.days, Key.onboarded,
         Key.circles, Key.circleMembers].forEach {
            defaults.removeObject(forKey: $0)
        }
    }

    // MARK: - circles

    func loadCircles() -> [CircleModel] {
        decode([CircleModel].self, forKey: Key.circles) ?? []
    }

    func saveCircle(_ circle: CircleModel) {
        var circles = loadCircles()
        if let idx = circles.firstIndex(where: { $0.id == circle.id }) {
            circles[idx] = circle
        } else {
            circles.append(circle)
        }
        encode(circles, forKey: Key.circles)
    }

    func deleteCircle(_ id: String) {
        var circles = loadCircles()
        circles.removeAll { $0.id == id }
        encode(circles, forKey: Key.circles)
        var members = loadCircleMembers()
        members.removeAll { $0.circleId == id }
        encode(members, forKey: Key.circleMembers)
    }

    func findCircleByInviteCode(_ code: String) -> CircleModel? {
        loadCircles().first { $0.inviteCode.uppercased() == code.uppercased() }
    }

    // MARK: - circle_members

    func loadCircleMembers() -> [CircleMember] {
        decode([CircleMember].self, forKey: Key.circleMembers) ?? []
    }

    func loadMembers(for circleId: String) -> [CircleMember] {
        loadCircleMembers().filter { $0.circleId == circleId }
    }

    func saveCircleMember(_ member: CircleMember) {
        var members = loadCircleMembers()
        if let idx = members.firstIndex(where: { $0.id == member.id }) {
            members[idx] = member
        } else {
            members.append(member)
        }
        encode(members, forKey: Key.circleMembers)
    }

    func removeMember(_ memberId: String) {
        var members = loadCircleMembers()
        members.removeAll { $0.id == memberId }
        encode(members, forKey: Key.circleMembers)
    }

    /// Circles the given user belongs to.
    func circlesForUser(_ userId: String) -> [CircleModel] {
        let memberIds = Set(loadCircleMembers()
            .filter { $0.userId == userId }
            .map(\.circleId))
        return loadCircles().filter { memberIds.contains($0.id) }
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
