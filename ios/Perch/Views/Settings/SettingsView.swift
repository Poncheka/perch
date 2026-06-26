//
//  SettingsView.swift
//  Perch
//
//  The "Settings" tab. Minimal — sensible defaults, calm controls,
//  and a quiet account section.
//

import SwiftUI

struct SettingsView: View {
    @Environment(PerchStore.self) private var store
    @Environment(PostureSource.self) private var source
    @Environment(AuthService.self) private var auth

    @State private var showRecalibrate = false
    @State private var showAccount = false
    @State private var showPaywall = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Form {
                // MARK: Sensitivity
                Section {
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack {
                            Text("Sensitivity")
                            Spacer()
                            Text(sensitivityLabel)
                                .foregroundStyle(Palette.mist)
                        }
                        Slider(value: $store.profile.sensitivity, in: 0...1)
                            .tint(Palette.sage)
                            .onChange(of: store.profile.sensitivity) { _, _ in store.saveProfile() }
                        Text("Most people never need to change this.")
                            .font(.caption)
                            .foregroundStyle(Palette.mist)
                    }
                } header: {
                    Text("Posture")
                }

                // MARK: Nudge style
                Section("Nudge style") {
                    Picker("Nudge style", selection: $store.profile.nudgeStyle) {
                        ForEach(NudgeStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: store.profile.nudgeStyle) { _, _ in store.saveProfile() }
                }

                // MARK: Quiet hours
                Section("Quiet hours") {
                    ClockRow(label: "Start", clock: $store.profile.quietStart) { store.saveProfile() }
                    ClockRow(label: "End", clock: $store.profile.quietEnd) { store.saveProfile() }
                }

                // MARK: Auto-mute
                Section("Auto-mute") {
                    Toggle("Mute on phone calls", isOn: $store.profile.muteOnCall)
                        .onChange(of: store.profile.muteOnCall) { _, _ in store.saveProfile() }
                    Toggle("Mute while moving", isOn: $store.profile.muteWhileMoving)
                        .onChange(of: store.profile.muteWhileMoving) { _, _ in store.saveProfile() }
                }

                // MARK: Calibration
                Section {
                    Button {
                        showRecalibrate = true
                    } label: {
                        Label("Re-calibrate posture", systemImage: "scope")
                    }
                    .tint(Palette.sage)
                }

                // MARK: Account
                Section("Account") {
                    if auth.isSignedIn {
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(auth.email ?? "")
                                .foregroundStyle(Palette.mist)
                        }
                        Button("Sign out", role: .destructive) {
                            Task {
                                try? await auth.signOut()
                                store.wipeForSignOut()
                            }
                        }
                    } else {
                        Button("Sign in") { showAccount = true }
                            .tint(Palette.sage)
                    }
                }

                // MARK: Subscription
                Section("Subscription") {
                    HStack {
                        Text("Plan")
                        Spacer()
                        Text(planLabel)
                            .foregroundStyle(Palette.mist)
                    }
                    Button("Manage subscription") { showPaywall = true }
                        .tint(Palette.sage)
                    Button("Restore purchases") { showPaywall = true }
                        .tint(Palette.sage)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showRecalibrate) { RecalibrateView() }
            .sheet(isPresented: $showAccount) { AccountSignInView() }
            .sheet(isPresented: $showPaywall) { PaywallView(context: .manage) }
        }
    }

    private var sensitivityLabel: String {
        switch store.profile.sensitivity {
        case ..<0.34: return "Strict"
        case ..<0.67: return "Balanced"
        default: return "Forgiving"
        }
    }

    private var planLabel: String {
        if let days = store.subscription.trialDaysRemaining {
            return "Trial · \(days)d left"
        }
        return store.subscription.plan.title
    }
}

// MARK: - Clock row

private struct ClockRow: View {
    let label: String
    @Binding var clock: Clock
    let onChange: () -> Void

    var body: some View {
        DatePicker(
            label,
            selection: Binding(
                get: { dateFrom(clock) },
                set: { clock = clockFrom($0); onChange() }
            ),
            displayedComponents: .hourAndMinute
        )
    }

    private func dateFrom(_ clock: Clock) -> Date {
        Calendar.current.date(
            bySettingHour: clock.hour, minute: clock.minute, second: 0, of: Date()
        ) ?? Date()
    }

    private func clockFrom(_ date: Date) -> Clock {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Clock(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }
}
