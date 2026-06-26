//
//  Subscription.swift
//  Perch
//
//  Mirrors the Supabase `subscriptions` table. Drives paywall + premium gating.
//

import Foundation

nonisolated enum Plan: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case trial
    case monthly
    case annual
    case lifetime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Not subscribed"
        case .trial: return "Free trial"
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        case .lifetime: return "Forever"
        }
    }

    var priceLabel: String {
        switch self {
        case .none, .trial: return ""
        case .monthly: return "$2.99/mo"
        case .annual: return "$19.99/yr"
        case .lifetime: return "$29.99 once"
        }
    }
}

nonisolated enum SubscriptionStatus: String, Codable, Sendable {
    case inactive
    case trialing
    case active
    case expired
}

nonisolated struct Subscription: Codable, Equatable, Identifiable, Sendable {
    var userId: String
    var plan: Plan
    var trialEndsAt: Date?
    var status: SubscriptionStatus

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case plan
        case trialEndsAt = "trial_ends_at"
        case status
    }

    static func makeInactive(userId: String) -> Subscription {
        Subscription(userId: userId, plan: .none, trialEndsAt: nil, status: .inactive)
    }

    /// Whether premium features are currently unlocked.
    var isUnlocked: Bool {
        switch status {
        case .active: return true
        case .trialing:
            guard let end = trialEndsAt else { return false }
            return end > Date()
        case .inactive, .expired: return false
        }
    }

    var trialDaysRemaining: Int? {
        guard status == .trialing, let end = trialEndsAt else { return nil }
        let seconds = end.timeIntervalSinceNow
        guard seconds > 0 else { return 0 }
        return Int(ceil(seconds / 86_400))
    }
}
