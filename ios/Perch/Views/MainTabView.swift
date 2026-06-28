//
//  MainTabView.swift
//  Perch
//
//  Bottom tab bar with 4 tabs: Today, Progress, Pillars, Settings.
//  Sage tint for the selected tab, warm paper background throughout.
//

import SwiftUI
import CoreMotion

struct MainTabView: View {
    @Environment(PostureSource.self) private var source
    @Environment(PostureEngine.self) private var engine
    @Environment(PerchStore.self) private var store

    @State private var sensorsStarted = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Today", systemImage: "figure.seated.side")
                }

            ProgressView()
                .tabItem {
                    Label("Progress", systemImage: "chart.bar")
                }

            CirclesView()
                .tabItem {
                    Label("Pillars", systemImage: "person.2")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(Palette.sage)
        .onAppear { ensureSensors() }
    }

    // MARK: - Sensors

    /// Start the engine and sensor pipeline. The real AirPods motion sensor is
    /// only started if motion permission has already been granted — this
    /// prevents an accidental Motion & Fitness prompt from firing when
    /// MainTabView appears. The prompt is ONLY triggered by the explicit
    /// "Allow access" button on the dedicated MotionPermissionView.
    private func ensureSensors() {
        guard !sensorsStarted else { return }
        sensorsStarted = true

        // Start the engine timer unconditionally (it polls source and stays idle
        // if no data is flowing, which is harmless).
        engine.start()

        // Only start the real sensor if motion is already authorized, or if
        // we're in simulated mode (which never triggers permission prompts).
        let authorized: Bool
        if #available(iOS 18.0, *) {
            authorized = CMHeadphoneMotionManager.authorizationStatus() == .authorized
        } else {
            // On iOS 17, there's no authorization API — start and let the
            // existing permission state handle it. This is safe because by the
            // time MainTabView renders, the user has already been through
            // MotionPermissionView where the prompt was shown.
            authorized = store.hasOnboarded
        }

        if authorized || source.sourceMode == .simulated {
            source.start()
        }
    }
}
