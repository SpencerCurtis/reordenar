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
    @Published var recentlyPlayedTracks: [SpotifyPlayHistoryObject] = []
    
    // MARK: - Pagination Properties
    @Published var isLoadingMore = false
    @Published var hasMoreTracks = false 
    @Published var totalTrackCount = 0
    private var currentOffset = 0
    private let pageSize = 50 // Load 50 tracks at a time
    
    // MARK: - Private Properties
    private let spotifyAPI = SpotifyAPIService.shared
    private var cancellables = Set<AnyCancellable>()
    private var originalTrackOrder: [SpotifyPlaylistTrack] = []
    private var playlistActivityMap: [String: Date] = [:]
    
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
            // Fetch recently played tracks first to determine playlist activity
            await fetchRecentlyPlayedTracks()
            
            let allPlaylists = try await spotifyAPI.fetchAllUserPlaylists()
            let sortedPlaylists = sortPlaylistsByRecentActivity(allPlaylists)
            playlists = sortedPlaylists
        } catch {
            errorMessage = "Failed to fetch playlists: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func fetchRecentlyPlayedTracks() async {
        do {
            let response = try await spotifyAPI.fetchRecentlyPlayedTracks(limit: 50)
            recentlyPlayedTracks = response.items
            
            // Build activity map from recently played tracks
            buildPlaylistActivityMap()
        } catch {
            // Silently handle error - recently played is optional for core functionality
            print("Failed to fetch recently played tracks: \(error.localizedDescription)")
        }
    }
    
    private func buildPlaylistActivityMap() {
        playlistActivityMap.removeAll()
        
        for track in recentlyPlayedTracks {
            if let playlistId = track.context?.playlistId,
               let playedDate = track.playedAtDate {
                
                // Keep the most recent activity for each playlist
                if let existingDate = playlistActivityMap[playlistId] {
                    if playedDate > existingDate {
                        playlistActivityMap[playlistId] = playedDate
                    }
                } else {
                    playlistActivityMap[playlistId] = playedDate
                }
            }
        }
    }
    
    private func sortPlaylistsByRecentActivity(_ playlists: [SpotifyPlaylist]) -> [SpotifyPlaylist] {
        let sorted = playlists.sorted { playlist1, playlist2 in
            let date1 = playlistActivityMap[playlist1.id]
            let date2 = playlistActivityMap[playlist2.id]
            
            switch (date1, date2) {
            case (let d1?, let d2?):
                return d1 > d2 // Most recent first
            case (_?, nil):
                return true // Has activity beats no activity
            case (nil, _?):
                return false // No activity loses to has activity
            case (nil, nil):
                return false // Maintain original order for both without activity
            }
        }
        
        return sorted
    }
    
    func selectPlaylist(_ playlist: SpotifyPlaylist) async {
        guard selectedPlaylist?.id != playlist.id else { return }
        
        selectedPlaylist = playlist
        await fetchInitialPlaylistTracks()
    }
    
    func fetchInitialPlaylistTracks() async {
        guard let playlist = selectedPlaylist else { return }
        
        isLoading = true
        errorMessage = nil
        
        // Reset pagination state
        currentOffset = 0
        tracks = []
        totalTrackCount = 0
        hasMoreTracks = false
        
        do {
            let response = try await spotifyAPI.fetchPlaylistTracks(playlistId: playlist.id, limit: pageSize, offset: 0)
            let filteredTracks = response.items.filter { $0.track != nil } // Filter out null tracks
            tracks = filteredTracks
            originalTrackOrder = tracks
            hasUnsavedChanges = false
            
            // Update pagination state
            totalTrackCount = response.total
            currentOffset = pageSize
            hasMoreTracks = tracks.count < totalTrackCount
            
            if viewMode == .groupedByArtist {
                updateTrackGroups()
            }
        } catch {
            errorMessage = "Failed to fetch tracks: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func loadMoreTracksIfNeeded() async {
        guard !isLoadingMore && hasMoreTracks else { return }
        guard let playlist = selectedPlaylist else { return }
        
        isLoadingMore = true
        
        do {
            let response = try await spotifyAPI.fetchPlaylistTracks(playlistId: playlist.id, limit: pageSize, offset: currentOffset)
            let filteredTracks = response.items.filter { $0.track != nil } // Filter out null tracks
            
            tracks.append(contentsOf: filteredTracks)
            originalTrackOrder.append(contentsOf: filteredTracks)
            
            // Update pagination state
            currentOffset += pageSize
            hasMoreTracks = tracks.count < totalTrackCount
            
            if viewMode == .groupedByArtist {
                updateTrackGroups()
            }
        } catch {
            errorMessage = "Failed to load more tracks: \(error.localizedDescription)"
        }
        
        isLoadingMore = false
    }
    
    // Legacy method for when we need to load all tracks (for operations that require it)
    func fetchAllPlaylistTracks() async {
        guard let playlist = selectedPlaylist else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let allTracks = try await spotifyAPI.fetchAllPlaylistTracks(playlistId: playlist.id)
            tracks = allTracks.filter { $0.track != nil } // Filter out null tracks
            originalTrackOrder = tracks
            hasUnsavedChanges = false
            
            // Update pagination state to reflect all tracks loaded
            totalTrackCount = tracks.count
            currentOffset = tracks.count
            hasMoreTracks = false
            
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
        recentlyPlayedTracks = []
        playlistActivityMap.removeAll()
        
        // Reset pagination state
        currentOffset = 0
        totalTrackCount = 0
        hasMoreTracks = false
        isLoadingMore = false
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
    
    // MARK: - Delete Operations
    func deleteTrack(_ track: SpotifyPlaylistTrack) {
        // Remove from local tracks array only (creates unsaved changes)
        tracks.removeAll { $0.id == track.id }
        
        // Update grouped view if needed
        if viewMode == .groupedByArtist {
            updateTrackGroups()
        }
        
        checkForChanges()
    }
    
    func deleteArtist(_ artistName: String) {
        // Remove all tracks by this artist from local tracks array
        tracks.removeAll { track in
            let trackArtist = track.track?.primaryArtist ?? "Unknown Artist"
            return trackArtist == artistName
        }
        
        // Update grouped view if needed
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
            // First, handle deletions (tracks that are in original but not in current)
            let tracksToDelete = originalTrackOrder.filter { originalTrack in
                !tracks.contains { currentTrack in currentTrack.id == originalTrack.id }
            }
            
            for track in tracksToDelete {
                if let trackUri = track.track?.uri {
                    try await spotifyAPI.removeTrackFromPlaylist(playlistId: playlist.id, trackUri: trackUri)
                    // Small delay to avoid rate limiting
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }
            
            // Then handle reordering of remaining tracks
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
    
    var deletedTracksCount: Int {
        let deletedTracks = originalTrackOrder.filter { originalTrack in
            !tracks.contains { currentTrack in currentTrack.id == originalTrack.id }
        }
        return deletedTracks.count
    }
    
    var hasReorderingChanges: Bool {
        // Check if any tracks that exist in both arrays are in different positions
        let commonTracks = tracks.filter { currentTrack in
            originalTrackOrder.contains { originalTrack in originalTrack.id == currentTrack.id }
        }
        
        let commonOriginalTracks = originalTrackOrder.filter { originalTrack in
            tracks.contains { currentTrack in currentTrack.id == originalTrack.id }
        }
        
        return !commonTracks.elementsEqual(commonOriginalTracks) { $0.id == $1.id }
    }
    
    var changesSummary: String {
        var changes: [String] = []
        
        if deletedTracksCount > 0 {
            changes.append("\(deletedTracksCount) deleted")
        }
        
        if hasReorderingChanges {
            changes.append("reordered")
        }
        
        return changes.isEmpty ? "Unsaved changes" : changes.joined(separator: ", ")
    }
    
    func discardChanges() {
        tracks = originalTrackOrder
        hasUnsavedChanges = false
        
        if viewMode == .groupedByArtist {
            updateTrackGroups()
        }
    }
    
    func refreshCurrentPlaylist() async {
        // If user has unsaved changes, we should preserve them and just refresh what we can
        if hasUnsavedChanges {
            // For now, just refresh the playlist list order
            await refreshPlaylistOrder()
        } else {
            // Safe to refresh tracks from beginning
            await fetchInitialPlaylistTracks()
        }
    }
    
    func refreshPlaylistOrder() async {
        await fetchRecentlyPlayedTracks()
        let sortedPlaylists = sortPlaylistsByRecentActivity(playlists)
        playlists = sortedPlaylists
    }
}

// MARK: - Helper Structures
struct ReorderOperation {
    let rangeStart: Int
    let insertBefore: Int
    let rangeLength: Int
} 