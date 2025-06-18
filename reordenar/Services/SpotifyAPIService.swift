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
        if let tokenExpirationDate = tokenExpirationDate {
            try keychain.saveTokenExpirationDate(tokenExpirationDate)
        }
    }
    
    private func loadStoredTokens() {
        do {
            accessToken = try keychain.loadAccessToken()
            refreshToken = try keychain.loadRefreshToken()
            tokenExpirationDate = try? keychain.loadTokenExpirationDate()
            isAuthenticated = accessToken != nil
            
            // If we have tokens but they're expired, try to refresh immediately
            if isAuthenticated, let expirationDate = tokenExpirationDate, Date() > expirationDate {
                Task {
                    do {
                        try await refreshAccessToken()
                    } catch {
                        print("Failed to refresh expired token on startup: \(error)")
                        // If refresh fails, clear tokens and require re-authentication
                        await MainActor.run {
                            self.logout()
                        }
                    }
                }
            }
            
            // Load stored user data if we have tokens
            if isAuthenticated {
                loadStoredUser()
            }
        } catch {
            // No stored tokens, user needs to authenticate
            isAuthenticated = false
        }
    }
    
    private func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            print("No refresh token available")
            throw SpotifyAPIError.noRefreshToken
        }
        
        guard let url = URL(string: "\(accountsURL)/api/token") else {
            throw SpotifyAPIError.invalidURL
        }
        
        print("Attempting to refresh access token...")
        
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
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response type during token refresh")
            throw SpotifyAPIError.tokenRefreshFailed
        }
        
        guard httpResponse.statusCode == 200 else {
            print("Token refresh failed with status code: \(httpResponse.statusCode)")
            if let errorData = String(data: data, encoding: .utf8) {
                print("Error response: \(errorData)")
            }
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
        print("Access token refreshed successfully")
    }
    
    // MARK: - API Requests
    private func authenticatedRequest(url: URL) async throws -> URLRequest {
        // Check if token needs refresh
        if let expirationDate = tokenExpirationDate, Date() > expirationDate {
            do {
                try await refreshAccessToken()
            } catch {
                print("Token refresh failed, logging out user: \(error)")
                await MainActor.run {
                    self.logout()
                }
                throw SpotifyAPIError.notAuthenticated
            }
        }
        
        guard let accessToken = accessToken else {
            print("No access token available, user needs to re-authenticate")
            await MainActor.run {
                self.logout()
            }
            throw SpotifyAPIError.notAuthenticated
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
    
    // MARK: - Safe API Call Wrapper
    private func performAuthenticatedAPICall<T>(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        decode: (Data) throws -> T
    ) async throws -> T {
        do {
            var request = try await authenticatedRequest(url: url)
            request.httpMethod = method
            
            if let body = body {
                request.httpBody = body
            }
            
            if let contentType = contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SpotifyAPIError.invalidResponse
            }
            
            // Handle authentication errors by logging out
            if httpResponse.statusCode == 401 {
                print("Received 401 Unauthorized, logging out user")
                await MainActor.run {
                    self.logout()
                }
                throw SpotifyAPIError.notAuthenticated
            }
            
            // Handle other HTTP errors
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 403 {
                    throw SpotifyAPIError.insufficientScope
                }
                throw SpotifyAPIError.apiError(httpResponse.statusCode)
            }
            
            return try decode(data)
        } catch SpotifyAPIError.notAuthenticated {
            // Re-throw authentication errors
            throw SpotifyAPIError.notAuthenticated
        } catch {
            // For any other error, check if it might be authentication-related
            print("API call failed: \(error)")
            throw error
        }
    }
    
    // MARK: - User API
    func fetchCurrentUser() async throws {
        guard let url = URL(string: "\(baseURL)/me") else {
            throw SpotifyAPIError.invalidURL
        }
        
        let user = try await performAuthenticatedAPICall(url: url) { data in
            try JSONDecoder().decode(SpotifyUser.self, from: data)
        }
        
        await MainActor.run {
            self.currentUser = user
        }
        
        // Store user data for persistence
        let userData = try JSONEncoder().encode(user)
        try storeUserData(userData)
    }
    
    private func storeUserData(_ userData: Data) throws {
        try keychain.saveUserData(userData)
    }
    
    private func loadStoredUser() {
        do {
            let userData = try keychain.loadUserData()
            let user = try JSONDecoder().decode(SpotifyUser.self, from: userData)
            currentUser = user
        } catch {
            // No stored user data, will be fetched on next API call
            currentUser = nil
        }
    }
    
    // MARK: - Playlist API
    func fetchUserPlaylists(limit: Int = 50, offset: Int = 0) async throws -> SpotifyPlaylistsResponse {
        guard let url = URL(string: "\(baseURL)/me/playlists?limit=\(limit)&offset=\(offset)") else {
            throw SpotifyAPIError.invalidURL
        }
        
        return try await performAuthenticatedAPICall(url: url) { data in
            try JSONDecoder().decode(SpotifyPlaylistsResponse.self, from: data)
        }
    }
    
    func fetchAllUserPlaylists() async throws -> [SpotifyPlaylist] {
        var allPlaylists: [SpotifyPlaylist] = []
        var offset = 0
        let limit = 50
        
        repeat {
            let response = try await fetchUserPlaylists(limit: limit, offset: offset)
            allPlaylists.append(contentsOf: response.items)
            offset += limit
            
            // Continue if we have more playlists to fetch
            if response.next == nil || response.items.count < limit {
                break
            }
        } while true
        
        return allPlaylists
    }
    
    func fetchPlaylistTracks(playlistId: String, limit: Int = 100, offset: Int = 0) async throws -> SpotifyPlaylistTracksResponse {
        guard let url = URL(string: "\(baseURL)/playlists/\(playlistId)/tracks?limit=\(limit)&offset=\(offset)") else {
            throw SpotifyAPIError.invalidURL
        }
        
        return try await performAuthenticatedAPICall(url: url) { data in
            try JSONDecoder().decode(SpotifyPlaylistTracksResponse.self, from: data)
        }
    }
    
    func fetchAllPlaylistTracks(playlistId: String) async throws -> [SpotifyPlaylistTrack] {
        var allTracks: [SpotifyPlaylistTrack] = []
        var offset = 0
        let limit = 100
        
        repeat {
            let response = try await fetchPlaylistTracks(playlistId: playlistId, limit: limit, offset: offset)
            allTracks.append(contentsOf: response.items)
            offset += limit
            
            // Continue if we have more tracks to fetch
            if response.next == nil || response.items.count < limit {
                break
            }
        } while true
        
        return allTracks
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
        
        return try await performAuthenticatedAPICall(url: url) { data in
            try JSONDecoder().decode(SpotifyRecentlyPlayedResponse.self, from: data)
        }
    }
    
        // MARK: - Reorder API
    func reorderPlaylistTracks(playlistId: String, rangeStart: Int, insertBefore: Int, rangeLength: Int = 1) async throws {
        guard let url = URL(string: "\(baseURL)/playlists/\(playlistId)/tracks") else {
            throw SpotifyAPIError.invalidURL
        }

        let reorderRequest = SpotifyReorderRequest(
            range_start: rangeStart,
            insert_before: insertBefore,
            range_length: rangeLength,
            snapshot_id: nil
        )

        let requestBody = try JSONEncoder().encode(reorderRequest)

        let _ = try await performAuthenticatedAPICall(
            url: url,
            method: "PUT",
            body: requestBody,
            contentType: "application/json"
        ) { data in
            // Just return empty data for successful reorder
            return data
        }
    }
    
    // MARK: - Delete Track API
    func removeTrackFromPlaylist(playlistId: String, trackUri: String) async throws {
        guard let url = URL(string: "\(baseURL)/playlists/\(playlistId)/tracks") else {
            throw SpotifyAPIError.invalidURL
        }

        let removeRequest = SpotifyRemoveTrackRequest(
            tracks: [SpotifyTrackToRemove(uri: trackUri)]
        )

        let requestBody = try JSONEncoder().encode(removeRequest)

        let _ = try await performAuthenticatedAPICall(
            url: url,
            method: "DELETE",
            body: requestBody,
            contentType: "application/json"
        ) { data in
            // Just return empty data for successful delete
            return data
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
    case deleteFailed
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
        case .deleteFailed:
            return "Failed to delete track from playlist"
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