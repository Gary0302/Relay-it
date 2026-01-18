//
//  Relay_it_App.swift
//  Relay it!
//
//  App entry point
//

import SwiftUI

@main
struct Relay_it_App: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var auth = AuthService.shared
    
    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(appState)
                .environmentObject(auth)
        }
        .commands {
            // Add capture command to menu
            CommandMenu("Capture") {
                Button("Take Screenshot") {
                    Task {
                        await appState.captureScreenshot()
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}
