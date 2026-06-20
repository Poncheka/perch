//
//  Billing.swift
//  Perch
//
//  Isolated purchase surface. Mocks the StoreKit / IAP flow cleanly so it can
//  be wired to real StoreKit later without changing the paywall UI. Same
//  isolation pattern as PostureSource.
//

import Foundation

@Observable
@MainActor
final class Billing {
    private(set) var isProcessing = false

    /// Start the 14-day free trial (everything unlocked).
    func startFreeTrial() async -> Subscription? {
        await simulateNetwork()
        let end = Calendar.current.date(byAdding: .day, value: 14, to: Date())
        return Subscription(userId: "", plan: .trial, trialEndsAt: end, status: .trialing)
    }

    /// Purchase a specific plan. Returns the resulting subscription.
    func purchase(_ plan: Plan) async -> Subscription? {
        await simulateNetwork()
        switch plan {
        case .monthly, .annual:
            return Subscription(userId: "", plan: plan, trialEndsAt: nil, status: .active)
        case .lifetime:
            return Subscription(userId: "", plan: .lifetime, trialEndsAt: nil, status: .active)
        case .none, .trial:
            return nil
        }
    }

    /// Restore previously purchased entitlements.
    func restore() async -> Subscription? {
        await simulateNetwork()
        // Nothing to restore in the mock — real StoreKit would query receipts.
        return nil
    }

    private func simulateNetwork() async {
        isProcessing = true
        try? await Task.sleep(for: .milliseconds(900))
        isProcessing = false
    }
}
