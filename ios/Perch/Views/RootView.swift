//
//  RootView.swift
//  Perch
//
//  Decides between first-launch onboarding and the main Home experience, and
//  presents the paywall once after onboarding completes.
//

import SwiftUI

struct RootView: View {
    @Environment(PerchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PostureSource.self) private var source
    @Environment(PostureEngine.self) private var engine

    @State private var showPaywall = false
    /// Tracks whether sensors have been started for this session (deferred
    /// until after onboarding or on first appearance when already onboarded).
    @State private var sensorsStarted = false

    var body: some View {
        Group {
            if store.hasOnboarded {
                HomeView()
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
                // Show the paywall once, right after onboarding finishes.
                if !store.subscription.isUnlocked {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showPaywall = true
                    }
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .onboarding)
        }
        .onChange(of: scenePhase) { _, phase in
            engine.appIsActive = (phase == .active)
        }
    }

    /// Start sensors and the engine only once per session, and only after
    /// the onboarding flow has been completed (or was already done).
    private func ensureSensors() {
        guard !sensorsStarted, store.hasOnboarded else { return }
        sensorsStarted = true
        source.start()
        engine.start()
    }
}
