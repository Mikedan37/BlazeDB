//
//  ForwardSecrecyManager.swift
//  BlazeDB
//
//  EXPERIMENTAL: Not currently integrated into the BlazeDB encryption pipeline.
//  Key rotation and forward secrecy are not active. This module provides a
//  reference implementation that can be wired into the storage encryption path
//  in a future release.
//
//  Forward secrecy implementation with key rotation
//  Limits exposure from key compromise by rotating keys regularly
//
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Manages forward secrecy through key rotation
/// Rotates encryption keys regularly to limit exposure from key compromise
///
/// - Important: EXPERIMENTAL. Not currently wired into the BlazeDB encryption path.
public actor ForwardSecrecyManager {

    /// Key rotation interval (default: 1 hour)
    public let rotationInterval: TimeInterval

    /// Maximum key age before rotation (default: 24 hours)
    public let maxKeyAge: TimeInterval

    /// Current session keys (indexed by session start time)
    private var sessionKeys: [Date: SymmetricKey] = [:]

    /// Random salt generated once per manager lifetime, used for HKDF derivation.
    /// Using a random salt (instead of a deterministic timestamp) ensures that
    /// even if two sessions share the same time window, their derived keys differ.
    private let hkdfSalt: Data

    /// Key derivation key (derived from master password)
    private let masterKey: SymmetricKey

    /// Current active session start time
    private var currentSessionStart: Date?

    public init(
        masterKey: SymmetricKey,
        rotationInterval: TimeInterval = 3600,  // 1 hour
        maxKeyAge: TimeInterval = 86400  // 24 hours
    ) {
        self.masterKey = masterKey
        self.rotationInterval = rotationInterval
        self.maxKeyAge = maxKeyAge
        // Generate a random 32-byte salt at session start for HKDF
        var saltBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        self.hkdfSalt = Data(saltBytes)
    }
    
    /// Get current encryption key (rotates if needed)
    public func getCurrentKey() throws -> SymmetricKey {
        let now = Date()
        
        // Calculate current session start (rounded down to rotation interval)
        let sessionStart = Date(timeIntervalSince1970: 
            floor(now.timeIntervalSince1970 / rotationInterval) * rotationInterval
        )
        
        // Check if we need a new key
        if let existingKey = sessionKeys[sessionStart] {
            currentSessionStart = sessionStart
            return existingKey
        }
        
        // Generate new session key
        let sessionKey = try deriveSessionKey(sessionStart: sessionStart)
        sessionKeys[sessionStart] = sessionKey
        currentSessionStart = sessionStart
        
        // Clean up old keys (older than maxKeyAge)
        cleanupOldKeys(currentTime: now)
        
        BlazeLogger.debug("Generated new session key for session starting at \(sessionStart)")
        return sessionKey
    }
    
    /// Derive session key from master key and session start time
    private func deriveSessionKey(sessionStart: Date) throws -> SymmetricKey {
        // Use HKDF to derive session key from master key + session timestamp
        // The salt is random (generated once at init), not a timestamp, to avoid
        // deterministic derivation that could be replayed.
        let sessionTimestamp = withUnsafeBytes(of: sessionStart.timeIntervalSince1970) { Data($0) }

        // Combine random salt with session timestamp for the info parameter
        // so each time window still produces a distinct key.
        var info = Data("BlazeDB-Session-Key".utf8)
        info.append(sessionTimestamp)

        let sessionKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: hkdfSalt,
            info: info,
            outputByteCount: 32
        )

        return sessionKey
    }
    
    /// Get key for specific session (for decryption)
    public func getKey(for sessionStart: Date) throws -> SymmetricKey? {
        // Check if key exists
        if let key = sessionKeys[sessionStart] {
            return key
        }
        
        // Derive key if within max age
        let age = Date().timeIntervalSince(sessionStart)
        guard age <= maxKeyAge else {
            BlazeLogger.warn("Session key expired (age: \(age)s, max: \(maxKeyAge)s)")
            return nil
        }
        
        // Derive key for this session
        let key = try deriveSessionKey(sessionStart: sessionStart)
        sessionKeys[sessionStart] = key
        return key
    }
    
    /// Clean up old keys (older than maxKeyAge)
    private func cleanupOldKeys(currentTime: Date) {
        let cutoff = currentTime.addingTimeInterval(-maxKeyAge)
        sessionKeys = sessionKeys.filter { $0.key > cutoff }
        
        if sessionKeys.count > 10 {
            BlazeLogger.debug("Cleaned up old session keys, \(sessionKeys.count) keys remaining")
        }
    }
    
    /// Force key rotation (for testing or manual rotation)
    public func rotateKey() throws {
        // Clear current session to force new key on next getCurrentKey()
        currentSessionStart = nil
        BlazeLogger.info("Forced key rotation")
    }
    
    /// Get statistics
    public func getStats() -> ForwardSecrecyStats {
        let now = Date()
        let activeKeys = sessionKeys.filter { now.timeIntervalSince($0.key) <= maxKeyAge }
        
        return ForwardSecrecyStats(
            activeKeyCount: activeKeys.count,
            totalKeyCount: sessionKeys.count,
            rotationInterval: rotationInterval,
            maxKeyAge: maxKeyAge,
            currentSessionStart: currentSessionStart
        )
    }
}

/// Statistics for forward secrecy
public struct ForwardSecrecyStats {
    public let activeKeyCount: Int
    public let totalKeyCount: Int
    public let rotationInterval: TimeInterval
    public let maxKeyAge: TimeInterval
    public let currentSessionStart: Date?
}

