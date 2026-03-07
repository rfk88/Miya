//
//  SupabaseConfig.swift
//  Miya Health
//
//  Supabase client configuration. Supabase URL and anon key must ONLY come from the
//  gitignored Secrets.xcconfig (see Secrets.xcconfig.example). Do not add literal
//  URL or anon key in this file or in the Xcode project.
//

import Foundation
import Supabase

enum SupabaseConfig {
    private static func requireInfoPlist(key: String) -> String {
        guard let value = Bundle.main.infoDictionary?[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fatalError("SupabaseConfig: \(key) is missing or empty. Copy Miya Health/Secrets.xcconfig.example to Miya Health/Secrets.xcconfig, replace placeholders with your Supabase URL and anon key, and do not commit Secrets.xcconfig. See tools/README.md.")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // From Info.plist only (Secrets.xcconfig, not committed). Do not hardcode here.
    // Key names match Xcode INFOPLIST_KEY_* (SupabaseURL, SupabaseAnonKey) or legacy (SUPABASE_URL, SUPABASE_ANON_KEY)
    static let supabaseURL: String = {
        if let v = Bundle.main.infoDictionary?["SupabaseURL"] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return v.trimmingCharacters(in: .whitespacesAndNewlines) }
        return requireInfoPlist(key: "SUPABASE_URL")
    }()

    // From Info.plist only (Secrets.xcconfig, not committed). Do not hardcode here.
    static let supabaseAnonKey: String = {
        if let v = Bundle.main.infoDictionary?["SupabaseAnonKey"] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return v.trimmingCharacters(in: .whitespacesAndNewlines) }
        return requireInfoPlist(key: "SUPABASE_ANON_KEY")
    }()

    static let client: SupabaseClient = {
        guard let url = URL(string: supabaseURL) else {
            fatalError("SupabaseConfig: SUPABASE_URL is not a valid URL.")
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(storageKey: "miya-auth-token")
            )
        )
    }()
}
