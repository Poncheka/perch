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

    /// The screen displayed is driven by this state machine, NOT by a
    /// recomputed value.  While nil the view renders only the background
    /// so the sensor never starts and there is no flash.
    @State private var phase: PostOnboardingPhase? = nil

    var body: some View {
        Group {
            if !store.hasOnboarded {
                OnboardingView()
            } else if let resolved = phase {
                switch resolved {
                case .motionPermission:
                    MotionPermissionView {
                        advancePostOnboarding(.motionPermission)
                    }
                case .calibration:
                    CalibrationOnboardingView {
                        advancePostOnboarding(.calibration)
                    }
                case .paywall:
                    Color.clear
                        .frame(width: 1, height: 1)
                        .onAppear { showPaywall = true }
                case .done:
                    MainTabView()
                }
            } else {
                PerchBackground()
            }
        }
        .onAppear {
            if store.hasOnboarded, phase == nil {
                phase = computeInitialPhase()
            }
        }
        .onChange(of: store.hasOnboarded) { _, onboarded in
            if onboarded {
                phase = computeInitialPhase()
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

    // MARK: - Initial routing

    /// Compute the correct starting phase from store flags.
    /// Only called ONCE to seed the state machine — never inside the body.
    private func computeInitialPhase() -> PostOnboardingPhase {
        guard store.hasOnboarded else { return .motionPermission }
        if store.subscription.isUnlocked { return .done }
        if store.hasCalibrated { return .paywall }
        return .motionPermission
    }

    // MARK: - State‑machine advance

    /// Mutate `phase` to advance the post‑onboarding sequence.
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
