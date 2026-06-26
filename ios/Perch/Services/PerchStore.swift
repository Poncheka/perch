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

    init() {
        let db = Database()
        self.db = db
        let loadedProfile = db.loadProfile() ?? Profile.makeDefault()
        self.profile = loadedProfile
        self.subscription = db.loadSubscription() ?? Subscription.makeInactive(userId: loadedProfile.id)
        self.days = db.loadDays()
        self.hasOnboarded = db.hasOnboarded
        self.hasCalibrated = db.hasCalibrated
    }

    // MARK: - Profile / settings

    func saveProfile() {
        db.saveProfile(profile)
    }

    /// Capture a calibration baseline (the current raw tilt from PostureSource).
    func setBaseline(_ angle: Double) {
        profile.baselineAngle = angle
        saveProfile()
    }

    // MARK: - Subscription

    func applySubscription(_ sub: Subscription) {
        var updated = sub
        updated.userId = profile.id
        subscription = updated
        db.saveSubscription(updated)
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
        if let existing = days.first(where: {
            $0.userId == profile.id &&
            Calendar.current.isDateInToday($0.date)
        }) {
            return existing
        }
        return PostureDay.makeEmpty(userId: profile.id, date: Date())
    }

    func persistDay(_ day: PostureDay) {
        db.upsertDay(day)
        days = db.loadDays()
    }

    /// Days within the last `count` calendar days, oldest → newest, padded with
    /// empty placeholders so trends always render a full window.
    func recentDays(_ count: Int) -> [PostureDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<count).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            return days.first(where: { cal.isDate($0.date, inSameDayAs: date) })
                ?? PostureDay.makeEmpty(userId: profile.id, date: date)
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
