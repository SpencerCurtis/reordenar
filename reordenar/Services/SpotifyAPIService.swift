//
//  SpotifyAPIService.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import Foundation
import Combine

class SpotifyAPIService: ObservableObject {
    static let shared = SpotifyAPIService()
    
    // MARK: - Configuration
    private let clientId: String
    private let clientSecret: String
    private let redirectUri = "reordenar://callback"
    private let baseURL = "https://api.spotify.com/v1"
    private let accountsURL = "https://accounts.spotify.com"
    
    // MARK: - Properties
    @Published var isAuthenticated = false
    @Published var currentUser: SpotifyUser?
    
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpirationDate: Date?
    
    private let keychain = KeychainService.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Load credentials from Config.plist
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path),
              let clientId = config["SpotifyClientID"] as? String,
              let clientSecret = config["SpotifyClientSecret"] as? String else {
            fatalError("Config.plist not found or missing Spotify credentials. Please create Config.plist with SpotifyClientID and SpotifyClientSecret.")
        }
        
        self.clientId = clientId
        self.clientSecret = clientSecret
        
        loadStoredTokens()
    }
    
    // MARK: - Authentication
    func getAuthorizationURL() -> URL? {
        let scopes = "playlist-read-private playlist-modify-private playlist-modify-public user-read-recently-played"
        let state = UUID().uuidString
        
        var components = URLComponents(string: "\(accountsURL)/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state)
        ]
        
        return components?.url
    }
    
    func handleAuthorizationCallback(url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw SpotifyAPIError.invalidURL
        }
        
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            throw SpotifyAPIError.authorizationFailed(error)
        }
        
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw SpotifyAPIError.missingAuthorizationCode
        }
        
        try await exchangeCodeForTokens(code: code)
    }
    
    private func exchangeCodeForTokens(code: String) async throws {
        guard let url = URL(string: "\(accountsURL)/api/token") else {
            throw SpotifyAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let credentials = "\(clientId):\(clientSecret)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri
        ]
        
        request.httpBody = body.percentEncoded()
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyAPIError.tokenExchangeFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        
        await MainActor.run {
            self.accessToken = tokenResponse.access_token
            self.refreshToken = tokenResponse.refresh_token
            self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
            self.isAuthenticated = true
        }
        
        try storeTokens()
        try await fetchCurrentUser()
    }
    
    private func storeTokens() throws {
        if let accessToken = accessToken {
            try keychain.saveAccessToken(accessToken)
        }
        if let refreshToken = refreshToken {
            try keychain.saveRefreshToken(refreshToken)
        }
    }
    
    private func loadStoredTokens() {
        do {
            accessToken = try keychain.loadAccessToken()
            refreshToken = try keychain.loadRefreshToken()
            isAuthenticated = accessToken != nil
        } catch {
            // No stored tokens, user needs to authenticate
            isAuthenticated = false
        }
    }
    
    private func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw SpotifyAPIError.noRefreshToken
        }
        
        guard let url = URL(string: "\(accountsURL)/api/token") else {
            throw SpotifyAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let credentials = "\(clientId):\(clientSecret)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        
        request.httpBody = body.percentEncoded()
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyAPIError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        
        await MainActor.run {
            self.accessToken = tokenResponse.access_token
            if let newRefreshToken = tokenResponse.refresh_token {
                self.refreshToken = newRefreshToken
            }
            self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        }
        
        try storeTokens()
    }
    
    // MARK: - API Requests
    private func authenticatedRequest(url: URL) async throws -> URLRequest {
        // Check if token needs refresh
        if let expirationDate = tokenExpirationDate, Date() > expirationDate {
            try await refreshAccessToken()
        }
        
        guard let accessToken = accessToken else {
            throw SpotifyAPIError.notAuthenticated
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
    
    // MARK: - User API
    func fetchCurrentUser() async throws {
        guard let url = URL(string: "\(baseURL)/me") else {
            throw SpotifyAPIError.invalidURL
        }
        
        let request = try await authenticatedRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let user = try JSONDecoder().decode(SpotifyUser.self, from: data)
        
        await MainActor.run {
            self.currentUser = user
        }
    }
    
    // MARK: - Playlist API
    func fetchUserPlaylists(limit: Int = 50, offset: Int = 0) async throws -> SpotifyPlaylistsResponse {
        guard let url = URL(string: "\(baseURL)/me/playlists?limit=\(limit)&offset=\(offset)") else {
            throw SpotifyAPIError.invalidURL
        }
        
        let request = try await authenticatedRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)
        
        return try JSONDecoder().decode(SpotifyPlaylistsResponse.self, from: data)
    }
    
    func fetchPlaylistTracks(playlistId: String, limit: Int = 100, offset: Int = 0) async throws -> SpotifyPlaylistTracksResponse {
        guard let url = URL(string: "\(baseURL)/playlists/\(playlistId)/tracks?limit=\(limit)&offset=\(offset)") else {
            throw SpotifyAPIError.invalidURL
        }
        
        let request = try await authenticatedRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)
        
        return try JSONDecoder().decode(SpotifyPlaylistTracksResponse.self, from: data)
    }
    
    // MARK: - Recently Played API
    func fetchRecentlyPlayedTracks(limit: Int = 50, after: Int? = nil, before: Int? = nil) async throws -> SpotifyRecentlyPlayedResponse {
        var urlString = "\(baseURL)/me/player/recently-played?limit=\(limit)"
        
        if let after = after {
            urlString += "&after=\(after)"
        }
        
        if let before = before {
            urlString += "&before=\(before)"
        }
        
        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURL
        }
        
        let request = try await authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }
        
        if httpResponse.statusCode == 403 {
            throw SpotifyAPIError.insufficientScope
        }
        
        if httpResponse.statusCode != 200 {
            throw SpotifyAPIError.apiError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(SpotifyRecentlyPlayedResponse.self, from: data)
    }
    
    // MARK: - Reorder API
    func reorderPlaylistTracks(playlistId: String, rangeStart: Int, insertBefore: Int, rangeLength: Int = 1) async throws {
        guard let url = URL(string: "\(baseURL)/playlists/\(playlistId)/tracks") else {
            throw SpotifyAPIError.invalidURL
        }
        
        var request = try await authenticatedRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let reorderRequest = SpotifyReorderRequest(
            range_start: rangeStart,
            insert_before: insertBefore,
            range_length: rangeLength,
            snapshot_id: nil
        )
        
        request.httpBody = try JSONEncoder().encode(reorderRequest)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyAPIError.reorderFailed
        }
    }
    
    // MARK: - Logout
    func logout() {
        accessToken = nil
        refreshToken = nil
        tokenExpirationDate = nil
        currentUser = nil
        isAuthenticated = false
        
        try? keychain.deleteAllTokens()
    }
}

