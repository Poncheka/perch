//
//  RootView.swift
//  Perch
//
//  Decides between first-launch onboarding and the main Home experience, shows
//  the paywall after onboarding, then triggers first-run calibration on the
//  Home screen.
//

import SwiftUI

struct RootView: View {
    @Environment(PerchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PostureSource.self) private var source
    @Environment(PostureEngine.self) private var engine

    @State private var showPaywall = false
    @State private var showFirstCalibration = false
    /// Tracks whether sensors have been started for this session.
    @State private var sensorsStarted = false

    var body: some View {
        Group {
            if store.hasOnboarded {
                HomeView(showFirstCalibration: $showFirstCalibration)
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: store.hasOnboarded)
        .onAppear { ensureSensors() }
        .onChange(of: store.hasOnboarded) { _, onboarded in
            if onboarded {
                ensureSensors()
                // Show paywall once, right after onboarding finishes.
                if !store.subscription.isUnlocked {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showPaywall = true
                    }
                } else {
                    // Already unlocked — go straight to calibration if needed.
                    enqueueCalibrationIfNeeded()
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .onboarding)
        }
        .onChange(of: showPaywall) { _, showing in
            if !showing {
                // Paywall dismissed — check if first-run calibration is needed.
                enqueueCalibrationIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            engine.appIsActive = (phase == .active)
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

    // MARK: - First-run calibration

    /// If the user hasn't calibrated yet, flag the Home screen to show the
    /// calibration overlay after a brief delay (so the Home screen renders first).
    private func enqueueCalibrationIfNeeded() {
        guard !store.hasCalibrated else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showFirstCalibration = true
        }
    }
}
