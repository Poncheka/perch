//
//  PerchStore.swift
//  Perch
//
//  App-wide state container. Owns the profile, subscription, and day history,
//  and brokers persistence through the single Database module. Screens read and
//  mutate app state only through this store.
//

import SwiftUI

@Observable
@MainActor
final class PerchStore {
    var profile: Profile
    var subscription: Subscription
    private(set) var days: [PostureDay]
    var hasOnboarded: Bool
    var hasCalibrated: Bool

    private let db: Database
    let auth: AuthService

    init(db: Database, auth: AuthService) {
        self.db = db
        self.auth = auth
        let fresh = Profile.makeDefault()
        self.profile = fresh
        self.subscription = Subscription.makeInactive(userId: fresh.id)
        self.days = []
        self.hasOnboarded = db.hasOnboarded
        self.hasCalibrated = db.hasCalibrated

        // Load persisted data asynchronously.
        Task { await loadFromDisk() }
    }

    /// Called on launch and after sign-in to load Supabase data.
    func loadFromSupabase() async {
        guard auth.isSignedIn, let uid = auth.userId else { return }
        // Update profile id to match the auth user.
        if profile.id != uid {
            profile.id = uid
            subscription.userId = uid
        }
        // Load profile, subscription, days from Supabase.
        if let remoteProfile = await db.loadProfile() {
            profile = remoteProfile
        } else {
            // No profile yet — upsert from the handle_new_user trigger default.
            try? await auth.ensureProfile()
            if let p = await db.loadProfile() {
                profile = p
            }
        }
        if let sub = await db.loadSubscription() {
            subscription = sub
        }
        days = await db.loadDays()
    }

    /// Load from local UserDefaults (used when signed out).
    private func loadFromDisk() async {
        if let p = await db.loadProfile() { profile = p }
        if let s = await db.loadSubscription() { subscription = s }
        days = await db.loadDays()
    }

    // MARK: - Profile / settings

    func saveProfile() {
        Task { await db.saveProfile(profile) }
    }

    /// Capture a calibration baseline (the current raw tilt from PostureSource).
    func setBaseline(_ angle: Double) {
        profile.baselineAngle = angle
        saveProfile()
    }

    // MARK: - Subscription

    func applySubscription(_ sub: Subscription) {
        var updated = sub
        if let uid = auth.userId { updated.userId = uid }
        else { updated.userId = profile.id }
        subscription = updated
        Task { await db.saveSubscription(updated) }
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        hasOnboarded = true
        db.hasOnboarded = true
    }

    /// Reset the onboarding flag so the onboarding flow replays (Dev Panel use).
    func resetOnboarding() {
        hasOnboarded = false
        hasCalibrated = false
        db.hasOnboarded = false
        db.hasCalibrated = false
    }

    /// Mark first-run calibration as complete.
    func completeCalibration() {
        hasCalibrated = true
        db.hasCalibrated = true
    }

    // MARK: - Posture days

    /// The record for today, creating an empty one if needed.
    func todayRecord() -> PostureDay {
        let uid = auth.userId ?? profile.id
        if let existing = days.first(where: {
            $0.userId == uid &&
            Calendar.current.isDateInToday($0.date)
        }) {
            return existing
        }
        return PostureDay.makeEmpty(userId: uid, date: Date())
    }

    func persistDay(_ day: PostureDay) {
        Task { await db.upsertDay(day) }
        // Update in-memory immediately.
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
    }

    /// Days within the last `count` calendar days, oldest → newest, padded with
    /// empty placeholders so trends always render a full window.
    func recentDays(_ count: Int) -> [PostureDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let uid = auth.userId ?? profile.id
        return (0..<count).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            return days.first(where: { cal.isDate($0.date, inSameDayAs: date) })
                ?? PostureDay.makeEmpty(userId: uid, date: date)
        }
    }

    // MARK: - Account reset

    func wipeForSignOut() {
        db.wipe()
        let fresh = Profile.makeDefault()
        profile = fresh
        subscription = Subscription.makeInactive(userId: fresh.id)
        days = []
        hasOnboarded = false
        hasCalibrated = false
    }
}
