//
//  CLIMasterKeyring.swift
//  BlazeCLICore
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(Darwin) || canImport(Glibc)
@_silgen_name("flock")
private func posixFlock(_ fd: Int32, _ operation: Int32) -> Int32
#endif
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import BlazeDBCore

public enum CLIMasterStorageScope: String, Codable, CaseIterable, Sendable {
    case session
    case device
    case persistent
}

public struct CLIMasterDatabaseEntry: Codable, Sendable {
    public var dbID: String
    public var label: String?
    public var canonicalPath: String
    public var pathHash: String
    public var scope: CLIMasterStorageScope
    public var encryptedDBKey: String?
    public var keychainReference: String?
    public var createdAt: Date
    public var lastOpened: Date?
}

public struct CLIMasterKeyringPayload: Codable, Sendable {
    public var databases: [String: CLIMasterDatabaseEntry]

    public init(databases: [String: CLIMasterDatabaseEntry] = [:]) {
        self.databases = databases
    }
}

public struct CLIMasterKDFRecord: Codable, Sendable {
    public var algorithm: String
    public var saltBase64: String
    public var memoryCost: Int?
    public var timeCost: Int?
    public var parallelism: Int?
    public var keyLength: Int
    public var pbkdf2Iterations: Int?
}

public struct CLIMasterEnvelope: Codable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var entryCountHint: Int
    public var kdf: CLIMasterKDFRecord
    public var nonceBase64: String
    public var ciphertextBase64: String
    public var tagBase64: String
}

public struct CLIMasterKeyringStatus: Sendable {
    public var path: String
    public var exists: Bool
    public var securePermissions0600: Bool
    public var permissionsOctal: String?
    public var schemaVersion: Int?
    public var kdfAlgorithm: String?
    public var entryCountHint: Int?
}

public enum CLIMasterGuardrails {
    /// Explicit non-goals: keep BlazeDB a vault, never a credential scavenger.
    public static let forbiddenBehaviors: [String] = [
        "Scan source code to discover credentials",
        "Parse app files to extract hardcoded passwords",
        "Search shell history or arbitrary files for secrets",
        "Auto-collect credentials outside explicit user input",
    ]
}

public enum CLIMasterKeyringError: Error, LocalizedError {
    case alreadyInitialized(String)
    case notInitialized(String)
    case corruptEnvelope
    case unsupportedKDF(String)
    case invalidPassphrase
    case missingStoredSecret
    case entryNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyInitialized(let p):
            return "Master keyring already initialized at \(p)"
        case .notInitialized(let p):
            return "Master keyring not initialized at \(p)"
        case .corruptEnvelope:
            return "Master keyring file is corrupted or unreadable."
        case .unsupportedKDF(let algo):
            return "Unsupported key derivation algorithm: \(algo)"
        case .invalidPassphrase:
            return "Invalid master passphrase."
        case .missingStoredSecret:
            return "Entry exists but has no stored secret for its scope."
        case .entryNotFound(let key):
            return "No keyring entry found for \(key)."
        }
    }
}

private final class CLIMasterKeyringMutationLock: @unchecked Sendable {
    private let lock = NSLock()

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

public enum CLIMasterKeyringStore {
    private static let schemaVersion = 1
    private static let inProcessKeyringLock = CLIMasterKeyringMutationLock()

    public static func initialize(passphrase: String) throws -> CLIMasterKeyringStatus {
        try PasswordStrengthValidator.validate(passphrase, requirements: .recommended)
        return try withExclusiveKeyringMutationLock {
            let url = try CLIPaths.masterKeyringURL()
            if FileManager.default.fileExists(atPath: url.path) {
                throw CLIMasterKeyringError.alreadyInitialized(url.path)
            }

            let createdAt = Date()
            let payload = CLIMasterKeyringPayload()
            let payloadData = try jsonEncoder().encode(payload)

            let isTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            let kdf = CLIMasterKDFRecord(
                algorithm: "argon2id",
                saltBase64: Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString(),
                memoryCost: isTest ? 16_384 : 65_536,
                timeCost: isTest ? 2 : 3,
                parallelism: isTest ? 2 : 4,
                keyLength: 32,
                pbkdf2Iterations: nil
            )
            let key = try deriveMasterKey(passphrase: passphrase, kdf: kdf)
            let box = try AES.GCM.seal(payloadData, using: key)

            let envelope = CLIMasterEnvelope(
                schemaVersion: schemaVersion,
                createdAt: createdAt,
                updatedAt: createdAt,
                entryCountHint: 0,
                kdf: kdf,
                nonceBase64: Data(box.nonce).base64EncodedString(),
                ciphertextBase64: box.ciphertext.base64EncodedString(),
                tagBase64: box.tag.base64EncodedString()
            )

            let data = try jsonEncoder().encode(envelope)
            try data.write(to: url, options: .atomic)
            try lockDownPermissionsIfPossible(url: url)
            return try status()
        }
    }

