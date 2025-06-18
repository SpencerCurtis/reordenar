//
//  HybridImageCache.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import Foundation
import SwiftUI
import SwiftData

/// A hybrid image cache that provides fast memory access with persistent storage for offline use
@MainActor
class HybridImageCache: ObservableObject {
    static let shared = HybridImageCache()
    
    // MARK: - Private Properties
    private let memoryCache = NSCache<NSString, CachedImageData>()
    private var downloadTasks: [String: Task<Data, Error>] = [:]
    private var modelContext: ModelContext?
    
    // Background actor for database operations
    private let databaseActor = DatabaseActor()
    
    // MARK: - Initialization
    private init() {
        // Optimized memory cache for scrolling
        memoryCache.countLimit = 300
        memoryCache.totalCostLimit = 150 * 1024 * 1024 // 150MB
        memoryCache.evictsObjectsWithDiscardedContent = true
    }
    
    // MARK: - Configuration
    func configure(with modelContainer: ModelContainer) {
        // Keep a reference to the main context for any main-thread operations
        self.modelContext = modelContainer.mainContext
        Task {
            await databaseActor.configure(with: modelContainer)
        }
    }
    
    // MARK: - Public Methods
    func image(for urlString: String?) async -> NSImage? {
        guard let urlString = urlString, !urlString.isEmpty else { return nil }
        
        let cacheKey = NSString(string: urlString)
        
        // 1. Check memory cache first (instant)
        if let cachedData = memoryCache.object(forKey: cacheKey) {
            return cachedData.image
        }
        
        // 2. Check if already downloading
        if let existingTask = downloadTasks[urlString] {
            do {
                let data = try await existingTask.value
                return await createAndCacheImage(from: data, urlString: urlString, cacheKey: cacheKey)
            } catch {
                return nil
            }
        }
        
        // 3. Try to load from persistent storage (background)
        if let persistentData = await databaseActor.getCachedImage(for: urlString) {
            return await createAndCacheImage(from: persistentData, urlString: urlString, cacheKey: cacheKey)
        }
        
        // 4. Download from network
        return await downloadImage(urlString: urlString, cacheKey: cacheKey)
    }
    
    func clearCache() async {
        // Clear memory cache
        memoryCache.removeAllObjects()
        
        // Cancel downloads
        downloadTasks.values.forEach { $0.cancel() }
        downloadTasks.removeAll()
        
        // Clear persistent cache
        await databaseActor.clearAllCache()
    }
    
    func cacheStats() async -> (memoryCount: Int, diskCount: Int, totalSize: String) {
        let diskStats = await databaseActor.getCacheStats()
        let formatter = ByteCountFormatter()
        return (
            memoryCount: memoryCache.description.count, // Approximation
            diskCount: diskStats.count,
            totalSize: formatter.string(fromByteCount: Int64(diskStats.totalSize))
        )
    }
    
