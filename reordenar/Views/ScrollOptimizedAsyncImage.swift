//
//  ScrollOptimizedAsyncImage.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/17/25.
//

import SwiftUI

/// Ultra-fast async image view optimized for smooth scrolling
struct ScrollOptimizedAsyncImage<Content: View, Placeholder: View>: View {
    private let urlString: String?
    private let thumbnailSize: CGSize
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var image: Image?
    @State private var loadingTask: Task<Void, Never>?
    
    private let imageCache = UltraFastImageCache.shared
    
    init(
        urlString: String?,
        thumbnailSize: CGSize = CGSize(width: 40, height: 40),
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.urlString = urlString
        self.thumbnailSize = thumbnailSize
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(image)
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImageIfVisible()
        }
        .onDisappear {
            cancelLoading()
        }
        .onChange(of: urlString) { _, _ in
            loadImageIfVisible()
        }
    }
    
    private func loadImageIfVisible() {
        // Cancel any existing task
        loadingTask?.cancel()
        
        guard let urlString = urlString, !urlString.isEmpty else {
            image = nil
            return
        }
        
        // Check cache immediately (synchronous)
        if let cachedImageData = imageCache.getImage(for: urlString, thumbnailSize: thumbnailSize) {
            image = Image(nsImage: cachedImageData.image)
            return
        }
        
        // Load asynchronously only if not in cache
        loadingTask = Task { @MainActor in
            // Double-check cache after task starts (race condition protection)
            if let cachedImageData = imageCache.getImage(for: urlString, thumbnailSize: thumbnailSize) {
                image = Image(nsImage: cachedImageData.image)
                return
            }
            
            // Load from network
            if let imageData = await imageCache.loadImage(for: urlString, thumbnailSize: thumbnailSize) {
                guard !Task.isCancelled else { return }
                image = Image(nsImage: imageData.image)
            }
        }
    }
    
    private func cancelLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }
}

// MARK: - Convenience Initializers
extension ScrollOptimizedAsyncImage where Content == Image, Placeholder == Color {
    init(
        urlString: String?,
        thumbnailSize: CGSize = CGSize(width: 40, height: 40)
    ) {
        self.init(
            urlString: urlString,
            thumbnailSize: thumbnailSize,
            content: { $0 },
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

extension ScrollOptimizedAsyncImage where Placeholder == Color {
    init(
        urlString: String?,
        thumbnailSize: CGSize = CGSize(width: 40, height: 40),
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            urlString: urlString,
            thumbnailSize: thumbnailSize,
            content: content,
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
} 