    public static func status() throws -> CLIMasterKeyringStatus {
        let url = try CLIPaths.masterKeyringURL()
        let exists = FileManager.default.fileExists(atPath: url.path)
        guard exists else {
            return CLIMasterKeyringStatus(
                path: url.path,
                exists: false,
                securePermissions0600: false,
                permissionsOctal: nil,
                schemaVersion: nil,
                kdfAlgorithm: nil,
                entryCountHint: nil
            )
        }

        let perms = try posixPermString(url: url)
        let secure = perms == "0600"

        let envelope: CLIMasterEnvelope? = {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? jsonDecoder().decode(CLIMasterEnvelope.self, from: data)
        }()

        return CLIMasterKeyringStatus(
            path: url.path,
            exists: true,
            securePermissions0600: secure,
            permissionsOctal: perms,
            schemaVersion: envelope?.schemaVersion,
            kdfAlgorithm: envelope?.kdf.algorithm,
            entryCountHint: envelope?.entryCountHint
        )
    }

    public static func loadPayload(passphrase: String) throws -> CLIMasterKeyringPayload {
        try withExclusiveKeyringMutationLock {
            try loadPayloadUnlocked(passphrase: passphrase)
        }
    }

    public static func savePayload(passphrase: String, payload: CLIMasterKeyringPayload) throws -> CLIMasterKeyringStatus {
        try withExclusiveKeyringMutationLock {
            try savePayloadUnlocked(passphrase: passphrase, payload: payload)
        }
    }

    private static func loadPayloadUnlocked(passphrase: String) throws -> CLIMasterKeyringPayload {
        let url = try CLIPaths.masterKeyringURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIMasterKeyringError.notInitialized(url.path)
        }
        let data = try Data(contentsOf: url)
        let envelope = try jsonDecoder().decode(CLIMasterEnvelope.self, from: data)
        let key = try deriveMasterKey(passphrase: passphrase, kdf: envelope.kdf)

        guard
            let nonceData = Data(base64Encoded: envelope.nonceBase64),
            let ciphertext = Data(base64Encoded: envelope.ciphertextBase64),
            let tag = Data(base64Encoded: envelope.tagBase64),
            let nonce = try? AES.GCM.Nonce(data: nonceData),
            let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag),
            let clear = try? AES.GCM.open(box, using: key)
        else {
            throw CLIMasterKeyringError.invalidPassphrase
        }

