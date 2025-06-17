//
//  PlaylistViewModel.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class PlaylistViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var playlists: [SpotifyPlaylist] = []
    @Published var selectedPlaylist: SpotifyPlaylist?
    @Published var tracks: [SpotifyPlaylistTrack] = []
    @Published var trackGroups: [TrackGroup] = []
    @Published var viewMode: ViewMode = .tracks
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasUnsavedChanges = false
    @Published var previewChanges: [SpotifyPlaylistTrack] = []
    @Published var showPreview = false
    
    // MARK: - Private Properties
    private let spotifyAPI = SpotifyAPIService.shared
    private var cancellables = Set<AnyCancellable>()
    private var originalTrackOrder: [SpotifyPlaylistTrack] = []
    
    init() {
        // Listen to authentication changes
        spotifyAPI.$isAuthenticated
            .sink { [weak self] isAuthenticated in
                if isAuthenticated {
                    Task {
                        await self?.fetchPlaylists()
                    }
                } else {
                    self?.clearData()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Management
    func fetchPlaylists() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await spotifyAPI.fetchUserPlaylists()
            playlists = response.items
        } catch {
            errorMessage = "Failed to fetch playlists: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func selectPlaylist(_ playlist: SpotifyPlaylist) async {
        guard selectedPlaylist?.id != playlist.id else { return }
        
        selectedPlaylist = playlist
        await fetchPlaylistTracks()
    }
    
    func fetchPlaylistTracks() async {
        guard let playlist = selectedPlaylist else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await spotifyAPI.fetchPlaylistTracks(playlistId: playlist.id)
            tracks = response.items.filter { $0.track != nil } // Filter out null tracks
            originalTrackOrder = tracks
            hasUnsavedChanges = false
            
            if viewMode == .groupedByArtist {
                updateTrackGroups()
            }
        } catch {
            errorMessage = "Failed to fetch tracks: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func clearData() {
        playlists = []
        selectedPlaylist = nil
        tracks = []
        trackGroups = []
        hasUnsavedChanges = false
        previewChanges = []
        showPreview = false
    }
    
    // MARK: - View Mode Management
    func toggleViewMode() {
        switch viewMode {
        case .tracks:
            viewMode = .groupedByArtist
            updateTrackGroups()
        case .groupedByArtist:
            viewMode = .tracks
            flattenTrackGroups()
        }
    }
    
    private func updateTrackGroups() {
        var groups: [String: [SpotifyPlaylistTrack]] = [:]
        
        for track in tracks {
            let artistName = track.track?.primaryArtist ?? "Unknown Artist"
            if groups[artistName] == nil {
                groups[artistName] = []
            }
            groups[artistName]?.append(track)
        }
        
        // Maintain artist order based on first appearance
        var seenArtists: [String] = []
        for track in tracks {
            let artistName = track.track?.primaryArtist ?? "Unknown Artist"
            if !seenArtists.contains(artistName) {
                seenArtists.append(artistName)
            }
        }
        
        trackGroups = seenArtists.compactMap { artistName in
            guard let artistTracks = groups[artistName] else { return nil }
            return TrackGroup(artistName: artistName, tracks: artistTracks)
        }
    }
    
    private func flattenTrackGroups() {
        tracks = trackGroups.flatMap { $0.tracks }
        checkForChanges()
    }
    
    // MARK: - Drag and Drop Operations
    func moveTrack(from sourceIndices: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: sourceIndices, toOffset: destination)
        checkForChanges()
    }
    
    func moveTrackGroup(from sourceIndices: IndexSet, to destination: Int) {
        trackGroups.move(fromOffsets: sourceIndices, toOffset: destination)
        flattenTrackGroups()
    }
    
    func moveTrackWithinGroup(groupIndex: Int, from sourceIndices: IndexSet, to destination: Int) {
        guard groupIndex < trackGroups.count else { return }
        trackGroups[groupIndex].tracks.move(fromOffsets: sourceIndices, toOffset: destination)
        flattenTrackGroups()
    }
    
    // MARK: - Grouping Operations
    func groupByArtist() {
        // Sort tracks by artist name while maintaining relative order within artist groups
        var artistGroups: [String: [SpotifyPlaylistTrack]] = [:]
        var artistOrder: [String] = []
        
        for track in tracks {
            let artistName = track.track?.primaryArtist ?? "Unknown Artist"
            if artistGroups[artistName] == nil {
                artistGroups[artistName] = []
                artistOrder.append(artistName)
            }
            artistGroups[artistName]?.append(track)
        }
        
        // Rebuild tracks array with grouped ordering
        tracks = artistOrder.flatMap { artistGroups[$0] ?? [] }
        
        if viewMode == .groupedByArtist {
            updateTrackGroups()
        }
        
        checkForChanges()
    }
    
    // MARK: - Preview System
    func generatePreview() {
        previewChanges = tracks
        showPreview = true
    }
    
    func applyPreview() {
        showPreview = false
        previewChanges = []
    }
    
    func cancelPreview() {
        showPreview = false
        previewChanges = []
    }
    
    // MARK: - Sync to Spotify
    func syncToSpotify() async {
        guard let playlist = selectedPlaylist else { return }
        guard hasUnsavedChanges else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Calculate the minimum number of API calls needed
            let reorderOperations = calculateReorderOperations()
            
            for operation in reorderOperations {
                try await spotifyAPI.reorderPlaylistTracks(
                    playlistId: playlist.id,
                    rangeStart: operation.rangeStart,
                    insertBefore: operation.insertBefore,
                    rangeLength: operation.rangeLength
                )
                
                // Small delay to avoid rate limiting
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            // Update the original order
            originalTrackOrder = tracks
            hasUnsavedChanges = false
            
        } catch {
            errorMessage = "Failed to sync to Spotify: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func calculateReorderOperations() -> [ReorderOperation] {
        var operations: [ReorderOperation] = []
        var currentOrder = originalTrackOrder
        
        for (newIndex, track) in tracks.enumerated() {
            if let currentIndex = currentOrder.firstIndex(where: { $0.id == track.id }),
               currentIndex != newIndex {
                
                // Move the track from currentIndex to newIndex
                let movedTrack = currentOrder.remove(at: currentIndex)
                currentOrder.insert(movedTrack, at: newIndex)
                
                operations.append(ReorderOperation(
                    rangeStart: currentIndex,
                    insertBefore: newIndex < currentIndex ? newIndex : newIndex + 1,
                    rangeLength: 1
                ))
            }
        }
        
        return operations
    }
    
    // MARK: - Utility Methods
    private func checkForChanges() {
        hasUnsavedChanges = !tracks.elementsEqual(originalTrackOrder) { $0.id == $1.id }
    }
    
    func discardChanges() {
        tracks = originalTrackOrder
        hasUnsavedChanges = false
        
        if viewMode == .groupedByArtist {
            updateTrackGroups()
        }
    }
    
    func refreshCurrentPlaylist() async {
        await fetchPlaylistTracks()
    }
}

// MARK: - Helper Structures
struct ReorderOperation {
    let rangeStart: Int
    let insertBefore: Int
    let rangeLength: Int
} 