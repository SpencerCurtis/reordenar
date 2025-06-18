//
//  KeychainService.swift
//  reordenar
//
//  Created by Spencer Curtis on 6/16/25.
//

import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()
    
    private let serviceName = "com.spencercurtis.reordenar"
    
    private init() {}
    
    enum KeychainError: Error {
        case noData
        case duplicateItem
        case invalidData
        case unexpectedError(OSStatus)
    }
    
    // MARK: - Save Token
    func save(key: String, data: String) throws {
        let data = data.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedError(status)
        }
    }
    
    // MARK: - Load Token
    func load(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.noData
            } else {
                throw KeychainError.unexpectedError(status)
            }
        }
        
        guard let data = dataTypeRef as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return string
    }
    
    // MARK: - Delete Token
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedError(status)
        }
    }
    
    // MARK: - Convenience methods for Spotify tokens
    func saveAccessToken(_ token: String) throws {
        try save(key: "spotify_access_token", data: token)
    }
    
    func loadAccessToken() throws -> String {
        try load(key: "spotify_access_token")
    }
    
    func saveRefreshToken(_ token: String) throws {
        try save(key: "spotify_refresh_token", data: token)
    }
    
    func loadRefreshToken() throws -> String {
        try load(key: "spotify_refresh_token")
    }
    
    func saveTokenExpirationDate(_ date: Date) throws {
        let timestamp = String(date.timeIntervalSince1970)
        try save(key: "spotify_token_expiration", data: timestamp)
    }
    
    func loadTokenExpirationDate() throws -> Date {
        let timestampString = try load(key: "spotify_token_expiration")
        guard let timestamp = Double(timestampString) else {
            throw KeychainError.invalidData
        }
        return Date(timeIntervalSince1970: timestamp)
    }
    
    func deleteAllTokens() throws {
        try? delete(key: "spotify_access_token")
        try? delete(key: "spotify_refresh_token")
        try? delete(key: "spotify_token_expiration")
        try? delete(key: "spotify_user_data")
    }
    
    // MARK: - Convenience methods for user data
    func saveUserData(_ userData: Data) throws {
        let userDataString = userData.base64EncodedString()
        try save(key: "spotify_user_data", data: userDataString)
    }
    
    func loadUserData() throws -> Data {
        let userDataString = try load(key: "spotify_user_data")
        guard let userData = Data(base64Encoded: userDataString) else {
            throw KeychainError.invalidData
        }
        return userData
    }
} 