//
//  AuthenticationViewModel.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import Foundation
import Combine
import AppKit

@MainActor
class AuthenticationViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: SpotifyUser?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let spotifyAPI = SpotifyAPIService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Subscribe to authentication state changes
        spotifyAPI.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAuthenticated)
        
        spotifyAPI.$currentUser
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentUser)
        
        // Fetch user data if we're authenticated but don't have user info
        Task {
            await fetchUserDataIfNeeded()
        }
    }
    
    func fetchUserDataIfNeeded() async {
        if isAuthenticated && currentUser == nil {
            do {
                try await spotifyAPI.fetchCurrentUser()
            } catch {
                // If we can't fetch user data, it might mean tokens are invalid
                // The user will need to re-authenticate
                print("Failed to fetch user data: \(error)")
            }
        }
    }
    
    func signInWithSpotify() {
        guard let authURL = spotifyAPI.getAuthorizationURL() else {
            errorMessage = "Failed to create authorization URL"
            return
        }
        
        // Open the authorization URL in the default browser
        NSWorkspace.shared.open(authURL)
    }
    
    func handleCallback(url: URL) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await spotifyAPI.handleAuthorizationCallback(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func signOut() {
        spotifyAPI.logout()
        currentUser = nil
        errorMessage = nil
    }
    
    func clearError() {
        errorMessage = nil
    }
} 