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
                        if viewModel.hasMoreTracks {
                            Text("\(viewModel.tracks.count) of \(viewModel.totalTrackCount) tracks")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(viewModel.tracks.count) tracks")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
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
                // Load all tracks button (always visible, disabled when no more tracks)
                Button(action: {
                    Task {
                        await viewModel.fetchAllPlaylistTracks()
                    }
                }) {
                    HStack {
                        if viewModel.isLoading {
                            ButtonProgressView()
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text("Load All (\(viewModel.totalTrackCount))")
                    }
                }
                .disabled(viewModel.isLoading || !viewModel.hasMoreTracks)
                .help("Load all tracks for better reordering experience")
                
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
                
                // Preview button (always visible, disabled when no changes)
                Button(action: {
                    viewModel.generatePreview()
                }) {
                    HStack {
                        Image(systemName: "eye")
                        Text("Preview")
                    }
                }
                .disabled(!viewModel.hasUnsavedChanges)
                
                // Discard changes button (always visible, disabled when no changes)
                Button(action: {
                    viewModel.discardChanges()
                }) {
                    HStack {
                        Image(systemName: "arrow.uturn.left")
                        Text("Discard")
                    }
                }
                .disabled(!viewModel.hasUnsavedChanges)
                .foregroundColor(.red)
                
                // Sync button (always visible, disabled when no changes)
                Button(action: {
                    Task {
                        await viewModel.syncToSpotify()
                    }
                }) {
                    HStack {
                        if viewModel.isLoading {
                            ButtonProgressView()
                        } else {
                            Image(systemName: "icloud.and.arrow.up")
                        }
                        Text("Sync to Spotify")
                    }
                }
                .disabled(viewModel.isLoading || !viewModel.hasUnsavedChanges)
                .buttonStyle(.borderedProminent)
                
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
            ForEach(Array(viewModel.tracks.enumerated()), id: \.offset) { index, track in
                TrackRowView(track: track, index: index + 1, viewModel: viewModel)
                    .listRowSeparator(.hidden)
                    .onAppear {
                        // Load more tracks when we're near the end
                        if index >= viewModel.tracks.count - 10 {
                            Task {
                                await viewModel.loadMoreTracksIfNeeded()
                            }
                        }
                    }
            }
            .onMove { source, destination in
                viewModel.moveTrack(from: source, to: destination)
            }
            
            // Loading indicator at the bottom
            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ButtonProgressView()
                    Text("Loading more tracks...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .listRowSeparator(.hidden)
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
    
    // Pre-compute expensive strings to avoid doing it during scrolling
    private let trackName: String
    private let artistName: String
    private let albumName: String
    private let duration: String
    private let imageURL: String?
    
    init(track: SpotifyPlaylistTrack, index: Int?, viewModel: PlaylistViewModel) {
        self.track = track
        self.index = index
        self.viewModel = viewModel
        
        // Pre-compute all display strings
        self.trackName = track.track?.name ?? "Unknown Track"
        self.artistName = track.track?.artistNames ?? "Unknown Artist"
        self.albumName = track.track?.album.name ?? "Unknown Album"
        self.duration = track.track?.durationFormatted ?? "0:00"
        self.imageURL = track.track?.album.images?.first?.url
    }
    
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
            ScrollOptimizedAsyncImage(
                urlString: imageURL,
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
                Text(trackName)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                
                Text(artistName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Album name and duration
            VStack(alignment: .trailing, spacing: 2) {
                Text(albumName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(duration)
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