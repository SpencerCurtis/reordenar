//
//  PlaylistSidebarView.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import SwiftUI

struct PlaylistSidebarView: View {
    @ObservedObject var viewModel: PlaylistViewModel
    @ObservedObject var authViewModel: AuthenticationViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with user info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let user = authViewModel.currentUser {
                        Text(user.display_name ?? "Spotify User")
                            .font(.headline)
                            .lineLimit(1)
                        
                        Text("\(viewModel.playlists.count) playlists")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Logout button
                Button(action: {
                    authViewModel.signOut()
                }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Sign out")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Playlists list
            if viewModel.playlists.isEmpty {
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Loading playlists...")
                        Spacer()
                    }
                } else {
                    VStack {
                        Spacer()
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No playlists found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Create a playlist in Spotify to get started")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                }
            } else {
                List(viewModel.playlists, id: \.id, selection: Binding<SpotifyPlaylist.ID?>(
                    get: { viewModel.selectedPlaylist?.id },
                    set: { newValue in
                        if let playlistId = newValue,
                           let playlist = viewModel.playlists.first(where: { $0.id == playlistId }) {
                            Task {
                                await viewModel.selectPlaylist(playlist)
                            }
                        }
                    }
                )) { playlist in
                    PlaylistRowView(playlist: playlist, viewModel: viewModel)
                        .tag(playlist.id)
                }
                .listStyle(SidebarListStyle())
            }
            
            Divider()
            
            // Footer with refresh button
            HStack {
                Button(action: {
                    Task {
                        await viewModel.fetchPlaylists()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                }
                .disabled(viewModel.isLoading)
                .help("Refresh playlists and recently played order")
                
                Spacer()
                
                if viewModel.isLoading {
                    ButtonProgressView()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 250)
        .task {
            if viewModel.playlists.isEmpty && authViewModel.isAuthenticated {
                await viewModel.fetchPlaylists()
            }
        }
    }
}

struct PlaylistRowView: View {
    let playlist: SpotifyPlaylist
    let viewModel: PlaylistViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Playlist image or placeholder
            ScrollOptimizedAsyncImage(
                urlString: playlist.images?.first?.url,
                thumbnailSize: CGSize(width: 40, height: 40),
                content: { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                },
                placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "music.note.list")
                                .foregroundColor(.secondary)
                        )
                }
            )
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            
            // Playlist info
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(playlist.tracks?.total ?? 0) tracks")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(viewModel.selectedPlaylist?.id == playlist.id ? 
                      Color.accentColor.opacity(0.2) : Color.clear)
        )
        .onTapGesture {
            Task {
                await viewModel.selectPlaylist(playlist)
            }
        }
        .help(playlist.name)
    }
}

#Preview {
    let viewModel = PlaylistViewModel()
    
    PlaylistSidebarView(
        viewModel: viewModel,
        authViewModel: AuthenticationViewModel()
    )
    .frame(width: 250, height: 500)
} 