//
//  SecureEnclaveKeyManager.swift
//  BlazeDB
//
//  Enhanced Secure Enclave integration for hardware-protected key storage
//  Provides hardware-level key protection on iOS/macOS devices
//
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

#if canImport(Security) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
import Security

/// Enhanced Secure Enclave key manager
/// Stores encryption keys in Secure Enclave (hardware-protected)
public final class SecureEnclaveKeyManager {
    
    private let keyTag: String
    private let accessControl: SecAccessControl
    private let unlockProvider: KeyUnlockProvider
    
    /// Initialize with key tag and access control
    /// - Parameters:
    ///   - keyTag: Unique tag for this key
    ///   - requireBiometry: If true, requires biometric authentication
    ///   - requireDeviceUnlock: If true, requires device to be unlocked
    ///   - unlockProvider: Optional custom unlock provider (defaults to platform-appropriate provider)
    public init(
        keyTag: String,
        requireBiometry: Bool = true,
        requireDeviceUnlock: Bool = true,
        unlockProvider: KeyUnlockProvider? = nil
    ) throws {
        self.keyTag = keyTag
        // Use provided provider or default to platform-appropriate one
        self.unlockProvider = unlockProvider ?? DefaultKeyUnlockProvider()
        
        // Create access control
        var flags: SecAccessControlCreateFlags = []
        if requireBiometry {
            flags.insert(.biometryAny)  // Face ID or Touch ID
        }
        if requireDeviceUnlock {
            flags.insert(.privateKeyUsage)
        }
        
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            nil
        ) else {
            throw SecureEnclaveError.accessControlCreationFailed
        }
        
        self.accessControl = access
    }
    
    /// Store symmetric key in Secure Enclave
    /// Note: Secure Enclave only supports EC keys, so we wrap the symmetric key
    public func storeKey(_ key: SymmetricKey) throws {
        // Secure Enclave only supports EC keys, not symmetric keys directly
        // So we create an EC key pair and use it to encrypt the symmetric key
        
        // Generate EC key pair in Secure Enclave
        guard let tagData = keyTag.data(using: .utf8) else {
            throw SecureEnclaveError.keychainError(errSecParam)
        }
        
        let ecKeyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tagData,
                kSecAttrAccessControl as String: accessControl
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(ecKeyAttributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw SecureEnclaveError.keyCreationFailed(error.localizedDescription)
            }
            throw SecureEnclaveError.keyCreationFailed("Unknown error")
        }
        
        // Get public key for encrypting the symmetric key
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecureEnclaveError.publicKeyExtractionFailed
        }

        // Encrypt symmetric key with EC public key using ECIES
        let keyData = key.withUnsafeBytes { Data($0) }
        let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorVariableIVX963SHA256AESGCM

        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            throw SecureEnclaveError.encryptionFailed("ECIES algorithm not supported")
        }

        var encryptError: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(publicKey, algorithm, keyData as CFData, &encryptError) as Data? else {
            let errorDesc = encryptError?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw SecureEnclaveError.encryptionFailed(errorDesc)
        }

        // Store encrypted key in Keychain (protected by Secure Enclave EC key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(keyTag)_encrypted_key",
            kSecAttrService as String: "BlazeDB",
            kSecAttrAccessControl as String: accessControl,
            kSecValueData as String: encryptedData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item if present
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveError.keychainError(status)
        }
        
        BlazeLogger.info("Stored encryption key in Secure Enclave (wrapped)")
    }
    
    /// Retrieve symmetric key from Secure Enclave
    /// Decrypts the stored key using the EC private key (requires biometric auth)
    public func retrieveKey() throws -> SymmetricKey? {
        // Retrieve encrypted key from Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(keyTag)_encrypted_key",
            kSecAttrService as String: "BlazeDB",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let encryptedData = result as? Data else {
            return nil
        }

        // Retrieve the EC private key from Secure Enclave
        guard let tagData = keyTag.data(using: .utf8) else {
            throw SecureEnclaveError.keychainError(errSecParam)
        }

        let privateKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true
        ]

        var privateKeyRef: AnyObject?
        let keyStatus = SecItemCopyMatching(privateKeyQuery as CFDictionary, &privateKeyRef)

        guard keyStatus == errSecSuccess,
              let privateKey = privateKeyRef else {
            throw SecureEnclaveError.keychainError(keyStatus)
        }

        // Decrypt the symmetric key using the EC private key
        let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorVariableIVX963SHA256AESGCM
        // Keychain returns an untyped ref; verify CF type before downcasting to SecKey (no `as!`).
        guard CFGetTypeID(privateKey as CFTypeRef) == SecKeyGetTypeID() else {
            throw SecureEnclaveError.keychainError(errSecInvalidKeyRef)
        }
        let secKey = unsafeDowncast(privateKey as AnyObject, to: SecKey.self)

        var decryptError: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(secKey, algorithm, encryptedData as CFData, &decryptError) as Data? else {
            let errorDesc = decryptError?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw SecureEnclaveError.decryptionFailed(errorDesc)
        }

        // Reconstruct symmetric key
        guard decryptedData.count == 32 else {
            throw SecureEnclaveError.invalidKeyData
        }

        return SymmetricKey(data: decryptedData)
    }
    
    /// Check if Secure Enclave is available
    /// Uses the unlock provider to determine availability
    public static func isAvailable() -> Bool {
        #if canImport(Security)
        // On Apple platforms, check if Secure Enclave hardware is available
        // On other platforms, Secure Enclave is not available
        #if os(iOS) || os(macOS)
        // Use default provider to check availability
        let provider = DefaultKeyUnlockProvider()
        return provider.isAvailable()
        #else
        return false
        #endif
        #else
        return false
        #endif
    }
    
    /// Check if Secure Enclave is available using a specific unlock provider
    /// - Parameter unlockProvider: The unlock provider to use for availability check
    /// - Returns: true if Secure Enclave is available, false otherwise
    public static func isAvailable(using unlockProvider: KeyUnlockProvider) -> Bool {
        #if canImport(Security)
        #if os(iOS) || os(macOS)
        return unlockProvider.isAvailable()
        #else
        return false
        #endif
        #else
        return false
        #endif
    }
    
    /// Delete stored key
    public func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(keyTag)_encrypted_key",
            kSecAttrService as String: "BlazeDB"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureEnclaveError.keychainError(status)
        }
        
        BlazeLogger.info("Deleted key from Secure Enclave")
    }
}

/// Secure Enclave errors
public enum SecureEnclaveError: Error, LocalizedError {
    case accessControlCreationFailed
    case keyCreationFailed(String)
    case publicKeyExtractionFailed
    case keychainError(OSStatus)
    case invalidKeyData
    case encryptionFailed(String)
    case decryptionFailed(String)
    case notAvailable
    
    public var errorDescription: String? {
        switch self {
        case .accessControlCreationFailed:
            return "Failed to create access control for Secure Enclave"
        case .keyCreationFailed(let reason):
            return "Failed to create key in Secure Enclave: \(reason)"
        case .publicKeyExtractionFailed:
            return "Failed to extract public key from Secure Enclave key"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .invalidKeyData:
            return "Invalid key data retrieved from Secure Enclave"
        case .encryptionFailed(let reason):
            return "Failed to encrypt key with Secure Enclave: \(reason)"
        case .decryptionFailed(let reason):
            return "Failed to decrypt key with Secure Enclave: \(reason)"
        case .notAvailable:
            return "Secure Enclave is not available on this device"
        }
    }
}
#endif // canImport(Security) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))

