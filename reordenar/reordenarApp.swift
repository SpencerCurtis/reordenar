//
//  reordenarApp.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import SwiftUI

@main
struct reordenarApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            AppCommands()
        }
    }
}

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("About Reordenar") {
                // Show about window if needed
            }
        }
        
        CommandGroup(after: .windowArrangement) {
            Button("Refresh Playlists") {
                // Refresh playlists
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
