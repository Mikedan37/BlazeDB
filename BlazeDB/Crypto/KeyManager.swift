//  Untitled.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.

import Foundation
import CryptoKit
internal import CryptoSwift
import LocalAuthentication

enum KeySource {
    case secureEnclave(label: String)
    case password(String)
}

enum KeyManagerError: Error {
    case secureEnclaveUnavailable
    case keychainError
    case passwordTooWeak
}

final class KeyManager {
    static func getKey(from source: KeySource) throws -> SymmetricKey {
        switch source {
        case .secureEnclave(let label):
            return try loadSecureEnclaveKey(label: label)

        case .password(let pass):
            return try deriveKeyFromPassword(pass)
        }
    }

    private static func loadSecureEnclaveKey(label: String) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: label,
            kSecAttrKeyType as String: kSecAttrKeyTypeAES,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data {
            return SymmetricKey(data: data)
        }

        // Key not found, generate new
        let keyData = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: label,
            kSecAttrKeyType as String: kSecAttrKeyTypeAES,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeyManagerError.keychainError
        }

        return SymmetricKey(data: keyData)
    }

    private static func deriveKeyFromPassword(_ password: String) throws -> SymmetricKey {
        guard password.count >= 8 else {
            throw KeyManagerError.passwordTooWeak
        }

        let salt = "blazedb🔥".data(using: .utf8)!
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

