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

    @State private var phase: PostOnboardingPhase = .done

    var body: some View {
        Group {
            if !store.hasOnboarded {
                OnboardingView()
            } else {
                switch phase {
                case .motionPermission:
                    MotionPermissionView(onComplete: { advancePostOnboarding() })
                case .calibration:
                    CalibrationOnboardingView(onComplete: { advancePostOnboarding() })
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
                if store.subscription.isUnlocked {
                    phase = .done
                } else if store.hasCalibrated {
                    phase = .paywall
                } else {
                    phase = .motionPermission
                }
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

    private func advancePostOnboarding() {
        switch phase {
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