// MARK: - Error Types
enum SpotifyAPIError: Error {
    case invalidURL
    case notAuthenticated
    case authorizationFailed(String)
    case missingAuthorizationCode
    case tokenExchangeFailed
    case tokenRefreshFailed
    case noRefreshToken
    case reorderFailed
    case invalidResponse
    case insufficientScope
    case apiError(Int)
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .notAuthenticated:
            return "Not authenticated with Spotify"
        case .authorizationFailed(let error):
            return "Authorization failed: \(error)"
        case .missingAuthorizationCode:
            return "Missing authorization code"
        case .tokenExchangeFailed:
            return "Failed to exchange code for tokens"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .noRefreshToken:
            return "No refresh token available"
        case .reorderFailed:
            return "Failed to reorder playlist tracks"
        case .invalidResponse:
            return "Invalid response from Spotify"
        case .insufficientScope:
            return "Insufficient scope for the recently played endpoint"
        case .apiError(let statusCode):
            return "API error: \(statusCode)"
        }
    }
}

// MARK: - Helper Extensions
extension Dictionary where Key == String, Value == String {
    func percentEncoded() -> Data? {
        map { key, value in
            let escapedKey = "\(key)".addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
            let escapedValue = "\(value)".addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
            return "\(escapedKey)=\(escapedValue)"
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
        let subDelimitersToEncode = "!$&'()*+,;="
        
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")
        return allowed
    }()
} 