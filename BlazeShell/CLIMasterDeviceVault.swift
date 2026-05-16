//
//  CLIMasterDeviceVault.swift
//  BlazeCLICore
//

import Foundation

#if canImport(Security) && os(macOS)
import Security
#endif

public enum CLIMasterDeviceVaultError: Error, LocalizedError {
    case unsupportedPlatform
    case notFound
    case keychainFailure(Int32)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Device scope is supported on macOS only."
        case .notFound:
            return "No device-scoped secret found."
        case .keychainFailure(let status):
            return "Keychain operation failed (status \(status))."
        }
    }
}

public enum CLIMasterDeviceVault {
    private static let service = "com.blazedb.cli.master.device"

    public static func store(secret: String, account: String) throws -> String {
        #if canImport(Security) && os(macOS)
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CLIMasterDeviceVaultError.keychainFailure(status)
        }
        return account
        #else
        throw CLIMasterDeviceVaultError.unsupportedPlatform
        #endif
    }

    public static func fetch(account: String) throws -> String {
        #if canImport(Security) && os(macOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw CLIMasterDeviceVaultError.notFound }
            throw CLIMasterDeviceVaultError.keychainFailure(status)
        }
        guard let data = out as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CLIMasterDeviceVaultError.keychainFailure(errSecDecode)
        }
        return value
        #else
        throw CLIMasterDeviceVaultError.unsupportedPlatform
        #endif
    }

    public static func remove(account: String) throws {
        #if canImport(Security) && os(macOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw CLIMasterDeviceVaultError.keychainFailure(status)
        }
        #else
        throw CLIMasterDeviceVaultError.unsupportedPlatform
        #endif
    }
}
