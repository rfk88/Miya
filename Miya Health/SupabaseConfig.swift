//
//  SupabaseConfig.swift
//  Miya Health
//
//  Supabase client configuration.
//

import Foundation
import Supabase

enum SupabaseConfig {
    private static let defaultSupabaseURL = "https://xmfgdeyrpzpqptckmcbr.supabase.co"
    private static let defaultSupabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhtZmdkZXlycHpwcXB0Y2ttY2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQxNjA4NjMsImV4cCI6MjA3OTczNjg2M30.zL4PS7grZF3BJUcdgGmJMa_2KTsl-1fCMbaCyhUqSIA"

    static let supabaseURL: String = {
        if let url = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
           !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return url
        }
        return defaultSupabaseURL
    }()

    static let supabaseAnonKey: String = {
        if let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        return defaultSupabaseAnonKey
    }()
    
    static let client: SupabaseClient = {
        if let url = URL(string: supabaseURL) {
            return SupabaseClient(
                supabaseURL: url,
                supabaseKey: supabaseAnonKey
            )
        }

        let fallbackURL = URL(string: defaultSupabaseURL)!
        return SupabaseClient(
            supabaseURL: fallbackURL,
            supabaseKey: supabaseAnonKey
        )
    }()
}
