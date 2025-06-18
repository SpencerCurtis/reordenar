//
//  PreviewView.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import SwiftUI

struct PreviewView: View {
    @ObservedObject var viewModel: PlaylistViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "eye")
                            .foregroundColor(.blue)
                        Text("Preview Changes")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    
                    if let playlist = viewModel.selectedPlaylist {
                        HStack {
                            Text("Playlist: \(playlist.name)")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    
                    HStack {
                        Text("This is how your playlist will look after syncing to Spotify")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Track list preview
                List {
                    ForEach(Array(viewModel.previewChanges.enumerated()), id: \.element.id) { index, track in
                        PreviewTrackRowView(track: track, index: index + 1)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(PlainListStyle())
                
                Divider()
                
                // Footer with actions
                HStack {
                    Button("Cancel") {
                        viewModel.cancelPreview()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .keyboardShortcut(.escape)
                    
                    Spacer()
                    
                    Button("Apply Changes") {
                        viewModel.applyPreview()
                        presentationMode.wrappedValue.dismiss()
                        Task {
                            await viewModel.syncToSpotify()
                        }
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(width: 600, height: 500)
        .navigationTitle("Preview Changes")
    }
}

struct PreviewTrackRowView: View {
    let track: SpotifyPlaylistTrack
    let index: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Track number
            Text("\(index)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
            
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
    }
}

#Preview {
    PreviewView(viewModel: PlaylistViewModel())
} 