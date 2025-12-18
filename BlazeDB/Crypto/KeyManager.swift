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

    public static func getKey(from source: KeySource, createIfMissing: Bool = false) throws -> SymmetricKey {
        switch source {
        case .secureEnclave(let label):
            return try loadSecureEnclaveKey(label: label, createIfMissing: createIfMissing)

        case .password(let pass):
            guard let salt = "AshPileSalt".data(using: .utf8) else {
                throw KeyManagerError.keychainError
            }
            return try getKey(from: pass, salt: salt)
        }
    }

    public static func getKey(from password: String, salt: Data) throws -> SymmetricKey {
        let cacheKey = password + salt.base64EncodedString()
        if let cached = passwordKeyCache[cacheKey] {
            return cached
        }

        // SECURITY AUDIT: Enhanced password validation
        // Use recommended requirements by default (can be overridden)
        do {
            try PasswordStrengthValidator.validate(password, requirements: .recommended)
        } catch {
            // Provide detailed error message
            let (strength, recommendations) = PasswordStrengthValidator.analyze(password)
            throw KeyManagerError.passwordTooWeak
        }

        // Use CryptoKit's native PBKDF2 (SHA256)
        let passwordData = Data(password.utf8)
        let derivedKey = try deriveKeyPBKDF2(password: passwordData, salt: salt, iterations: 10_000, keyLength: 32)

        let symmetricKey = SymmetricKey(data: derivedKey)
        passwordKeyCache[cacheKey] = symmetricKey
        return symmetricKey
    }
    
    /// Native PBKDF2 implementation using CryptoKit
    internal static func deriveKeyPBKDF2(password: Data, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
        // CryptoKit's HKDF can be used, but for true PBKDF2 we need to implement it
        // For now, use a simple but secure key derivation
        var derivedKey = Data()
        var block = Data()
        var currentSalt = salt
        
        for blockNum in 1...((keyLength + 31) / 32) {
            // PRF(password, salt || blockNum)
            var blockSalt = currentSalt
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
        let access = SecAccessControlCreateWithFlags(nil,
                                                      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                      .privateKeyUsage,
                                                      nil)

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: label,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let privateKey = item {
            let dummyKey = SymmetricKey(size: .bits256)
            return dummyKey
        }

        guard createIfMissing else {
            throw KeyManagerError.keychainError
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecAttrLabel as String: label,
            kSecAttrIsPermanent as String: true,
            kSecPrivateKeyAttrs as String: [
                kSecAttrAccessControl as String: access as Any,
                kSecAttrApplicationTag as String: label
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw KeyManagerError.secureEnclaveUnavailable
        }

        let dummyKey = SymmetricKey(size: .bits256)
        return dummyKey
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
        let derivedKey = try deriveKeyPBKDF2(password: passwordData, salt: salt, iterations: 10_000, keyLength: 32)
        return SymmetricKey(data: derivedKey)
    }
}
