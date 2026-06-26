//
//  SupabaseClient.swift
//  Perch
//
//  Singleton Supabase client. Configured for native Supabase Auth
//  (email/password). The client owns the auth session — no accessToken
//  closure needed.
//

import Foundation
import Supabase

/// The single Supabase client for the app. Created once at launch and shared
/// via SwiftUI environment. All database and auth calls flow through this.
@MainActor
final class SupabaseClientService {
    let client: SupabaseClient

    init() {
        guard let url = URL(string: "https://jzbgoibuljubumhzzzis.supabase.co") else {
            fatalError("Invalid Supabase URL")
        }

        // Workaround for iOS 18.4 simulator TLS bug affecting Supabase auth.
        #if targetEnvironment(simulator)
        let config = URLSessionConfiguration.default
        config.tlsMaximumSupportedProtocolVersion = .TLSv12
        let session = URLSession(configuration: config)
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: "sb_publishable_s88wVfqKwIdvvcFpd71gcQ_-Hyax-De",
            options: .init(
                global: .init(session: session)
            )
        )
        #else
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: "sb_publishable_s88wVfqKwIdvvcFpd71gcQ_-Hyax-De"
        )
        #endif
    }
}
