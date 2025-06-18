//
//  CachedImageModel.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import Foundation
import SwiftData

@Model
class CachedImage {
    @Attribute(.unique) var urlString: String
    var imageData: Data
    var cacheDate: Date
    var lastAccessDate: Date
    var contentType: String?
    
    init(urlString: String, imageData: Data, contentType: String? = nil) {
        self.urlString = urlString
        self.imageData = imageData
        self.contentType = contentType
        self.cacheDate = Date()
        self.lastAccessDate = Date()
    }
    
    // MARK: - Computed Properties
    var isExpired: Bool {
        let maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        return Date().timeIntervalSince(cacheDate) > maxAge
    }
    
    var sizeInBytes: Int {
        return imageData.count
    }
    
    // MARK: - Methods
    func updateLastAccessDate() {
        lastAccessDate = Date()
    }
} 