//
//  ImageCacheService.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ImageCacheService: ObservableObject {
    static let shared = ImageCacheService()
    
    // MARK: - Private Properties
    private let memoryCache = NSCache<NSString, NSData>()
    private let swiftDataCache = SwiftDataImageCacheService.shared
    
    // MARK: - Initialization
    private init() {
        // Configure memory cache
        memoryCache.countLimit = 100 // Max 100 images in memory
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB memory limit
    }
    
    // MARK: - Public Methods
    func cachedImage(for urlString: String) async -> NSData? {
        let cacheKey = NSString(string: cacheKeyForURL(urlString))
        
        // Check memory cache first
        if let cachedData = memoryCache.object(forKey: cacheKey) {
            return cachedData
        }
        
        // Check SwiftData persistent cache
        if let data = await swiftDataCache.getCachedImage(for: urlString) {
            let nsData = NSData(data: data)
            let cost = data.count
            memoryCache.setObject(nsData, forKey: cacheKey, cost: cost)
            return nsData
        }
        
        return nil
    }
    
    func cacheImage(data: Data, for urlString: String) async {
        let cacheKey = NSString(string: cacheKeyForURL(urlString))
        let nsData = NSData(data: data)
        
        // Store in memory cache
        let cost = data.count
        memoryCache.setObject(nsData, forKey: cacheKey, cost: cost)
        
        // Store in SwiftData persistent cache
        await swiftDataCache.cacheImage(data: data, for: urlString)
    }
    
    func loadImage(from urlString: String) async throws -> Data {
        // Check cache first
        if let cachedData = await cachedImage(for: urlString) {
            return Data(cachedData)
        }
        
        // Download from network
        guard let url = URL(string: urlString) else {
            throw ImageCacheError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ImageCacheError.networkError
        }
        
        // Cache the downloaded image
        await cacheImage(data: data, for: urlString)
        
        return data
    }
    
    func clearCache() async {
        // Clear memory cache
        memoryCache.removeAllObjects()
        
        // Clear SwiftData persistent cache
        await swiftDataCache.clearAllCache()
    }
    
    func getCacheStats() async -> (count: Int, totalSize: Int) {
        return await swiftDataCache.getCacheStats()
    }
    
    // MARK: - Private Methods
    private func cacheKeyForURL(_ urlString: String) -> String {
        return urlString.data(using: .utf8)?.base64EncodedString() ?? urlString
    }
}

// MARK: - Error Types
enum ImageCacheError: Error, LocalizedError {
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