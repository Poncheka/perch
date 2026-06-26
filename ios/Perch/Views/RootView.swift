//
//  RootView.swift
//  Perch
//
//  Orchestrates the first-launch flow:
//    1. Onboarding (3 pages: Intro, AirPods, Notifications)
//    2. Motion & Fitness permission (dedicated screen)
//    3. Calibration (hold-steady capture)
//    4. Paywall
//    5. Home
//
//  On subsequent launches, goes straight to Home.
//

import SwiftUI

struct RootView: View {
    @Environment(PerchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PostureSource.self) private var source
    @Environment(PostureEngine.self) private var engine

    @State private var showPaywall = false

    /// Phases that happen after onboarding but before the paywall.
    enum PostOnboardingPhase {
        case motionPermission
        case calibration
        case paywall
        case done
    }

    @State private var phase: PostOnboardingPhase = .done
    @State private var sensorsStarted = false

    var body: some View {
        Group {
            if store.hasOnboarded {
                switch phase {
                case .motionPermission:
                    MotionPermissionView(onComplete: { advancePostOnboarding() })
                        .transition(.opacity)
                case .calibration:
                    CalibrationOnboardingView(onComplete: { advancePostOnboarding() })
                        .transition(.opacity)
                case .paywall:
                    // Paywall will be presented as a sheet from here.
                    // Show a minimal background while the sheet appears.
                    Color.clear
                        .frame(width: 1, height: 1)
                        .transition(.identity)
                        .onAppear {
                            // Small delay so the transition finishes before the sheet.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showPaywall = true
                            }
                        }
                case .done:
                    HomeView()
                        .transition(.opacity)
                }
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: store.hasOnboarded)
        .animation(.easeInOut(duration: 0.5), value: phase)
        .onAppear { ensureSensors() }
        .onChange(of: store.hasOnboarded) { _, onboarded in
            if onboarded {
                ensureSensors()
                // Start the post-onboarding sequence.
                // Already unlocked? Skip to home.
                if store.subscription.isUnlocked {
                    phase = .done
                } else {
                    // If already calibrated from a previous run, skip to paywall.
                    if store.hasCalibrated {
                        phase = .paywall
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showPaywall = true
                        }
                    } else {
                        phase = .motionPermission
                    }
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .onboarding)
        }
        .onChange(of: showPaywall) { _, showing in
            if !showing {
                // Paywall dismissed — mark post-onboarding done.
                phase = .done
            }
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
                    // Already calibrated somehow — skip to paywall.
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

    // MARK: - Sensors

    /// Start sensors and the engine only once per session, and only after
    /// onboarding has been completed.
    private func ensureSensors() {
        guard !sensorsStarted, store.hasOnboarded else { return }
        sensorsStarted = true
        source.start()
        engine.start()
    }
}