        return try jsonDecoder().decode(CLIMasterKeyringPayload.self, from: clear)
    }

    private static func savePayloadUnlocked(passphrase: String, payload: CLIMasterKeyringPayload) throws -> CLIMasterKeyringStatus {
        let url = try CLIPaths.masterKeyringURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIMasterKeyringError.notInitialized(url.path)
        }

        let existing = try Data(contentsOf: url)
        let oldEnvelope = try jsonDecoder().decode(CLIMasterEnvelope.self, from: existing)
        let key = try deriveMasterKey(passphrase: passphrase, kdf: oldEnvelope.kdf)
        let payloadData = try jsonEncoder().encode(payload)
        let box = try AES.GCM.seal(payloadData, using: key)
        let now = Date()
        let envelope = CLIMasterEnvelope(
            schemaVersion: oldEnvelope.schemaVersion,
            createdAt: oldEnvelope.createdAt,
            updatedAt: now,
            entryCountHint: payload.databases.count,
            kdf: oldEnvelope.kdf,
            nonceBase64: Data(box.nonce).base64EncodedString(),
            ciphertextBase64: box.ciphertext.base64EncodedString(),
            tagBase64: box.tag.base64EncodedString()
        )
        let data = try jsonEncoder().encode(envelope)
        try data.write(to: url, options: .atomic)
        try lockDownPermissionsIfPossible(url: url)
        return try status()
    }

    public static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    public static func pathHash(forCanonicalPath canonicalPath: String) -> String {
        let digest = SHA256.hash(data: Data(canonicalPath.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    public static func databaseID(forCanonicalPath canonicalPath: String) -> String {
        "db_" + String(pathHash(forCanonicalPath: canonicalPath).prefix(16))
    }

    public static func listEntries(passphrase: String) throws -> [CLIMasterDatabaseEntry] {
        let payload = try loadPayload(passphrase: passphrase)
        return payload.databases.values.sorted { $0.lastOpened ?? $0.createdAt > $1.lastOpened ?? $1.createdAt }
    }

    public static func addEntry(
        passphrase: String,
        dbPath: String,
        dbSecret: String,
        scope: CLIMasterStorageScope,
        label: String?
    ) throws -> CLIMasterDatabaseEntry {
        let canonical = canonicalPath(dbPath)
        let hash = pathHash(forCanonicalPath: canonical)
        let now = Date()

        switch scope {
        case .session:
            CLIMasterSession.setSessionSecret(pathHash: hash, secret: dbSecret)
            return CLIMasterDatabaseEntry(
                dbID: databaseID(forCanonicalPath: canonical),
                label: label,
                canonicalPath: canonical,
                pathHash: hash,
                scope: .session,
                encryptedDBKey: nil,
                keychainReference: nil,
                createdAt: now,
                lastOpened: now
            )
        case .device, .persistent:
            return try withExclusiveKeyringMutationLock {
                var payload = try loadPayloadUnlocked(passphrase: passphrase)
                var entry = payload.databases[hash] ?? CLIMasterDatabaseEntry(
                    dbID: databaseID(forCanonicalPath: canonical),
                    label: label,
                    canonicalPath: canonical,
                    pathHash: hash,
                    scope: scope,
                    encryptedDBKey: nil,
                    keychainReference: nil,
                    createdAt: now,
                    lastOpened: nil
                )
                entry.label = label ?? entry.label
                entry.scope = scope
                entry.lastOpened = now

                if scope == .device {
                    let ref = try CLIMasterDeviceVault.store(secret: dbSecret, account: hash)
                    entry.keychainReference = ref
                    entry.encryptedDBKey = nil
                } else {
                    entry.encryptedDBKey = Data(dbSecret.utf8).base64EncodedString()
                    entry.keychainReference = nil
                }
                payload.databases[hash] = entry
                _ = try savePayloadUnlocked(passphrase: passphrase, payload: payload)
                return entry
            }
        }
    }

    public static func removeEntry(passphrase: String, dbPathOrID: String) throws -> Bool {
        try withExclusiveKeyringMutationLock {
            var payload = try loadPayloadUnlocked(passphrase: passphrase)
            let canonical = canonicalPath(dbPathOrID)
            let hashByPath = pathHash(forCanonicalPath: canonical)

            let targetKey: String? = {
                if payload.databases[dbPathOrID] != nil { return dbPathOrID }
                if payload.databases[hashByPath] != nil { return hashByPath }
                return payload.databases.first { $0.value.dbID == dbPathOrID || $0.value.canonicalPath == canonical }?.key
            }()

            guard let key = targetKey, let entry = payload.databases.removeValue(forKey: key) else {
                return false
            }
            _ = try savePayloadUnlocked(passphrase: passphrase, payload: payload)
            if entry.scope == .device, let ref = entry.keychainReference {
                try? CLIMasterDeviceVault.remove(account: ref)
            }
            return true
        }
    }

    public static func resolveSecret(passphrase: String, dbPath: String) throws -> String? {
        let canonical = canonicalPath(dbPath)
        let hash = pathHash(forCanonicalPath: canonical)

        if let inSession = CLIMasterSession.sessionSecret(pathHash: hash) {
            return inSession
        }

        let status = try status()
        guard status.exists else {
            return nil
        }

        let payload = try loadPayload(passphrase: passphrase)
        guard let entry = payload.databases[hash] else { return nil }

        switch entry.scope {
        case .session:
            return CLIMasterSession.sessionSecret(pathHash: hash)
        case .device:
            guard let ref = entry.keychainReference else { throw CLIMasterKeyringError.missingStoredSecret }
            return try CLIMasterDeviceVault.fetch(account: ref)
        case .persistent:
            guard let encoded = entry.encryptedDBKey, let data = Data(base64Encoded: encoded), let value = String(data: data, encoding: .utf8) else {
                throw CLIMasterKeyringError.missingStoredSecret
            }
            return value
        }
    }

    private static func deriveMasterKey(passphrase: String, kdf: CLIMasterKDFRecord) throws -> SymmetricKey {
        guard let salt = Data(base64Encoded: kdf.saltBase64) else {
            throw CLIMasterKeyringError.corruptEnvelope
        }

        switch kdf.algorithm.lowercased() {
        case "argon2id":
            let params: Argon2KDF.Parameters
            if (kdf.memoryCost ?? 65_536) >= 131_072 || (kdf.timeCost ?? 3) >= 5 {
                params = .highSecurity
            } else if (kdf.memoryCost ?? 65_536) <= 16_384 || (kdf.timeCost ?? 3) <= 2 {
                params = .fast
            } else {
                params = .default
            }
            return try Argon2KDF.deriveKey(from: passphrase, salt: salt, parameters: params)
        case "pbkdf2":
            let iters = kdf.pbkdf2Iterations ?? 600_000
            let derived = derivePBKDF2SHA256(password: Data(passphrase.utf8), salt: salt, iterations: iters, keyLength: kdf.keyLength)
            return SymmetricKey(data: derived)
        default:
            throw CLIMasterKeyringError.unsupportedKDF(kdf.algorithm)
        }
    }

    private static func derivePBKDF2SHA256(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        var out = Data()
        let key = SymmetricKey(data: password)
        let blocks = (keyLength + 31) / 32
        for blockIndex in 1...blocks {
            var blockSalt = salt
            blockSalt.append(contentsOf: [
                UInt8((blockIndex >> 24) & 0xff),
                UInt8((blockIndex >> 16) & 0xff),
                UInt8((blockIndex >> 8) & 0xff),
                UInt8(blockIndex & 0xff),
            ])
            var u = Data(HMAC<SHA256>.authenticationCode(for: blockSalt, using: key))
            var t = u
            if iterations > 1 {
                for _ in 1..<iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    for i in 0..<t.count { t[i] ^= u[i] }
                }
            }
            out.append(t)
        }
        return out.prefix(keyLength)
    }

    private static func withExclusiveKeyringMutationLock<T>(_ body: () throws -> T) throws -> T {
        try inProcessKeyringLock.withLock {
            #if canImport(Darwin) || canImport(Glibc)
            let keyringURL = try CLIPaths.masterKeyringURL()
            let lockURL = keyringURL
                .deletingLastPathComponent()
                .appendingPathComponent("\(keyringURL.lastPathComponent).lock", isDirectory: false)
            let flags: Int32 = O_CREAT | O_RDWR
            let mode: mode_t = 0o600
            let fd = lockURL.path.withCString { path in
                #if canImport(Darwin)
                Darwin.open(path, flags, mode)
                #elseif canImport(Glibc)
                Glibc.open(path, flags, mode)
                #endif
            }
            guard fd >= 0 else {
                let err = errno
                throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
            }
            defer {
                #if canImport(Darwin)
                _ = Darwin.close(fd)
                #elseif canImport(Glibc)
                _ = Glibc.close(fd)
                #endif
            }

            try lockDownPermissionsIfPossible(url: lockURL)
            let lockResult = posixFlock(fd, LOCK_EX)
            guard lockResult == 0 else {
                let err = errno
                throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
            }
            defer {
                _ = posixFlock(fd, LOCK_UN)
            }
            #endif

            return try body()
        }
    }

    private static func lockDownPermissionsIfPossible(url: URL) throws {
        #if os(macOS) || os(Linux)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }

    private static func posixPermString(url: URL) throws -> String? {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let raw = attrs[.posixPermissions] as? NSNumber else { return nil }
        return String(format: "%04o", raw.intValue & 0o777)
    }

    private static func jsonEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    private static func jsonDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}
