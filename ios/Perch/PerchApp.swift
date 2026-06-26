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
    @State private var supabase: SupabaseClientService
    @State private var store: PerchStore
    @State private var source: PostureSource
    @State private var engine: PostureEngine
    @State private var nudge: NudgeService
    @State private var auth: AuthService
    @State private var billing: Billing
    @State private var db: Database

    init() {
        let supabase = SupabaseClientService()
        let auth = AuthService(supabase: supabase)
        let db = Database(supabase: supabase)
        let store = PerchStore(db: db, auth: auth)
        let source = PostureSource()
        let nudge = NudgeService()
        let engine = PostureEngine(source: source, store: store, nudge: nudge)

        _supabase = State(initialValue: supabase)
        _store = State(initialValue: store)
        _source = State(initialValue: source)
        _nudge = State(initialValue: nudge)
        _engine = State(initialValue: engine)
        _auth = State(initialValue: auth)
        _billing = State(initialValue: Billing())
        _db = State(initialValue: db)

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
                .environment(db)
                .tint(Palette.sage)
        }
    }
}
