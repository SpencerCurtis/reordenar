//
//  reordenarApp.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import SwiftUI
import SwiftData
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable automatic window tabbing to ensure single-window behavior
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}

@main
struct reordenarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authViewModel = AuthenticationViewModel()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CachedImage.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        Window("Reordenar", id: "main") {
            ContentView()
                .environmentObject(authViewModel)
                .modelContainer(sharedModelContainer)
                .onAppear {
                    // Configure the hybrid image cache with the model container
                    Task { @MainActor in
                        HybridImageCache.shared.configure(with: sharedModelContainer)
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .handlesExternalEvents(matching: Set(arrayLiteral: "reordenar"))
        .commands {
            AppCommands()
        }
    }
}

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Refresh Playlists") {
                // TODO: Implement playlist refresh functionality
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
