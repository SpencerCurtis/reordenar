//
//  CachedAsyncImage.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import SwiftUI

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var image: Image?
    @State private var isLoading = false
    
    private let imageCache = ImageCacheService.shared
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(image)
            } else {
                placeholder()
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.secondary)
                            }
                        }
                    )
            }
        }
        .task(id: url?.absoluteString) {
            await loadImage()
        }
    }
    
    @MainActor
    private func loadImage() async {
        guard let url = url else { return }
        
        isLoading = true
        
        do {
            let imageData = try await imageCache.loadImage(from: url.absoluteString)
            
            #if canImport(AppKit)
            if let nsImage = NSImage(data: imageData) {
                image = Image(nsImage: nsImage)
            }
            #elseif canImport(UIKit)
            if let uiImage = UIImage(data: imageData) {
                image = Image(uiImage: uiImage)
            }
            #endif
        } catch {
            // Image failed to load, keep placeholder
            print("Failed to load image: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
}

// MARK: - Convenience Initializers
extension CachedAsyncImage where Content == Image, Placeholder == Color {
    init(url: URL?) {
        self.init(
            url: url,
            content: { image in image },
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

extension CachedAsyncImage where Placeholder == Color {
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            url: url,
            content: content,
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

extension CachedAsyncImage where Content == Image {
    init(
        url: URL?,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            url: url,
            content: { image in image },
            placeholder: placeholder
        )
    }
}

// MARK: - String URL Convenience
extension CachedAsyncImage {
    init(
        urlString: String?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        let url = urlString.flatMap(URL.init(string:))
        self.init(url: url, content: content, placeholder: placeholder)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Basic usage
        CachedAsyncImage(url: URL(string: "https://via.placeholder.com/150"))
            .frame(width: 150, height: 150)
        
        // Custom content and placeholder
        CachedAsyncImage(
            url: URL(string: "https://via.placeholder.com/100"),
            content: { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            },
            placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                    )
            }
        )
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .padding()
} 