# Reordenar - Spotify Playlist Reorder Tool

A macOS app built with SwiftUI that allows you to easily reorder tracks in your Spotify playlists with drag-and-drop functionality, intelligent artist grouping, and smart playlist ordering based on your listening history.

## Features

✅ **OAuth Authentication** - Secure login with Spotify using Authorization Code Flow  
✅ **Smart Playlist Ordering** - Playlists automatically sorted by recent activity from your listening history  
✅ **Playlist Management** - Browse and select from your Spotify playlists with pagination support  
✅ **Drag & Drop Reordering** - Intuitive track reordering with visual feedback  
✅ **Group by Artist** - Automatically cluster tracks by artist for easy organization  
✅ **Artist Group Management** - Drag entire artist groups or individual tracks within groups  
✅ **Performance Optimized Loading** - Intelligent pagination with "Load All" option for large playlists  
✅ **Advanced Image Caching** - Ultra-fast album artwork loading with memory optimization  
✅ **Preview Changes** - Review your changes before syncing to Spotify  
✅ **Batch Sync** - Efficient API calls to minimize requests to Spotify  
✅ **Secure Token Storage** - Access tokens stored securely in macOS Keychain  
✅ **Change Tracking** - Visual indicators for unsaved changes with detailed summaries  
✅ **Recently Played Integration** - Playlists sorted by recent listening activity  

## Setup Instructions

### 1. Spotify App Registration

1. Go to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
2. Create a new app
3. Add `reordenar://callback` to your app's redirect URIs
4. Note your **Client ID** and **Client Secret**

### 2. Configure the App

1. Create a `Config.plist` file in the `reordenar/` directory (same level as `reordenarApp.swift`)
2. Add your Spotify credentials:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>SpotifyClientID</key>
       <string>YOUR_SPOTIFY_CLIENT_ID</string>
       <key>SpotifyClientSecret</key>
       <string>YOUR_SPOTIFY_CLIENT_SECRET</string>
   </dict>
   </plist>
   ```

**Important**: `Config.plist` is gitignored for security. Never commit credentials to version control.

### 3. Build and Run

1. Open `reordenar.xcodeproj` in Xcode
2. Select your development team in the project settings
3. Build and run the app

## Usage

### Authentication
1. Launch the app and click "Sign in with Spotify"
2. Complete the OAuth flow in your browser
3. Return to the app to see your playlists

### Smart Playlist Ordering
- Playlists are automatically ordered by recent activity
- Recently played tracks determine which playlists appear at the top
- Refresh to update the ordering based on new listening activity

### Reordering Tracks

#### Performance Mode (Default)
- Playlists load 50 tracks at a time for smooth performance
- Scroll to bottom to load more tracks automatically
- Use "Load All" button for full playlist access when reordering

#### Track Reordering
1. Select a playlist from the sidebar
2. Drag tracks to reorder them in the main view
3. Use "Group by Artist" to cluster tracks by artist
4. Use "Cluster by Artist" to automatically reorder tracks by artist groupings
5. Preview your changes before syncing
6. Click "Sync to Spotify" to apply changes

### View Modes

**Tracks View**: 
- Shows all tracks in a flat list
- Drag individual tracks to reorder
- Track numbers show current position
- "Cluster by Artist" automatically groups similar artists together

**Grouped by Artist View**: 
- Tracks are grouped by artist
- Drag entire artist groups to reorder artists
- Drag individual tracks within artist groups
- Group headers show artist name and track count

### Controls

- **Load All** - Load all tracks in playlist (appears when there are more than 50 tracks)
- **Group by Artist** - Switch to grouped view mode
- **Show All Tracks** - Switch back to flat list view
- **Cluster by Artist** - Automatically reorder tracks to group by artist
- **Preview** - Review changes before syncing with detailed track list
- **Discard** - Revert unsaved changes
- **Sync to Spotify** - Apply changes to your Spotify playlist
- **Refresh** - Reload playlists and update recent activity order

## Architecture

The app follows the MVVM (Model-View-ViewModel) pattern with advanced performance optimizations:

### Core Architecture
- **Models** (`SpotifyModels.swift`) - Data structures for Spotify API responses and recently played tracks
- **Services** - API communication, security, and performance optimization
  - `SpotifyAPIService.swift` - Handles all Spotify API interactions including recently played
  - `KeychainService.swift` - Secure token storage with automatic refresh
  - `UltraFastImageCache.swift` - Advanced image caching with thumbnail generation
  - `HybridImageCache.swift` - Multi-tier caching system for optimal performance
- **ViewModels** - Business logic and state management
  - `PlaylistViewModel.swift` - Manages playlist data, pagination, and change tracking
  - `AuthenticationViewModel.swift` - Handles authentication state and user management
- **Views** - SwiftUI user interface components
  - `ContentView.swift` - Main app coordinator with navigation split view
  - `LoginView.swift` - Authentication interface
  - `PlaylistSidebarView.swift` - Smart playlist selection sidebar
  - `TrackListView.swift` - Performance-optimized track reordering interface
  - `PreviewView.swift` - Change preview modal with detailed track listing
  - `ScrollOptimizedAsyncImage.swift` - Optimized image loading for smooth scrolling

### Performance Features
- **Intelligent Pagination** - Loads playlists in chunks of 50 tracks
- **Advanced Image Caching** - Multiple caching strategies for album artwork
- **Memory Optimization** - Efficient memory usage for large playlists
- **Smooth Scrolling** - Optimized rendering for thousands of tracks

## Security

- **Token Storage**: Access tokens stored securely in macOS Keychain with service-specific identifiers
- **Network Security**: Uses TLS 1.2+ for all API communications
- **Sandboxed**: App runs in a macOS sandbox for enhanced security
- **Credential Management**: Sensitive configuration stored in gitignored `Config.plist`
- **Minimal Permissions**: Only requests necessary Spotify scopes

## Required Spotify Scopes

- `playlist-read-private` - Read user's private playlists
- `playlist-modify-private` - Modify user's private playlists
- `playlist-modify-public` - Modify user's public playlists
- `user-read-recently-played` - Read recently played tracks for smart ordering

## System Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later for development
- Active Spotify account
- Internet connection

## Troubleshooting

### Authentication Issues
- Ensure your redirect URI is exactly `reordenar://callback`
- Check that your `Config.plist` file exists and contains correct credentials
- Verify your Spotify app is not in development mode restrictions

### Performance Issues
- Large playlists (1000+ tracks) use pagination by default
- Use "Load All" only when necessary for reordering operations
- Album artwork caching improves performance on subsequent loads

### Sync Issues
- Check your internet connection
- Ensure you have permission to modify the playlist
- Try refreshing the playlist and attempting sync again
- Verify all tracks are loaded if reordering across page boundaries

### Recently Played Features
- Recently played data may take a moment to load
- Playlist ordering updates when you refresh
- This feature requires the `user-read-recently-played` scope

## Contributing

This app demonstrates modern SwiftUI patterns, advanced performance optimization, and comprehensive Spotify API integration. The codebase follows strict MVVM architecture with emphasis on performance and user experience.

## License

This project is for educational and personal use. Please respect Spotify's API terms of service. 