//
//  DevPanelView.swift
//  Perch
//
//  Hidden developer panel (triple-tap the Home numeral). Lets us force every
//  state by hand: a manual neckAngle slider, an AirPods toggle, and simulated
//  call / movement context — all driven through the single PostureSource.
//

import SwiftUI

struct DevPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PostureSource.self) private var source
    @Environment(PerchStore.self) private var store

    var body: some View {
        @Bindable var source = source

        NavigationStack {
            Form {
                Section {
                    Toggle("AirPods connected", isOn: $source.airpodsConnected)
                    Toggle("Manual angle override", isOn: $source.manualOverride)
                } header: {
                    Text("Sensor")
                } footer: {
                    Text("All values flow through PostureSource — the single signal the whole app reads.")
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
