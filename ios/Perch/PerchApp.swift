//
//  PerchApp.swift
//  Perch
//
//  App entry. Builds the dependency graph once and injects every service into
//  the environment. Configures Google Sign In on launch. PostureSource is the
//  single sensor signal; PostureEngine is the state machine that reads it.
//

import SwiftUI
import GoogleSignIn

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

        // Configure Google Sign In with the iOS client ID from Google Cloud Console.
        // Replace the placeholder below with your actual iOS client ID, which looks
        // like "XXXX-XXXX.apps.googleusercontent.com".
        let googleClientID = "523223745831-folpkj43uqhs77d854m92l2s1dfq3qpi.apps.googleusercontent.com"
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)
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
