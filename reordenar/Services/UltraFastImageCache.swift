//
//  UltraFastImageCache.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/17/25.
//

import Foundation
import SwiftUI
import Combine

/// Ultra-fast image cache optimized for smooth scrolling
@MainActor
class UltraFastImageCache: ObservableObject {
    static let shared = UltraFastImageCache()
    
    // MARK: - Private Properties
    private let memoryCache = NSCache<NSString, CachedImageData>()
    private let thumbnailCache = NSCache<NSString, CachedImageData>()
    private var downloadTasks: [String: Task<Data, Error>] = [:]
    private let maxConcurrentDownloads = 3
    private var activeDownloads = 0
    
    // Background queue for image processing
    private let processingQueue = DispatchQueue(label: "image-processing", qos: .userInitiated, attributes: .concurrent)
    
    // MARK: - Initialization
    private init() {
        // Aggressive memory caching for scrolling
        memoryCache.countLimit = 500 // More images
        memoryCache.totalCostLimit = 200 * 1024 * 1024 // 200MB for full images
        
        // Separate cache for thumbnails
        thumbnailCache.countLimit = 1000 // Even more thumbnails
        thumbnailCache.totalCostLimit = 50 * 1024 * 1024 // 50MB for thumbnails
        
        // Configure for performance
        memoryCache.evictsObjectsWithDiscardedContent = true
        thumbnailCache.evictsObjectsWithDiscardedContent = true
    }
    
    // MARK: - Public Methods
    func getImage(for urlString: String, thumbnailSize: CGSize? = nil) -> CachedImageData? {
        guard !urlString.isEmpty else { return nil }
        
        let cacheKey = cacheKeyForURL(urlString)
        let thumbnailKey = thumbnailSize != nil ? "\(cacheKey)_thumb" : cacheKey
        
        // Check thumbnail cache first if we need a thumbnail
        if let thumbnailSize = thumbnailSize {
            if let thumbnailData = thumbnailCache.object(forKey: NSString(string: thumbnailKey)) {
                return thumbnailData
            }
        }
        
        // Check main memory cache
        if let imageData = memoryCache.object(forKey: NSString(string: cacheKey)) {
            // If we need a thumbnail and don't have one, create it asynchronously
            if let thumbnailSize = thumbnailSize {
                Task {
                    await createThumbnail(from: imageData, key: thumbnailKey, size: thumbnailSize)
                }
            }
            return imageData
        }
        
        return nil
    }
    
    func loadImage(for urlString: String, thumbnailSize: CGSize? = nil) async -> CachedImageData? {
        guard !urlString.isEmpty else { return nil }
        
        // Check cache first
        if let cached = getImage(for: urlString, thumbnailSize: thumbnailSize) {
            return cached
        }
        
        // Limit concurrent downloads for performance
        guard activeDownloads < maxConcurrentDownloads else {
            return nil
        }
        
        // Check if already downloading
        if let existingTask = downloadTasks[urlString] {
            do {
                let data = try await existingTask.value
                return await processAndCacheImage(data: data, urlString: urlString, thumbnailSize: thumbnailSize)
            } catch {
                return nil
            }
        }
        
        // Start new download
        let task = Task<Data, Error> {
            activeDownloads += 1
            defer { activeDownloads -= 1 }
            
            guard let url = URL(string: urlString) else {
                throw UltraFastImageCacheError.invalidURL
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw UltraFastImageCacheError.networkError
            }
            
            return data
        }
        
        downloadTasks[urlString] = task
        
        do {
            let data = try await task.value
            downloadTasks.removeValue(forKey: urlString)
            return await processAndCacheImage(data: data, urlString: urlString, thumbnailSize: thumbnailSize)
        } catch {
            downloadTasks.removeValue(forKey: urlString)
            return nil
        }
    }
    
    // MARK: - Private Methods
    private func processAndCacheImage(data: Data, urlString: String, thumbnailSize: CGSize?) async -> CachedImageData? {
        return await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let nsImage = NSImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let imageData = CachedImageData(image: nsImage, data: data)
                let cacheKey = self.cacheKeyForURL(urlString)
                
                // Cache the full image
                Task { @MainActor in
                    let cost = data.count
                    self.memoryCache.setObject(imageData, forKey: NSString(string: cacheKey), cost: cost)
                }
                
                // Create thumbnail if needed
                if let thumbnailSize = thumbnailSize {
                    if let thumbnail = self.createThumbnailSync(from: nsImage, size: thumbnailSize) {
                        let thumbnailData = CachedImageData(image: thumbnail, data: data)
                        let thumbnailKey = "\(cacheKey)_thumb"
                        
                        Task { @MainActor in
                            let thumbnailCost = Int(thumbnailSize.width * thumbnailSize.height * 4) // Estimate
                            self.thumbnailCache.setObject(thumbnailData, forKey: NSString(string: thumbnailKey), cost: thumbnailCost)
                        }
                        
                        continuation.resume(returning: thumbnailData)
                        return
                    }
                }
                
                continuation.resume(returning: imageData)
            }
        }
    }
    
    private func createThumbnail(from imageData: CachedImageData, key: String, size: CGSize) async {
        await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                if let thumbnail = self.createThumbnailSync(from: imageData.image, size: size) {
                    let thumbnailData = CachedImageData(image: thumbnail, data: imageData.data)
                    
                    Task { @MainActor in
                        let cost = Int(size.width * size.height * 4)
                        self.thumbnailCache.setObject(thumbnailData, forKey: NSString(string: key), cost: cost)
                    }
                }
                
                continuation.resume()
            }
        }
    }
    
    private func createThumbnailSync(from image: NSImage, size: CGSize) -> NSImage? {
        let targetSize = NSSize(width: size.width, height: size.height)
        let thumbnail = NSImage(size: targetSize)
        
        thumbnail.lockFocus()
        defer { thumbnail.unlockFocus() }
        
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        
        return thumbnail
    }
    
    private func cacheKeyForURL(_ urlString: String) -> String {
        return urlString.data(using: .utf8)?.base64EncodedString() ?? urlString
    }
    
    func clearCache() {
        memoryCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        downloadTasks.removeAll()
    }
}

// MARK: - Supporting Types
class CachedImageData {
    let image: NSImage
    let data: Data
    
    init(image: NSImage, data: Data) {
        self.image = image
        self.data = data
    }
}

enum UltraFastImageCacheError: Error, LocalizedError {
    case invalidURL
    case networkError
    case processingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid image URL"
        case .networkError:
            return "Network error"
        case .processingError:
            return "Image processing error"
        }
    }
} 