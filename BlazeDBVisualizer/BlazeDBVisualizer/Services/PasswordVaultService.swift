//
//  PasswordVaultService.swift
//  BlazeDBVisualizer
//
//  Secure password management using macOS Keychain + Face ID
//  ✅ Industry-standard security
//  ✅ Biometric unlock
//  ✅ Encrypted storage
//
//  Created by Michael Danylchuk on 11/13/25.
//

import Foundation
import Security
import LocalAuthentication

/// Secure password vault service using macOS Keychain
/// Supports Face ID/Touch ID for biometric unlock
final class PasswordVaultService {
    
    static let shared = PasswordVaultService()
    
    private init() {}
    
    // MARK: - Password Storage
    
    /// Save password for a database (stored securely in Keychain)
    /// - Parameters:
    ///   - password: The database password
    ///   - dbPath: The full path to the database file
    ///   - useBiometrics: If true, requires Face ID/Touch ID to access
    func savePassword(_ password: String, for dbPath: String, useBiometrics: Bool = true) throws {
        let service = "com.blazedb.visualizer"
        let account = dbPath
        
        guard let passwordData = password.data(using: .utf8) else {
            throw PasswordVaultError.encodingFailed
        }
        
        // Delete existing entry first
        try? deletePassword(for: dbPath)
        
        // Build query
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Add biometric protection if requested
        if useBiometrics {
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.biometryCurrentSet, .or, .devicePasscode],  // Allow Face ID OR device password
                nil
            )
            if let access = access {
                query[kSecAttrAccessControl as String] = access
            }
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw PasswordVaultError.keychainError(status)
        }
    }
    
    /// Retrieve password for a database
    /// Will trigger Face ID prompt if biometric protection is enabled
    func getPassword(for dbPath: String, reason: String = "Unlock database") throws -> String {
        let service = "com.blazedb.visualizer"
        let account = dbPath
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        // Set up biometric authentication
        let context = LAContext()
        context.localizedReason = reason
        query[kSecUseAuthenticationContext as String] = context
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            throw PasswordVaultError.keychainError(status)
        }
        
        guard let passwordData = result as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            throw PasswordVaultError.decodingFailed
        }
        
        return password
    }
    
    /// Delete stored password for a database
    func deletePassword(for dbPath: String) throws {
        let service = "com.blazedb.visualizer"
        let account = dbPath
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // Don't error if item doesn't exist
        if status != errSecSuccess && status != errSecItemNotFound {
            throw PasswordVaultError.keychainError(status)
        }
    }
    
    /// Check if password is stored for a database
    func hasStoredPassword(for dbPath: String) -> Bool {
        let service = "com.blazedb.visualizer"
        let account = dbPath
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Check if biometrics (Face ID/Touch ID) are available
    func isBiometricsAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Get biometric type available on this device
    func biometricType() -> String {
        let context = LAContext()
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return "None"
        }
        
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        @unknown default:
            return "Biometrics"
        }
    }
}

// MARK: - Errors

enum PasswordVaultError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case keychainError(OSStatus)
    case biometricsNotAvailable
    case userCancelled
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode password"
        case .decodingFailed:
            return "Failed to decode password"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .biometricsNotAvailable:
            return "Face ID/Touch ID not available on this device"
        case .userCancelled:
            return "User cancelled authentication"
        }
    }
}

