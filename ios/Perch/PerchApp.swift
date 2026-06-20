//
//  PerchApp.swift
//  Perch
//
//  App entry. Builds the dependency graph once and injects every service into
//  the environment. PostureSource is the single sensor signal; PostureEngine is
//  the state machine that reads it.
//

import SwiftUI

@main
struct PerchApp: App {
    @State private var store: PerchStore
    @State private var source: PostureSource
    @State private var engine: PostureEngine
    @State private var nudge: NudgeService
    @State private var auth: AuthService
    @State private var billing: Billing

    init() {
        let store = PerchStore()
        let source = PostureSource()
        let nudge = NudgeService()
        let engine = PostureEngine(source: source, store: store, nudge: nudge)

        _store = State(initialValue: store)
        _source = State(initialValue: source)
        _nudge = State(initialValue: nudge)
        _engine = State(initialValue: engine)
        _auth = State(initialValue: AuthService())
        _billing = State(initialValue: Billing())

        // Seed the source baseline from any saved calibration.
        source.manualOverride = false
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(source)
                .environment(engine)
                .environment(nudge)
                .environment(auth)
                .environment(billing)
                .tint(Palette.sage)
        }
    }
}
