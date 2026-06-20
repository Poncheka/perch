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
    @Environment(PostureEngine.self) private var engine

    @State private var showPaywall = false

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
        .onChange(of: store.hasOnboarded) { _, onboarded in
            // Show the paywall once, right after onboarding finishes.
            if onboarded && !store.subscription.isUnlocked {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showPaywall = true
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
}
