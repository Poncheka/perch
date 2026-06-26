//
//  RootView.swift
//  Perch
//
//  Orchestrates the first-launch flow:
//    1. Onboarding (3 pages: Intro, AirPods, Notifications)
//    2. Motion & Fitness permission (dedicated screen)
//    3. Calibration (hold-steady capture)
//    4. Paywall
//    5. MainTabView (Today / Progress / Circles / Settings)
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
    enum PostOnboardingPhase {
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
                    .transition(.opacity)
            } else {
                switch phase {
                case .motionPermission:
                    MotionPermissionView(onComplete: { advancePostOnboarding() })
                        .transition(.opacity)
                case .calibration:
                    CalibrationOnboardingView(onComplete: { advancePostOnboarding() })
                        .transition(.opacity)
                case .paywall:
                    Color.clear
                        .frame(width: 1, height: 1)
                        .transition(.identity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showPaywall = true
                            }
                        }
                case .done:
                    MainTabView()
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: store.hasOnboarded)
        .animation(.easeInOut(duration: 0.5), value: phase)
        .onChange(of: store.hasOnboarded) { _, onboarded in
            if onboarded {
                if store.subscription.isUnlocked {
                    phase = .done
                } else if store.hasCalibrated {
                    phase = .paywall
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showPaywall = true
                    }
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
        withAnimation(.easeInOut(duration: 0.5)) {
            switch phase {
            case .motionPermission:
                if store.hasCalibrated {
                    phase = .paywall
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showPaywall = true
                    }
                } else {
                    phase = .calibration
                }
            case .calibration:
                if store.subscription.isUnlocked {
                    phase = .done
                } else {
                    phase = .paywall
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showPaywall = true
                    }
                }
            default:
                break
            }
        }
    }
}
