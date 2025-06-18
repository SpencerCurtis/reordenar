//
//  SpotifyModels.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import Foundation

// MARK: - Authentication Models
struct SpotifyTokenResponse: Codable {
    let access_token: String
    let token_type: String
    let scope: String
    let expires_in: Int
    let refresh_token: String?
}

// MARK: - User Models
struct SpotifyUser: Codable, Identifiable {
    let id: String
    let display_name: String?
    let email: String?
    let images: [SpotifyImage]?
}

struct SpotifyImage: Codable {
    let url: String
    let height: Int?
    let width: Int?
}

// MARK: - Playlist Models
struct SpotifyPlaylistsResponse: Codable {
    let items: [SpotifyPlaylist]
    let total: Int
    let limit: Int
    let offset: Int
    let next: String?
    let previous: String?
}

struct SpotifyPlaylist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let images: [SpotifyImage]?
    let tracks: SpotifyTracksInfo?
    let owner: SpotifyUser
    let isPublic: Bool?
    let collaborative: Bool?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SpotifyPlaylist, rhs: SpotifyPlaylist) -> Bool {
        lhs.id == rhs.id
    }
}

struct SpotifyTracksInfo: Codable {
    let href: String
    let total: Int
}

// MARK: - Track Models
struct SpotifyPlaylistTracksResponse: Codable {
    let items: [SpotifyPlaylistTrack]
    let total: Int
    let limit: Int
    let offset: Int
    let next: String?
    let previous: String?
}

/// Represents a track within a Spotify playlist
/// Note: Uses trackId + added_at timestamp for unique SwiftUI identification
/// This solves the duplicate ID issue when the same track appears multiple times in a playlist
struct SpotifyPlaylistTrack: Codable, Identifiable {
    let track: SpotifyTrack?
    let added_at: String
    let added_by: SpotifyUser
    let is_local: Bool
    
    var id: String {
        // Create a unique ID that combines track ID with added timestamp
        // This ensures that the same track added at different times has different IDs
        // The added_at timestamp is unique per playlist entry, solving the duplicate ID issue
        if let trackId = track?.id {
            return "\(trackId)_\(added_at)"
        } else {
            // For null tracks, use a combination of added timestamp and user ID
            return "null_\(added_at)_\(added_by.id)"
        }
    }
    
    // Keep the original track ID for API operations when needed
    var trackId: String? {
        track?.id
    }
}

struct SpotifyTrack: Codable, Identifiable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
    let duration_ms: Int
    let explicit: Bool
    let external_urls: SpotifyExternalUrls
    let preview_url: String?
    let uri: String
    
    var artistNames: String {
        artists.map { $0.name }.joined(separator: ", ")
    }
    
    var primaryArtist: String {
        artists.first?.name ?? "Unknown Artist"
    }
    
    var durationFormatted: String {
        let seconds = duration_ms / 1000
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct SpotifyArtist: Codable, Identifiable {
    let id: String
    let name: String
    let external_urls: SpotifyExternalUrls
}

struct SpotifyAlbum: Codable, Identifiable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
    let release_date: String
    let external_urls: SpotifyExternalUrls
}

struct SpotifyExternalUrls: Codable {
    let spotify: String
}

// MARK: - Reorder Models
struct SpotifyReorderRequest: Codable {
    let range_start: Int
    let insert_before: Int
    let range_length: Int?
    let snapshot_id: String?
}

// MARK: - Delete Track Models
struct SpotifyRemoveTrackRequest: Codable {
    let tracks: [SpotifyTrackToRemove]
}

struct SpotifyTrackToRemove: Codable {
    let uri: String
}

// MARK: - Error Models
struct SpotifyError: Codable {
    let error: SpotifyErrorDetails
}

struct SpotifyErrorDetails: Codable {
    let status: Int
    let message: String
}

// MARK: - Local Models for UI
struct TrackGroup: Identifiable {
    let id = UUID()
    let artistName: String
    var tracks: [SpotifyPlaylistTrack]
}

enum ViewMode {
    case tracks
    case groupedByArtist
}

// MARK: - Recently Played Models
struct SpotifyRecentlyPlayedResponse: Codable {
    let href: String
    let limit: Int
    let next: String?
    let cursors: SpotifyPlayHistoryCursors?
    let items: [SpotifyPlayHistoryObject]
}

struct SpotifyPlayHistoryCursors: Codable {
    let after: String?
    let before: String?
}

struct SpotifyPlayHistoryObject: Codable, Identifiable {
    let track: SpotifyTrack
    let played_at: String
    let context: SpotifyPlayHistoryContext?
    
    var id: String {
        "\(track.id)_\(played_at)"
    }
    
    var playedAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: played_at)
    }
}

struct SpotifyPlayHistoryContext: Codable {
    let type: String
    let href: String?
    let external_urls: SpotifyExternalUrls?
    let uri: String
    
    // Extract playlist ID from context URI if it's a playlist
    var playlistId: String? {
        if type == "playlist", uri.hasPrefix("spotify:playlist:") {
            return String(uri.dropFirst("spotify:playlist:".count))
        }
        return nil
    }
} 
