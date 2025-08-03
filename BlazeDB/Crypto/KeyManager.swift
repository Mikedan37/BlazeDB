//  Untitled.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation
import CryptoKit
internal import CryptoSwift
import LocalAuthentication

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
    private static var passwordKeyCache = [String: SymmetricKey]()

    public static func getKey(from source: KeySource, createIfMissing: Bool = false) throws -> SymmetricKey {
        switch source {
        case .secureEnclave(let label):
            return try loadSecureEnclaveKey(label: label, createIfMissing: createIfMissing)

        case .password(let pass):
            let salt = "AshPileSalt".data(using: .utf8)! // or inject from caller
            return try getKey(from: pass, salt: salt)
        }
    }

    public static func getKey(from password: String, salt: Data) throws -> SymmetricKey {
        let cacheKey = password + salt.base64EncodedString()
        if let cached = passwordKeyCache[cacheKey] {
            return cached
        }

        guard password.count >= 8 else {
            throw KeyManagerError.passwordTooWeak
        }

        let key = try PKCS5.PBKDF2(
            password: Array(password.utf8),
            salt: Array(salt),
            iterations: 10_000,
            keyLength: 32,
            variant: HMAC.Variant.sha2(.sha256)
        ).calculate()

        let symmetricKey = SymmetricKey(data: Data(key))
        passwordKeyCache[cacheKey] = symmetricKey
        return symmetricKey
    }

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

    private static func deriveKeyFromPassword(_ password: String, salt: Data) throws -> SymmetricKey {
        guard password.count >= 8 else {
            throw KeyManagerError.passwordTooWeak
        }

        let key = try PKCS5.PBKDF2(
            password: Array(password.utf8),
            salt: Array(salt),
            iterations: 10_000,
            keyLength: 32,
            variant: HMAC.Variant.sha2(.sha256)
        ).calculate()

        return SymmetricKey(data: Data(key))
    }
}
