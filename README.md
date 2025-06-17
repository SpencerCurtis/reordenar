# Reordenar - Spotify Playlist Reorder Tool

A macOS app built with SwiftUI that allows you to easily reorder tracks in your Spotify playlists with drag-and-drop functionality and intelligent artist grouping.

## Features

✅ **OAuth Authentication** - Secure login with Spotify using Authorization Code Flow  
✅ **Playlist Management** - Browse and select from your Spotify playlists  
✅ **Drag & Drop Reordering** - Intuitive track reordering with visual feedback  
✅ **Group by Artist** - Automatically cluster tracks by artist for easy organization  
✅ **Artist Group Management** - Drag entire artist groups or individual tracks within groups  
✅ **Preview Changes** - Review your changes before syncing to Spotify  
✅ **Batch Sync** - Efficient API calls to minimize requests to Spotify  
✅ **Secure Token Storage** - Access tokens stored securely in macOS Keychain  
✅ **Change Tracking** - Visual indicators for unsaved changes  

## Setup Instructions

### 1. Spotify App Registration

1. Go to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
2. Create a new app
3. Add `reordenar://callback` to your app's redirect URIs
4. Note your **Client ID** and **Client Secret**

### 2. Configure the App

1. Open `reordenar/Services/SpotifyAPIService.swift`
2. Replace the placeholder values:
   ```swift
   private let clientId = "YOUR_SPOTIFY_CLIENT_ID"
   private let clientSecret = "YOUR_SPOTIFY_CLIENT_SECRET"
   ```

### 3. Build and Run

1. Open `reordenar.xcodeproj` in Xcode
2. Select your development team in the project settings
3. Build and run the app

## Usage

### Authentication
1. Launch the app and click "Sign in with Spotify"
2. Complete the OAuth flow in your browser
3. Return to the app to see your playlists

### Reordering Tracks
1. Select a playlist from the sidebar
2. Drag tracks to reorder them in the main view
3. Use "Group by Artist" to cluster tracks by artist
4. Preview your changes before syncing
5. Click "Sync to Spotify" to apply changes

### View Modes

**Tracks View**: 
- Shows all tracks in a flat list
- Drag individual tracks to reorder
- Track numbers show current position

**Grouped by Artist View**: 
- Tracks are grouped by artist
- Drag entire artist groups to reorder artists
- Drag individual tracks within artist groups
- Group headers show artist name and track count

### Controls

- **Group by Artist** - Automatically clusters tracks by artist
- **Toggle View Mode** - Switch between flat and grouped views
- **Preview** - Review changes before syncing
- **Discard** - Revert unsaved changes
- **Sync to Spotify** - Apply changes to your Spotify playlist
- **Refresh** - Reload playlist data

## Architecture

The app follows the MVVM (Model-View-ViewModel) pattern:

- **Models** (`SpotifyModels.swift`) - Data structures for Spotify API responses
- **Services** - API communication and keychain management
  - `SpotifyAPIService.swift` - Handles all Spotify API interactions
  - `KeychainService.swift` - Secure token storage
- **ViewModels** - Business logic and state management
  - `PlaylistViewModel.swift` - Manages playlist and track data
  - `AuthenticationViewModel.swift` - Handles authentication state
- **Views** - SwiftUI user interface components
  - `ContentView.swift` - Main app coordinator
  - `LoginView.swift` - Authentication interface
  - `PlaylistSidebarView.swift` - Playlist selection sidebar
  - `TrackListView.swift` - Main track reordering interface
  - `PreviewView.swift` - Change preview modal

## Security

- **Token Storage**: Access tokens are stored securely in the macOS Keychain
- **Network Security**: Uses TLS 1.2+ for all API communications
- **Sandboxed**: App runs in a macOS sandbox for enhanced security
- **Minimal Permissions**: Only requests necessary Spotify scopes

## Required Spotify Scopes

- `playlist-read-private` - Read user's private playlists
- `playlist-modify-private` - Modify user's private playlists
- `playlist-modify-public` - Modify user's public playlists

## System Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later for development
- Active Spotify account
- Internet connection

## Troubleshooting

### Authentication Issues
- Ensure your redirect URI is exactly `reordenar://callback`
- Check that your Client ID and Client Secret are correct
- Verify your Spotify app is not in development mode restrictions

### Sync Issues
- Check your internet connection
- Ensure you have permission to modify the playlist
- Try refreshing the playlist and attempting sync again

### Performance
- Large playlists (500+ tracks) may take longer to load
- Consider breaking very large playlists into smaller ones for better performance

## Contributing

This app was built as a demonstration of SwiftUI and Spotify API integration. Feel free to extend and modify it for your needs.

## License

This project is for educational and personal use. Please respect Spotify's API terms of service. 