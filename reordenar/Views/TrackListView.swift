//
//  TrackListView.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import SwiftUI

struct TrackListView: View {
    @ObservedObject var viewModel: PlaylistViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            TrackListHeaderView(viewModel: viewModel)
            
            Divider()
            
            // Main content
            if let selectedPlaylist = viewModel.selectedPlaylist {
                if viewModel.tracks.isEmpty {
                    if viewModel.isLoading {
                        VStack {
                            Spacer()
                            ProgressView("Loading tracks...")
                                .font(.headline)
                            Spacer()
                        }
                    } else {
                        VStack {
                            Spacer()
                            Image(systemName: "music.note")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No tracks in this playlist")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Add some songs in Spotify to get started")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                } else {
                    // Track list based on view mode
                    Group {
                        switch viewModel.viewMode {
                        case .tracks:
                            TrackListContent(viewModel: viewModel)
                        case .groupedByArtist:
                            GroupedTrackListContent(viewModel: viewModel)
                        }
                    }
                    .clipped()
                }
            } else {
                // No playlist selected
                VStack {
                    Spacer()
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a playlist")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Choose a playlist from the sidebar to start reordering tracks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            }
        }
    }
}

// MARK: - Header View
struct TrackListHeaderView: View {
    @ObservedObject var viewModel: PlaylistViewModel
    
    var body: some View {
        HStack {
            // Playlist info
            VStack(alignment: .leading, spacing: 4) {
                if let playlist = viewModel.selectedPlaylist {
                    Text(playlist.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(1)
                    
                    HStack {
                        Text("\(viewModel.tracks.count) tracks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if viewModel.hasUnsavedChanges {
                            Text("• \(viewModel.changesSummary)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Controls
            HStack(spacing: 12) {
                // View mode toggle
                Button(action: {
                    viewModel.toggleViewMode()
                }) {
                    HStack {
                        Image(systemName: viewModel.viewMode == .tracks ? "list.bullet" : "person.2")
                        Text(viewModel.viewMode == .tracks ? "Group by Artist" : "Show All Tracks")
                    }
                }
                .disabled(viewModel.tracks.isEmpty)
                
                // Cluster tracks by artist button (only in tracks mode)
                if viewModel.viewMode == .tracks {
                    Button(action: {
                        viewModel.groupByArtist()
                    }) {
                        HStack {
                            Image(systemName: "rectangle.3.group")
                            Text("Cluster by Artist")
                        }
                    }
                    .disabled(viewModel.tracks.isEmpty)
                    .help("Reorder tracks to cluster them by artist")
                }
                
                // Preview button
                if viewModel.hasUnsavedChanges {
                    Button(action: {
                        viewModel.generatePreview()
                    }) {
                        HStack {
                            Image(systemName: "eye")
                            Text("Preview")
                        }
                    }
                }
                
                // Discard changes button
                if viewModel.hasUnsavedChanges {
                    Button(action: {
                        viewModel.discardChanges()
                    }) {
                        HStack {
                            Image(systemName: "arrow.uturn.left")
                            Text("Discard")
                        }
                    }
                    .foregroundColor(.red)
                }
                
                // Sync button
                if viewModel.hasUnsavedChanges {
                    Button(action: {
                        Task {
                            await viewModel.syncToSpotify()
                        }
                    }) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "icloud.and.arrow.up")
                            }
                            Text("Sync to Spotify")
                        }
                    }
                    .disabled(viewModel.isLoading)
                    .buttonStyle(.borderedProminent)
                }
                
                // Refresh button
                Button(action: {
                    Task {
                        await viewModel.refreshCurrentPlaylist()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .help("Refresh playlist")
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Track List Content
struct TrackListContent: View {
    @ObservedObject var viewModel: PlaylistViewModel
    
    var body: some View {
        List {
            ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { index, track in
                TrackRowView(track: track, index: index + 1, viewModel: viewModel)
                    .listRowSeparator(.hidden)
            }
            .onMove { source, destination in
                viewModel.moveTrack(from: source, to: destination)
            }
        }
        .listStyle(PlainListStyle())
    }
}

// MARK: - Grouped Track List Content
struct GroupedTrackListContent: View {
    @ObservedObject var viewModel: PlaylistViewModel
    
    var body: some View {
        List {
            ForEach(Array(viewModel.trackGroups.enumerated()), id: \.element.id) { groupIndex, group in
                ArtistGroupHeaderView(artistName: group.artistName, trackCount: group.tracks.count, viewModel: viewModel)
                    .listRowSeparator(.hidden)
            }
            .onMove { source, destination in
                viewModel.moveTrackGroup(from: source, to: destination)
            }
        }
        .listStyle(PlainListStyle())
    }
}

// MARK: - Track Row View
struct TrackRowView: View {
    let track: SpotifyPlaylistTrack
    let index: Int?
    @ObservedObject var viewModel: PlaylistViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Track number or drag handle
            if let index = index {
                Text("\(index)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)
            } else {
                Image(systemName: "line.horizontal.3")
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            }
            
            // Album artwork
            CachedAsyncImage(
                urlString: track.track?.album.images?.first?.url,
                content: { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                },
                placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.gray)
                                .font(.caption)
                        )
                }
            )
            .frame(width: 40, height: 40)
            .clipped()
            .cornerRadius(4)
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.track?.name ?? "Unknown Track")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                
                Text(track.track?.artistNames ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Album name and duration
            VStack(alignment: .trailing, spacing: 2) {
                Text(track.track?.album.name ?? "Unknown Album")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(track.track?.durationFormatted ?? "0:00")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: {
                viewModel.deleteTrack(track)
            }) {
                Label("Delete from Playlist", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: {
                viewModel.deleteTrack(track)
            }) {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }
}

// MARK: - Artist Group Header
struct ArtistGroupHeaderView: View {
    let artistName: String
    let trackCount: Int
    @ObservedObject var viewModel: PlaylistViewModel
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle")
                .foregroundColor(.secondary)
            
            Text(artistName)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("(\(trackCount) \(trackCount == 1 ? "track" : "tracks"))")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Image(systemName: "line.horizontal.3")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: {
                viewModel.deleteArtist(artistName)
            }) {
                Label("Delete All Tracks by \(artistName)", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: {
                viewModel.deleteArtist(artistName)
            }) {
                Label("Delete Artist", systemImage: "trash")
            }
            .tint(.red)
        }
    }
}

#Preview {
    TrackListView(viewModel: PlaylistViewModel())
        .frame(width: 600, height: 500)
} 