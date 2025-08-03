//  BlazeDBManager.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.


import Foundation
import CryptoKit

/// Manages multiple BlazeDB instances for fast DB switching.
public final class BlazeDBManager {
public var mountedDatabases: [String: DynamicCollection] = [:]
    private var currentKey: SymmetricKey?
    public static let shared = BlazeDBManager()
    public var currentName: String?
    /// Public accessor for the current database (for CLI/UI/testing)
    public var current: DynamicCollection? {
        return currentDatabase
    }

    
    public init() {}

    /// Mount a DB from the given file path.
    @discardableResult
    public func mountDatabase(named name: String, fileURL: URL, password: String) throws -> DynamicCollection {
        let key = Self.keyFromPassword(password)
        let metaURL = fileURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try PageStore(fileURL: fileURL)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: name, encryptionKey: key)
        mountedDatabases[name] = collection
        currentKey = key
        currentName = name
        return collection
    }

    /// Unmount a DB by name.
    public func unmountDatabase(named name: String) {
        mountedDatabases.removeValue(forKey: name)
    }

    /// Get a mounted DB by name.
    public func database(named name: String) -> DynamicCollection? {
        return mountedDatabases[name]
    }

    /// List all currently mounted DB names.
    public var mountedNames: [String] {
        return Array(mountedDatabases.keys)
    }

    /// Public accessor for mounted database names (for CLI/UI/testing)
    public var mountedDatabaseNames: [String] {
        return Array(mountedDatabases.keys)
    }

    /// Set a new encryption key globally.
    public func setEncryptionKey(_ key: SymmetricKey) {
        currentKey = key
    }

    /// Access the current active encryption key (if any).
    public func getCurrentKey() -> SymmetricKey? {
        return currentKey
    }

    /// Create a key from a user-provided password.
    private static func keyFromPassword(_ password: String) -> SymmetricKey {
        let hashed = SHA256.hash(data: password.data(using: .utf8)!)
        return SymmetricKey(data: hashed)
    }

    @discardableResult
    public func useDatabase(named name: String) throws -> DynamicCollection {
        guard let db = mountedDatabases[name] else {
            throw NSError(domain: "BlazeDBManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Database not found"])
        }
        currentName = name
        return db
    }

    public var currentDatabase: DynamicCollection? {
        guard let name = currentName else { return nil }
        return mountedDatabases[name]
    }
    
    public func switchDatabase(to name: String) throws {
        _ = try useDatabase(named: name)
    }
    
    public var currentDatabaseName: String? {
        return currentName
    }
    /// Synonym for useDatabase(named:) for consistency with test expectations.
    public func use(_ name: String) throws -> DynamicCollection {
        return try useDatabase(named: name)
    }
}
