//
//  FastAsyncImage.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import SwiftUI

/// A performance-optimized async image view for smooth scrolling
struct FastAsyncImage<Content: View, Placeholder: View>: View {
    private let urlString: String?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var image: Image?
    @State private var isLoading = false
    @State private var loadingTask: Task<Void, Never>?
    
    private let imageCache = SimpleImageCache.shared
    
    init(
        urlString: String?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.urlString = urlString
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
                                    .scaleEffect(0.5)
                                    .tint(.secondary)
                            }
                        }
                    )
            }
        }
        .onAppear {
            loadImageIfNeeded()
        }
        .onDisappear {
            cancelLoading()
        }
        .onChange(of: urlString) { _, _ in
            image = nil
            cancelLoading()
            loadImageIfNeeded()
        }
    }
    
    private func loadImageIfNeeded() {
        guard urlString != nil, image == nil, loadingTask == nil else { return }
        
        loadingTask = Task { @MainActor in
            isLoading = true
            defer { 
                isLoading = false
                loadingTask = nil
            }
            
            if let nsImage = await imageCache.image(for: urlString) {
                if !Task.isCancelled {
                    image = Image(nsImage: nsImage)
                }
            }
        }
    }
    
    private func cancelLoading() {
        loadingTask?.cancel()
        loadingTask = nil
        isLoading = false
    }
}

// MARK: - Convenience Initializers
extension FastAsyncImage where Content == Image, Placeholder == Color {
    init(urlString: String?) {
        self.init(
            urlString: urlString,
            content: { image in image },
            placeholder: { Color.gray.opacity(0.2) }
        )
    }
}

extension FastAsyncImage where Placeholder == Color {
    init(
        urlString: String?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            urlString: urlString,
            content: content,
            placeholder: { Color.gray.opacity(0.2) }
        )
    }
}

extension FastAsyncImage where Content == Image {
    init(
        urlString: String?,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            urlString: urlString,
            content: { image in image },
            placeholder: placeholder
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        FastAsyncImage(urlString: "https://via.placeholder.com/150")
            .frame(width: 150, height: 150)
        
        FastAsyncImage(
            urlString: "https://via.placeholder.com/100",
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