//  KeyManager.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public enum KeySource {
    case secureEnclave(label: String)
    case password(String)
}

enum KeyManagerError: Error {
    case secureEnclaveUnavailable
    case keychainError
    case passwordTooWeak
}

public final class KeyManager {
    nonisolated(unsafe) private static var passwordKeyCache = [String: SymmetricKey]()
    private static let passwordKeyCacheLock = NSLock()
    private static let pbkdf2OverrideLock = NSLock()
    nonisolated(unsafe) private static var pbkdf2IterationsOverride: Int?
    internal static var pbkdf2Iterations: Int {
        pbkdf2OverrideLock.lock()
        let override = pbkdf2IterationsOverride
        pbkdf2OverrideLock.unlock()
        if let override, override > 0 {
            return override
        }
        if let override = ProcessInfo.processInfo.environment["BLAZEDB_PBKDF2_ITERATIONS"],
           let parsed = Int(override), parsed > 0 {
            return parsed
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return 100_000
        }
        return 600_000
    }

    /// Test-only hook for bounding PBKDF2 cost in non-crypto-focused suites.
    /// Set to `nil` to restore default behavior.
    internal static func setTestPBKDF2IterationsOverride(_ iterations: Int?) {
        pbkdf2OverrideLock.lock()
        defer { pbkdf2OverrideLock.unlock() }
        if let iterations, iterations > 0 {
            pbkdf2IterationsOverride = iterations
        } else {
            pbkdf2IterationsOverride = nil
        }
    }

    public static func getKey(from source: KeySource, createIfMissing: Bool = false) throws -> SymmetricKey {
        switch source {
        case .secureEnclave(let label):
            return try loadSecureEnclaveKey(label: label, createIfMissing: createIfMissing)

        case .password(let pass):
            // DEPRECATED: Legacy fallback using static salt. Only used by tests.
            // Production code must use getKey(from:salt:) with a per-database salt.
            let legacySalt = Data("AshPileSalt".utf8)
            return try getKey(from: pass, salt: legacySalt)
        }
    }

    public static func getKey(from password: String, salt: Data) throws -> SymmetricKey {
        let cacheKey = cacheKeyDigest(password: password, salt: salt)
        if let cached = cachedKey(for: cacheKey) {
            return cached
        }

        // SECURITY AUDIT: Enhanced password validation
        // Use recommended requirements by default (can be overridden)
        do {
            try PasswordStrengthValidator.validate(password, requirements: .recommended)
        } catch {
            // Provide detailed error message
            _ = PasswordStrengthValidator.analyze(password)
            throw KeyManagerError.passwordTooWeak
        }

        // Use CryptoKit's native PBKDF2 (SHA256)
        let passwordData = Data(password.utf8)
        let derivedKey = try deriveKeyPBKDF2(
            password: passwordData,
            salt: salt,
            iterations: pbkdf2Iterations,
            keyLength: 32
        )

        let symmetricKey = SymmetricKey(data: derivedKey)
        setCachedKey(symmetricKey, for: cacheKey)
        return symmetricKey
    }
    
    /// Native PBKDF2 implementation using CryptoKit
    internal static func deriveKeyPBKDF2(password: Data, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
        // CryptoKit's HKDF can be used, but for true PBKDF2 we need to implement it
        // For now, use a simple but secure key derivation
        var derivedKey = Data()
        
        for blockNum in 1...((keyLength + 31) / 32) {
            // PRF(password, salt || blockNum)
            var blockSalt = salt
            blockSalt.append(Data([UInt8(blockNum >> 24), UInt8(blockNum >> 16), UInt8(blockNum >> 8), UInt8(blockNum)]))
            
            var u = Data(HMAC<SHA256>.authenticationCode(for: blockSalt, using: SymmetricKey(data: password)))
            var result = u
            
            for _ in 1..<iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: SymmetricKey(data: password)))
                for i in 0..<result.count {
                    result[i] ^= u[i]
                }
            }
            
            derivedKey.append(result)
        }
        
        return derivedKey.prefix(keyLength)
    }

    #if canImport(Security) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
    private static func loadSecureEnclaveKey(label: String, createIfMissing: Bool) throws -> SymmetricKey {
        guard SecureEnclaveKeyManager.isAvailable() else {
            throw KeyManagerError.secureEnclaveUnavailable
        }

        let manager = try SecureEnclaveKeyManager(
            keyTag: label,
            requireBiometry: false,
            requireDeviceUnlock: true
        )

        if let existing = try manager.retrieveKey() {
            return existing
        }

        guard createIfMissing else {
            throw KeyManagerError.keychainError
        }

        let newKey = SymmetricKey(size: .bits256)
        try manager.storeKey(newKey)
        return newKey
    }
    #else
    private static func loadSecureEnclaveKey(label: String, createIfMissing: Bool) throws -> SymmetricKey {
        // Secure Enclave not available on this platform
        throw KeyManagerError.secureEnclaveUnavailable
    }
    #endif

    private static func deriveKeyFromPassword(_ password: String, salt: Data) throws -> SymmetricKey {
        guard password.count >= 8 else {
            throw KeyManagerError.passwordTooWeak
        }

        let passwordData = Data(password.utf8)
        let derivedKey = try deriveKeyPBKDF2(
            password: passwordData,
            salt: salt,
            iterations: pbkdf2Iterations,
            keyLength: 32
        )
        return SymmetricKey(data: derivedKey)
    }

    public static func clearKeyCache() {
        passwordKeyCacheLock.lock()
        defer { passwordKeyCacheLock.unlock() }
        passwordKeyCache.removeAll()
    }

    private static func cachedKey(for cacheKey: String) -> SymmetricKey? {
        passwordKeyCacheLock.lock()
        defer { passwordKeyCacheLock.unlock() }
        return passwordKeyCache[cacheKey]
    }

    private static func setCachedKey(_ key: SymmetricKey, for cacheKey: String) {
        passwordKeyCacheLock.lock()
        defer { passwordKeyCacheLock.unlock() }
        passwordKeyCache[cacheKey] = key
    }

    private static func cacheKeyDigest(password: String, salt: Data) -> String {
        var material = Data(password.utf8)
        material.append(salt)
        let digest = SHA256.hash(data: material)
        return Data(digest).base64EncodedString()
    }
}
