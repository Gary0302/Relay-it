//
//  Config.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import Foundation

/// App configuration constants
enum Config {
    // MARK: - Supabase
    static let supabaseURL = URL(string: "https://ergubwjyauqgqipzucte.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVyZ3Vid2p5YXVxZ3FpcHp1Y3RlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg2MjkyMTQsImV4cCI6MjA4NDIwNTIxNH0.Z3y0DCailuUkWpwjkvujUhjNdIO7h5EjO-cQRofpk0o"
    
    // MARK: - API
    static let apiBaseURL = URL(string: "https://relay-that-backend.vercel.app")!
    
    // MARK: - App Settings
    static let screenshotHotkey = "⌘⇧E"
    static let maxFreeScreenshotsPerSession = 15
}
