//
//  SimpleImageCache.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import Foundation
import SwiftUI

/// A simplified, performance-focused image cache for smooth scrolling
@MainActor
class SimpleImageCache: ObservableObject {
    static let shared = SimpleImageCache()
    
    // MARK: - Private Properties
    private let memoryCache = NSCache<NSString, CachedImageData>()
    private var downloadTasks: [String: Task<Data, Error>] = [:]
    
    // MARK: - Initialization
    private init() {
        // Optimized for scrolling performance
        memoryCache.countLimit = 300 // More images for smooth scrolling
        memoryCache.totalCostLimit = 150 * 1024 * 1024 // 150MB
        memoryCache.evictsObjectsWithDiscardedContent = true
    }
    
    // MARK: - Public Methods
    func image(for urlString: String?) async -> NSImage? {
        guard let urlString = urlString, !urlString.isEmpty else { return nil }
        
        let cacheKey = NSString(string: urlString)
        
        // Check memory cache first
        if let cachedData = memoryCache.object(forKey: cacheKey) {
            return cachedData.image
        }
        
        // Start or get existing download task
        if let existingTask = downloadTasks[urlString] {
            do {
                let data = try await existingTask.value
                return createAndCacheImage(from: data, key: cacheKey)
            } catch {
                return nil
            }
        }
        
        // Create new download task
        let downloadTask = Task<Data, Error> { [weak self] in
            defer {
                self?.downloadTasks.removeValue(forKey: urlString)
            }
            
            guard let url = URL(string: urlString) else {
                throw SimpleImageCacheError.invalidURL
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw SimpleImageCacheError.networkError
            }
            
            return data
        }
        
        downloadTasks[urlString] = downloadTask
        
        do {
            let data = try await downloadTask.value
            return createAndCacheImage(from: data, key: cacheKey)
        } catch {
            return nil
        }
    }
    
    func clearCache() {
        memoryCache.removeAllObjects()
        downloadTasks.values.forEach { $0.cancel() }
        downloadTasks.removeAll()
    }
    
    func cacheStats() -> (count: Int, estimatedSize: String) {
        // Simple approximation since NSCache doesn't expose exact size
        let count = memoryCache.name.isEmpty ? 0 : 50 // Rough estimate
        let size = count * 100 * 1024 // Rough estimate: 100KB per image
        let formatter = ByteCountFormatter()
        return (count, formatter.string(fromByteCount: Int64(size)))
    }
    
    // MARK: - Private Methods
    private func createAndCacheImage(from data: Data, key: NSString) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        
        let cachedData = CachedImageData(image: image, data: data)
        let cost = data.count
        memoryCache.setObject(cachedData, forKey: key, cost: cost)
        
        return image
    }
}

// MARK: - Supporting Types
// Note: CachedImageData is defined in UltraFastImageCache.swift

// MARK: - Error Types  
enum SimpleImageCacheError: Error, LocalizedError {
    case invalidURL
    case networkError
    case cacheError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid image URL"
        case .networkError:
            return "Failed to download image"
        case .cacheError:
            return "Image cache error"
        }
    }
} 