//
//  MiyaSupabaseHTTP.swift
//  Miya Health
//
//  Finite URLSession timeouts for Supabase (avoids hung requests appearing as infinite “Syncing…”).
//  In your local `SupabaseConfig`, pass `global: MiyaSupabaseHTTP.globalOptions` into `SupabaseClientOptions`.

import Foundation
import Supabase

enum MiyaSupabaseHTTP {
    static func makeURLSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    /// Drop-in for `SupabaseClientOptions(global: ...)` alongside your existing `auth:` configuration.
    static var globalOptions: SupabaseClientOptions.GlobalOptions {
        SupabaseClientOptions.GlobalOptions(session: makeURLSession())
    }
}
