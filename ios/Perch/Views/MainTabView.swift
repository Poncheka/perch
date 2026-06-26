//
//  MainTabView.swift
//  Perch
//
//  Bottom tab bar with 4 tabs: Today, Progress, Circles, Settings.
//  Sage tint for the selected tab, warm paper background throughout.
//

import SwiftUI

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

            HistoryView()
                .tabItem {
                    Label("Progress", systemImage: "chart.bar")
                }

            CirclesView()
                .tabItem {
                    Label("Circles", systemImage: "person.2")
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

    private func ensureSensors() {
        guard !sensorsStarted else { return }
        sensorsStarted = true
        source.start()
        engine.start()
    }
}
