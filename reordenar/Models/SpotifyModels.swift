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

struct SpotifyPlaylistTrack: Codable, Identifiable {
    let track: SpotifyTrack?
    let added_at: String
    let added_by: SpotifyUser
    let is_local: Bool
    
    var id: String {
        track?.id ?? UUID().uuidString
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
