//
//  LoginView.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import SwiftUI

struct LoginView: View {
    @StateObject private var authViewModel = AuthenticationViewModel()
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Logo and title
            VStack(spacing: 20) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                Text("Reordenar")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Easily reorder your Spotify playlists")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            // Error message
            if let errorMessage = authViewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.1))
                    )
                    .onTapGesture {
                        authViewModel.clearError()
                    }
            }
            
            // Sign in button
            Button(action: {
                authViewModel.signInWithSpotify()
            }) {
                HStack {
                    if authViewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "music.note")
                    }
                    
                    Text("Sign in with Spotify")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(authViewModel.isLoading)
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: 300)
            
            // Privacy note
            Text("We only access your playlists to help you reorder tracks. Your data stays secure.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    LoginView()
        .frame(width: 600, height: 500)
} 