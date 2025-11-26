//
//  SupabaseClient.swift
//  Miya Health
//
//  This file creates our connection to Supabase.
//  Think of it like saving a contact in your phone — we enter the
//  address and key once, then the whole app can use it.
//

import Foundation
import Supabase

// MARK: - Supabase Connection
// This creates a single connection that the entire app can use.
// "let" means this never changes once it's created.

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://xmfgdeyrpzpqptckmcbr.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhtZmdkZXlycHpwcXB0Y2ttY2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQxNjA4NjMsImV4cCI6MjA3OTczNjg2M30.zL4PS7grZF3BJUcdgGmJMa_2KTsl-1fCMbaCyhUqSIA"
)

