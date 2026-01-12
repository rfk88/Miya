//
//  SupabaseConfig.swift
//  Miya Health
//
//  Supabase client configuration.
//

import Foundation
import Supabase

enum SupabaseConfig {
    static let supabaseURL = "https://xmfgdeyrpzpqptckmcbr.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhtZmdkZXlycHpwcXB0Y2ttY2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQxNjA4NjMsImV4cCI6MjA3OTczNjg2M30.zL4PS7grZF3BJUcdgGmJMa_2KTsl-1fCMbaCyhUqSIA"
    
    static let client = SupabaseClient(
        supabaseURL: URL(string: supabaseURL)!,
        supabaseKey: supabaseAnonKey
    )
}
