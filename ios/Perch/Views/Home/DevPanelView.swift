//
//  DevPanelView.swift
//  Perch
//
//  Hidden developer panel (triple-tap the Home numeral). Lets us force every
//  state by hand: a manual neckAngle slider, an AirPods toggle, simulated
//  call / movement context, source mode switch (Real vs Simulated), and a
//  "Replay onboarding" button (resets onboarding + calibration so the full
//  flow replays).
//

import SwiftUI

struct DevPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PostureSource.self) private var source
    @Environment(PerchStore.self) private var store

    @State private var pendingMode: PostureSource.SourceMode?

    var body: some View {
        @Bindable var source = source

        NavigationStack {
            Form {
                Section {
                    Picker("Sensor source", selection: $pendingMode) {
                        Text("Simulated").tag(PostureSource.SourceMode.simulated)
                        Text("Real (AirPods)").tag(PostureSource.SourceMode.real)
                    }
                    .pickerStyle(.segmented)
                    .onAppear { pendingMode = source.sourceMode }
                    .onChange(of: pendingMode) { _, newValue in
                        if let mode = newValue {
                            source.setSourceMode(mode)
                        }
                    }

                    Toggle("AirPods override", isOn: $source.manualAirpodsOverride)
                    if source.manualAirpodsOverride {
                        Toggle("AirPods connected", isOn: $source.manualAirpodsValue)
                    }
                    Toggle("Manual angle override", isOn: $source.manualOverride)
                } header: {
                    Text("Sensor")
                } footer: {
                    Text("All values flow through PostureSource — the single signal the whole app reads. Real requires AirPods (3rd gen), Pro, or Max with motion sensors.")
                }

                Section("Neck angle") {
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack {
                            Text("Forward tilt")
                            Spacer()
                            Text("\(Int(source.manualOverride ? source.manualAngle : source.neckAngle))°")
                                .foregroundStyle(Palette.mist)
                                .monospacedDigit()
                        }
                        Slider(value: $source.manualAngle, in: -10...40, step: 1)
                            .tint(Palette.sage)
                            .disabled(!source.manualOverride)
                        Text("Slouch threshold: \(Int(store.profile.slouchThreshold))°")
                            .font(.caption)
                            .foregroundStyle(Palette.mist)
                    }
                }

                Section("Simulated context") {
                    Toggle("On a call", isOn: $source.isOnCall)
                    Toggle("Moving / walking", isOn: $source.isMoving)
                }

                Section {
                    Button(role: .destructive) {
                        store.resetOnboarding()
                        dismiss()
                    } label: {
                        Label("Replay onboarding", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Development")
                } footer: {
                    Text("Resets onboarding AND calibration flags so the full flow replays. Use this to review onboarding and first-run calibration during development.")
                }
            }
            .navigationTitle("Developer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