    // MARK: - Private Methods
    private func downloadImage(urlString: String, cacheKey: NSString) async -> NSImage? {
        let downloadTask = Task<Data, Error> { [weak self] in
            defer {
                Task { @MainActor in
                    self?.downloadTasks.removeValue(forKey: urlString)
                }
            }
            
            guard let url = URL(string: urlString) else {
                throw HybridImageCacheError.invalidURL
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw HybridImageCacheError.networkError
            }
            
            return data
        }
        
        downloadTasks[urlString] = downloadTask
        
        do {
            let data = try await downloadTask.value
            return await createAndCacheImage(from: data, urlString: urlString, cacheKey: cacheKey)
        } catch {
            print("Failed to download image: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func createAndCacheImage(from data: Data, urlString: String, cacheKey: NSString) async -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        
        // Store in memory cache immediately
        let cachedData = CachedImageData(image: image, data: data)
        let cost = data.count
        memoryCache.setObject(cachedData, forKey: cacheKey, cost: cost)
        
        // Store in persistent cache in background (non-blocking)
        Task.detached {
            await self.databaseActor.cacheImage(data: data, for: urlString)
        }
        
        return image
    }
}

// MARK: - Background Database Actor
private actor DatabaseActor {
    private var modelContext: ModelContext?
    private let maxCacheSize: Int = 200 * 1024 * 1024 // 200MB
    
    func configure(with modelContainer: ModelContainer) {
        // Create a new ModelContext for this actor's background queue
        self.modelContext = ModelContext(modelContainer)
        
        // Clean up expired images on startup
        Task {
            await cleanupExpiredImages()
        }
    }
    
    func getCachedImage(for urlString: String) async -> Data? {
        guard let modelContext = modelContext else { return nil }
        
        do {
            let predicate = #Predicate<CachedImage> { image in
                image.urlString == urlString
            }
            
            let descriptor = FetchDescriptor<CachedImage>(predicate: predicate)
            let cachedImages = try modelContext.fetch(descriptor)
            
            guard let cachedImage = cachedImages.first else {
                return nil
            }
            
            // Check if expired
            if cachedImage.isExpired {
                modelContext.delete(cachedImage)
                try modelContext.save()
                return nil
            }
            
            return cachedImage.imageData
            
        } catch {
            print("Failed to fetch cached image: \(error.localizedDescription)")
            return nil
        }
    }
    
    func cacheImage(data: Data, for urlString: String) async {
        guard let modelContext = modelContext else { return }
        
        do {
            // Check if image already exists
            let predicate = #Predicate<CachedImage> { image in
                image.urlString == urlString
            }
            
            let descriptor = FetchDescriptor<CachedImage>(predicate: predicate)
            let existingImages = try modelContext.fetch(descriptor)
            
            // Remove existing image if it exists
            if let existingImage = existingImages.first {
                modelContext.delete(existingImage)
            }
            
            // Create new cached image
            let cachedImage = CachedImage(
                urlString: urlString,
                imageData: data
            )
            
            modelContext.insert(cachedImage)
            try modelContext.save()
            
            // Cleanup cache if needed (periodically)
            if shouldCleanupCache() {
                await cleanupCacheIfNeeded()
            }
            
        } catch {
            print("Failed to cache image: \(error.localizedDescription)")
        }
    }
    
    func clearAllCache() async {
        guard let modelContext = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<CachedImage>()
            let allImages = try modelContext.fetch(descriptor)
            
            for image in allImages {
                modelContext.delete(image)
            }
            
            try modelContext.save()
            
        } catch {
            print("Failed to clear cache: \(error.localizedDescription)")
        }
    }
    
    func getCacheStats() async -> (count: Int, totalSize: Int) {
        guard let modelContext = modelContext else { return (0, 0) }
        
        do {
            let descriptor = FetchDescriptor<CachedImage>()
            let allImages = try modelContext.fetch(descriptor)
            
            let totalSize = allImages.reduce(0) { total, image in
                total + image.sizeInBytes
            }
            
            return (allImages.count, totalSize)
            
        } catch {
            print("Failed to get cache stats: \(error.localizedDescription)")
            return (0, 0)
        }
    }
    
    // MARK: - Private Methods
    private func shouldCleanupCache() -> Bool {
        // Only cleanup every 30 cache operations to reduce overhead
        return Int.random(in: 1...30) == 1
    }
    
    private func cleanupExpiredImages() async {
        guard let modelContext = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<CachedImage>()
            let allImages = try modelContext.fetch(descriptor)
            
            let expiredImages = allImages.filter { $0.isExpired }
            
            for image in expiredImages {
                modelContext.delete(image)
            }
            
            if !expiredImages.isEmpty {
                try modelContext.save()
                print("Cleaned up \(expiredImages.count) expired images")
            }
            
        } catch {
            print("Failed to cleanup expired images: \(error.localizedDescription)")
        }
    }
    
    private func cleanupCacheIfNeeded() async {
        guard let modelContext = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<CachedImage>()
            let allImages = try modelContext.fetch(descriptor)
            
            let currentSize = allImages.reduce(0) { $0 + $1.sizeInBytes }
            
            guard currentSize > maxCacheSize else { return }
            
            // Sort by last access date (oldest first)
            let sortedImages = allImages.sorted { $0.lastAccessDate < $1.lastAccessDate }
            
            var totalSize = currentSize
            
            // Remove oldest images until we're under the limit
            for image in sortedImages {
                guard totalSize > maxCacheSize else { break }
                
                totalSize -= image.sizeInBytes
                modelContext.delete(image)
            }
            
            try modelContext.save()
            print("Cache cleanup: removed images, new size: \(totalSize) bytes")
            
        } catch {
            print("Failed to cleanup cache: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Types
// Note: CachedImageData is defined in UltraFastImageCache.swift

// MARK: - Error Types
enum HybridImageCacheError: Error, LocalizedError {
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