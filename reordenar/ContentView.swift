//
//  ContentView.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authViewModel = AuthenticationViewModel()
    @StateObject private var playlistViewModel = PlaylistViewModel()
    
    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                // Main app interface
                NavigationSplitView {
                    PlaylistSidebarView(
                        viewModel: playlistViewModel,
                        authViewModel: authViewModel
                    )
                } detail: {
                    TrackListView(viewModel: playlistViewModel)
                }
                .navigationSplitViewStyle(.prominentDetail)
                .sheet(isPresented: $playlistViewModel.showPreview) {
                    PreviewView(viewModel: playlistViewModel)
                }
                .alert("Error", isPresented: .constant(playlistViewModel.errorMessage != nil)) {
                    Button("OK") {
                        playlistViewModel.errorMessage = nil
                    }
                } message: {
                    if let errorMessage = playlistViewModel.errorMessage {
                        Text(errorMessage)
                    }
                }
            } else {
                // Login screen
                LoginView()
                    .onOpenURL { url in
                        // Handle OAuth callback
                        if url.scheme == "reordenar" && url.host == "callback" {
                            Task {
                                await authViewModel.handleCallback(url: url)
                            }
                        }
                    }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
