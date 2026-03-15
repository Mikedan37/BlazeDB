//  BlazeDBManager.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Manages multiple BlazeDB instances for fast DB switching.
/// Thread-safe for manager-owned mutable state via `stateLock`.
public final class BlazeDBManager {
    public private(set) var mountedDatabases: [String: DynamicCollection] = [:]
    private var currentKey: SymmetricKey?
    nonisolated(unsafe) public static let shared = BlazeDBManager()
    public private(set) var currentName: String?
    private var dbFileURLs: [String: URL] = [:]
    private var dbMetaURLs: [String: URL] = [:]
    private var dbPasswords: [String: String] = [:]  // Store passwords per database for reload/migration
    private let stateLock = NSRecursiveLock()
    
    /// Public accessor for the current database (for CLI/UI/testing)
    public var current: DynamicCollection? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentName.flatMap { mountedDatabases[$0] }
    }

    public init() {}

    private static func stablePathDigestHex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return Data(digest).map { String(format: "%02x", $0) }.joined()
    }

    private static func transactionLogURLs(for fileURL: URL) -> [URL] {
        let base = fileURL.deletingPathExtension().lastPathComponent
        let digest = stablePathDigestHex(fileURL.path)
        let namespaced = fileURL.deletingLastPathComponent().appendingPathComponent("txn_log-\(base)-\(digest).json")
        let legacy = fileURL.deletingLastPathComponent().appendingPathComponent("txn_log.json")
        return [namespaced, legacy]
    }

    private static func preferredTransactionLogURL(for fileURL: URL) -> URL {
        transactionLogURLs(for: fileURL).first!
    }

    private static func recoverTransactionLogIfPresent(into store: PageStore, fileURL: URL) throws {
        let fm = FileManager.default
        let candidates = transactionLogURLs(for: fileURL)
        let chosen = candidates.first(where: { fm.fileExists(atPath: $0.path) }) ?? preferredTransactionLogURL(for: fileURL)
        let log = TransactionLog(logFileURL: chosen)
        try log.recover(into: store, from: chosen)
        BlazeLogger.info("Recovered journal: \(chosen.lastPathComponent)")
    }

    /// Mount a DB from the given file path.
    @discardableResult
    public func mountDatabase(named name: String, fileURL: URL, password: String) throws -> DynamicCollection {
        stateLock.lock()
        defer { stateLock.unlock() }
        // CRITICAL: Validate database name to prevent path traversal attacks
        // Database names should not contain path traversal characters or null bytes
        guard !name.contains("../") && !name.contains("..\\") && !name.contains("\0") else {
            throw NSError(domain: "BlazeDBManager", code: 4001, userInfo: [
                NSLocalizedDescriptionKey: "Invalid database name: contains path traversal characters or null bytes"
            ])
        }
        guard !name.isEmpty && name.count <= 255 else {
            throw NSError(domain: "BlazeDBManager", code: 4002, userInfo: [
                NSLocalizedDescriptionKey: "Invalid database name: must be non-empty and <= 255 characters"
            ])
        }
        
        let kdfSalt = try Self.loadOrCreateKDFSalt(for: fileURL)
        let key = try Self.keyFromPassword(password, salt: kdfSalt)
        let metaURL = fileURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try PageStore(fileURL: fileURL, key: key)
        try Self.recoverTransactionLogIfPresent(into: store, fileURL: fileURL)
        
        // CRITICAL: Pass password to DynamicCollection so migration can access password-protected layouts
        let collection = try DynamicCollection(
            store: store,
            metaURL: metaURL,
            project: name,
            encryptionKey: key,
            password: password,
            kdfSalt: kdfSalt
        )
        mountedDatabases[name] = collection
        currentKey = key
        currentName = name
        dbFileURLs[name] = fileURL
        dbMetaURLs[name] = metaURL
        dbPasswords[name] = password  // Store password for reloadDatabase()
        return collection
    }

    /// Unmount a DB by name.
    public func unmountDatabase(named name: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        mountedDatabases.removeValue(forKey: name)
    }

    /// Get a mounted DB by name.
    public func database(named name: String) -> DynamicCollection? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return mountedDatabases[name]
    }

    /// List all currently mounted DB names.
    public var mountedNames: [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return Array(mountedDatabases.keys)
    }

    /// Public accessor for mounted database names (for CLI/UI/testing)
    public var mountedDatabaseNames: [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return Array(mountedDatabases.keys)
    }

    /// Set a new encryption key globally.
    public func setEncryptionKey(_ key: SymmetricKey) {
        stateLock.lock()
        defer { stateLock.unlock() }
        currentKey = key
    }

    /// Access the current active encryption key (if any).
    public func getCurrentKey() -> SymmetricKey? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentKey
    }

    /// Create a key from a user-provided password.
    private static func keyFromPassword(_ password: String, salt: Data) throws -> SymmetricKey {
        try KeyManager.getKey(from: password, salt: salt)
    }

    private static func kdfSaltURL(for fileURL: URL) -> URL {
        fileURL.deletingPathExtension().appendingPathExtension("salt")
    }

    private static func loadOrCreateKDFSalt(for fileURL: URL) throws -> Data {
        let saltURL = kdfSaltURL(for: fileURL)
        let fm = FileManager.default

        if fm.fileExists(atPath: saltURL.path) {
            let existing = try Data(contentsOf: saltURL)
            if !existing.isEmpty {
                return existing
            }
        }

        let salt = try SecureRandom.bytesStrict(count: 16)
        try salt.write(to: saltURL, options: .atomic)
        return salt
    }

    @discardableResult
    public func useDatabase(named name: String) throws -> DynamicCollection {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let db = mountedDatabases[name] else {
            throw NSError(domain: "BlazeDBManager", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Database not found"])
        }
        currentName = name
        return db
    }

    public var currentDatabase: DynamicCollection? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let name = currentName else { return nil }
        return mountedDatabases[name]
    }
    
    public func switchDatabase(to name: String) throws {
        _ = try useDatabase(named: name)
    }
    
    public var currentDatabaseName: String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentName
    }
    /// Synonym for useDatabase(named:) for consistency with test expectations.
    public func use(_ name: String) throws -> DynamicCollection {
        return try useDatabase(named: name)
    }
    
    public func reloadDatabase(named name: String) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let fileURL = dbFileURLs[name], let metaURL = dbMetaURLs[name] else {
            throw NSError(domain: "BlazeDBManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Database file or meta URL not found"])
        }
        // CRITICAL: Retrieve stored password for password-protected databases
        // Without password, migration will fail when trying to access encrypted layouts
        let password = dbPasswords[name]
        let kdfSalt = try Self.loadOrCreateKDFSalt(for: fileURL)
        let key = try Self.keyFromPassword(password ?? "", salt: kdfSalt)
        let store = try PageStore(fileURL: fileURL, key: key)
        try Self.recoverTransactionLogIfPresent(into: store, fileURL: fileURL)
        
        // CRITICAL: Pass password to DynamicCollection so migration can access password-protected layouts
        let collection = try DynamicCollection(
            store: store,
            metaURL: metaURL,
            project: name,
            encryptionKey: key,
            password: password,
            kdfSalt: kdfSalt
        )
        mountedDatabases[name] = collection
    }
    /// Unmounts all mounted databases, performing cleanup and resetting manager state.
    public func unmountAllDatabases() {
        stateLock.lock()
        defer { stateLock.unlock() }
        // Attempt to call close() on each mounted DynamicCollection if available
        for (_, _) in mountedDatabases {
            // If DynamicCollection has a close() method, call it
            // (Uncomment the following line if such method exists)
            // db.close()
        }
        mountedDatabases.removeAll()
        currentName = nil
        currentKey = nil
        dbFileURLs.removeAll()
        dbMetaURLs.removeAll()
        dbPasswords.removeAll()  // Clear stored passwords
    }
    
    /// Recover all transactions for all mounted databases.
    public func recoverAllTransactions() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        for (name, collection) in mountedDatabases {
            guard let fileURL = dbFileURLs[name] else {
                BlazeLogger.warn("Missing file URL for \(name); skipping recovery")
                continue
            }
            let candidates = Self.transactionLogURLs(for: fileURL)
            let fm = FileManager.default
            let chosen = candidates.first(where: { fm.fileExists(atPath: $0.path) }) ?? Self.preferredTransactionLogURL(for: fileURL)
            let log = TransactionLog(logFileURL: chosen)
            try log.recover(into: collection.store, from: chosen)
            BlazeLogger.info("Recovered journal for \(name): \(chosen.lastPathComponent)")
        }
    }
    
    /// Flush all mounted PageStores to disk.
    public func flushAll() {
        stateLock.lock()
        defer { stateLock.unlock() }
        for (_, collection) in mountedDatabases {
            if let flushable = collection.store as? Flushable {
                flushable.flush()
            }
            // No-op if not flushable
        }
        BlazeLogger.debug("Flushed all mounted DBs")
    }
}

private protocol Flushable {
    func flush()
}
