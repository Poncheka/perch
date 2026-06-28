//
//  RootView.swift
//  Perch
//
//  Orchestrates the first-launch flow:
//    1. Onboarding (3 pages: Intro, AirPods, Notifications)
//    2. Motion & Fitness permission (dedicated screen)
//    3. Calibration (hold-steady capture)
//    4. Paywall
//    5. MainTabView (Today / Progress / Pillars / Settings)
//
//  On subsequent launches, goes straight to the tab bar.
//

import SwiftUI

struct RootView: View {
    @Environment(PerchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PostureEngine.self) private var engine

    @State private var showPaywall = false

    /// Phases that happen after onboarding but before the tab bar.
    enum PostOnboardingPhase: Equatable {
        case motionPermission
        case calibration
        case paywall
        case done
    }

    @State private var phase: PostOnboardingPhase

    init() {
        // Compute the initial post-onboarding phase synchronously so we never
        // flash MainTabView before onboarding is truly complete.
        // The store has already been read from disk by the time RootView appears,
        // but @Environment isn't available in init. We set a placeholder and
        // immediately fix it in the computed effectivePhase.
        _phase = State(initialValue: .motionPermission)
    }

    var body: some View {
        let effectivePhase = computeEffectivePhase()

        Group {
            if !store.hasOnboarded {
                OnboardingView()
            } else {
                switch effectivePhase {
                case .motionPermission:
                    MotionPermissionView(onComplete: { advancePostOnboarding(effectivePhase) })
                case .calibration:
                    CalibrationOnboardingView(onComplete: { advancePostOnboarding(effectivePhase) })
                case .paywall:
                    Color.clear
                        .frame(width: 1, height: 1)
                        .onAppear {
                            showPaywall = true
                        }
                case .done:
                    MainTabView()
                }
            }
        }
        .onChange(of: store.hasOnboarded) { _, onboarded in
            if onboarded {
                phase = computeEffectivePhase()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .onboarding)
        }
        .onChange(of: showPaywall) { _, showing in
            if !showing { phase = .done }
        }
        .onChange(of: scenePhase) { _, newPhase in
            engine.appIsActive = (newPhase == .active)
        }
    }

    // MARK: - Post-onboarding navigation

    /// Compute the correct phase from store flags — never defaults to `.done`.
    private func computeEffectivePhase() -> PostOnboardingPhase {
        guard store.hasOnboarded else { return .motionPermission }
        if store.subscription.isUnlocked { return .done }
        if store.hasCalibrated { return .paywall }
        return .motionPermission
    }

    private func advancePostOnboarding(_ from: PostOnboardingPhase) {
        switch from {
        case .motionPermission:
            if store.hasCalibrated {
                phase = .paywall
            } else {
                phase = .calibration
            }
        case .calibration:
            if store.subscription.isUnlocked {
                phase = .done
            } else {
                phase = .paywall
            }
        default:
            break
        }
    }
}
