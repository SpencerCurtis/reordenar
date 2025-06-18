//
//  SwiftDataImageCacheService.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import Foundation
import SwiftData

@MainActor
class SwiftDataImageCacheService: ObservableObject {
    static let shared = SwiftDataImageCacheService()
    
    // MARK: - Properties
    private var modelContext: ModelContext?
    private let maxCacheSize: Int = 100 * 1024 * 1024 // 100MB
    
    // MARK: - Initialization
    private init() {}
    
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        
        // Clean up expired images on startup
        Task {
            await cleanupExpiredImages()
        }
    }
    
    // MARK: - Public Methods
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
            
            // Update last access date
            cachedImage.updateLastAccessDate()
            try modelContext.save()
            
            return cachedImage.imageData
            
        } catch {
            print("Failed to fetch cached image: \(error.localizedDescription)")
            return nil
        }
    }
    
    func cacheImage(data: Data, for urlString: String, contentType: String? = nil) async {
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
                imageData: data,
                contentType: contentType
            )
            
            modelContext.insert(cachedImage)
            try modelContext.save()
            
            // Clean up if cache is getting too large
            await cleanupCacheIfNeeded()
            
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
    
    func getCacheSize() async -> Int {
        guard let modelContext = modelContext else { return 0 }
        
        do {
            let descriptor = FetchDescriptor<CachedImage>()
            let allImages = try modelContext.fetch(descriptor)
            
            return allImages.reduce(0) { total, image in
                total + image.sizeInBytes
            }
            
        } catch {
            print("Failed to calculate cache size: \(error.localizedDescription)")
            return 0
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
        let currentSize = await getCacheSize()
        
        guard currentSize > maxCacheSize else { return }
        
        guard let modelContext = modelContext else { return }
        
        do {
            // Get all images sorted by last access date (oldest first)
            let descriptor = FetchDescriptor<CachedImage>(
                sortBy: [SortDescriptor(\.lastAccessDate, order: .forward)]
            )
            let allImages = try modelContext.fetch(descriptor)
            
            var totalSize = currentSize
            
            // Remove oldest images until we're under the limit
            for image in allImages {
                guard totalSize > maxCacheSize else { break }
                
                totalSize -= image.sizeInBytes
                modelContext.delete(image)
            }
            
            try modelContext.save()
            print("Cache cleanup: removed images to reduce size from \(currentSize) to \(totalSize) bytes")
            
        } catch {
            print("Failed to cleanup cache: \(error.localizedDescription)")
        }
    }
} 