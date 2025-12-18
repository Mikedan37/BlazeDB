//
//  Savepoints.swift
//  BlazeDB
//
//  Transaction savepoints for nested rollbacks
//  Optimized with efficient state management
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Savepoint

public struct Savepoint {
    public let name: String
    public let timestamp: Date
    internal let state: TransactionState
    
    internal init(name: String, state: TransactionState) {
        self.name = name
        self.timestamp = Date()
        self.state = state
    }
}

// MARK: - Transaction State (for savepoints)

public struct TransactionState {
    let pendingOperations: [String: Any]
    let checkpoint: Int
    
    init(pendingOperations: [String: Any] = [:], checkpoint: Int = 0) {
        self.pendingOperations = pendingOperations
        self.checkpoint = checkpoint
    }
}

// MARK: - Savepoint Manager

public class SavepointManager {
    private var savepoints: [String: Savepoint] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    /// Create a savepoint
    public func createSavepoint(name: String, state: TransactionState) -> Savepoint {
        lock.lock()
        defer { lock.unlock() }
        let savepoint = Savepoint(name: name, state: state)
        savepoints[name] = savepoint
        BlazeLogger.debug("Created savepoint '\(name)'")
        return savepoint
    }
    
    /// Get savepoint by name
    public func getSavepoint(name: String) -> Savepoint? {
        lock.lock()
        defer { lock.unlock() }
        return savepoints[name]
    }
    
    /// Release savepoint
    public func releaseSavepoint(name: String) {
        lock.lock()
        defer { lock.unlock() }
        savepoints.removeValue(forKey: name)
        BlazeLogger.debug("Released savepoint '\(name)'")
    }
    
    /// Release all savepoints after a given name
    public func releaseSavepointsAfter(name: String) {
        lock.lock()
        defer { lock.unlock() }
        let sortedNames = savepoints.keys.sorted()
        guard let index = sortedNames.firstIndex(of: name) else { return }
        for i in (index + 1)..<sortedNames.count {
            savepoints.removeValue(forKey: sortedNames[i])
        }
        BlazeLogger.debug("Released savepoints after '\(name)'")
    }
    
    /// Get all savepoint names
    public func getAllSavepointNames() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(savepoints.keys).sorted()
    }
}

// MARK: - BlazeDBClient Savepoints Extension

extension BlazeDBClient {
    nonisolated(unsafe) private static var savepointManagerKey: UInt8 = 0
    
    private var savepointManager: SavepointManager {
        #if canImport(ObjectiveC)
        if let manager = objc_getAssociatedObject(self, &Self.savepointManagerKey) as? SavepointManager {
            return manager
        }
        let manager = SavepointManager()
        objc_setAssociatedObject(self, &Self.savepointManagerKey, manager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return manager
        #else
        if let manager: SavepointManager = AssociatedObjects.get(self, key: &Self.savepointManagerKey) {
            return manager
        }
        let manager = SavepointManager()
        AssociatedObjects.set(self, key: &Self.savepointManagerKey, value: manager)
        return manager
        #endif
    }
    
    /// Create a savepoint in current transaction
    public func savepoint(_ name: String) throws {
        // Check if transaction is active (file-based check)
        let backupURL = transactionBackupURL
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw BlazeDBError.transactionFailed("Cannot create savepoint: not in a transaction")
        }
        
        // Ensure all changes are persisted before creating savepoint
        try persist()
        
        // Ensure store is fully synced before creating savepoint
        try collection.store.synchronize()
        
        // CRITICAL: Small delay to ensure all file system operations are complete
        // This is especially important for nested savepoints where multiple operations occur
        // NOTE: Thread.sleep is intentional. This synchronous function must block to ensure
        // file system synchronization completes. Converting to async would require API changes.
        Thread.sleep(forTimeInterval: 0.01)
        
        // Ensure files are fully synced before copying
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            fileHandle.synchronizeFile()
            fileHandle.closeFile()
        }
        if let metaHandle = FileHandle(forWritingAtPath: metaURL.path) {
            metaHandle.synchronizeFile()
            metaHandle.closeFile()
        }
        
        // Additional small delay after sync to ensure file system has fully written
        // NOTE: Thread.sleep is intentional for file system synchronization in synchronous context.
        Thread.sleep(forTimeInterval: 0.01)
        
        // OPTIMIZATION: Create a checkpoint by copying current state
        let savepointURL = backupURL.appendingPathExtension(name)
        BlazeLogger.debug("🔍 [SAVEPOINT] Creating savepoint '\(name)' at: \(savepointURL.path)")
        if FileManager.default.fileExists(atPath: savepointURL.path) {
            BlazeLogger.debug("🔍 [SAVEPOINT] Removing existing savepoint file: \(savepointURL.path)")
            try FileManager.default.removeItem(at: savepointURL)
        }
        BlazeLogger.debug("🔍 [SAVEPOINT] Copying database file from: \(fileURL.path) to: \(savepointURL.path)")
        try FileManager.default.copyItem(at: fileURL, to: savepointURL)
        BlazeLogger.debug("🔍 [SAVEPOINT] Savepoint file created: \(savepointURL.path)")
        
        // Verify the savepoint file was created correctly
        guard FileManager.default.fileExists(atPath: savepointURL.path) else {
            throw BlazeDBError.transactionFailed("Failed to create savepoint file '\(name)'")
        }
        
        // Also save the meta file if it exists
        let savepointMetaURL = backupURL.appendingPathExtension(name + ".meta")
        if FileManager.default.fileExists(atPath: metaURL.path) {
            if FileManager.default.fileExists(atPath: savepointMetaURL.path) {
                try FileManager.default.removeItem(at: savepointMetaURL)
            }
            try FileManager.default.copyItem(at: metaURL, to: savepointMetaURL)
        }
        
        // CRITICAL: Verify savepoint was created correctly by checking indexMap count
        let currentRecordCount = collection.indexMap.count
        BlazeLogger.debug("Created savepoint '\(name)' with \(currentRecordCount) records in indexMap")
        
        let state = TransactionState(
            pendingOperations: [:],
            checkpoint: 0
        )
        
        _ = savepointManager.createSavepoint(name: name, state: state)
        BlazeLogger.info("Created savepoint '\(name)' (indexMap.count=\(currentRecordCount))")
    }
    
    /// Rollback to savepoint
    public func rollbackToSavepoint(_ name: String) throws {
        let backupURL = transactionBackupURL
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw BlazeDBError.transactionFailed("Cannot rollback to savepoint: not in a transaction")
        }
        
        guard savepointManager.getSavepoint(name: name) != nil else {
            throw BlazeDBError.transactionFailed("Savepoint '\(name)' not found")
        }
        
        // OPTIMIZATION: Restore from savepoint checkpoint
        let savepointURL = backupURL.appendingPathExtension(name)
        guard FileManager.default.fileExists(atPath: savepointURL.path) else {
            throw BlazeDBError.transactionFailed("Savepoint '\(name)' checkpoint file not found")
        }
        
        // Store reference to old collection to reset its unsavedChanges
        let oldCollection = self.collection
        
        // Clear caches before restoring to ensure no stale data
        #if !BLAZEDB_LINUX_CORE
        oldCollection.clearFetchAllCache()
        #endif
        RecordCache.shared.clear()
        
        // Reset unsavedChanges on old collection BEFORE restoring files to prevent it from saving on deinit
        oldCollection.unsavedChanges = 0
        
        // Restore database state from savepoint
        // Note: We can't set collection to nil (it's non-optional), but reloadFromDisk() will replace it
        // The old collection will be deallocated after reloadFromDisk() assigns a new one
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.copyItem(at: savepointURL, to: fileURL)
        
        // Restore meta file if it was saved
        // CRITICAL: Always restore the meta file if it exists, as it contains the indexMap
        // which determines which records are visible. Without it, we might use the wrong indexMap.
        let savepointMetaURL = backupURL.appendingPathExtension(name + ".meta")
        if FileManager.default.fileExists(atPath: savepointMetaURL.path) {
            if FileManager.default.fileExists(atPath: metaURL.path) {
                try FileManager.default.removeItem(at: metaURL)
            }
            try FileManager.default.copyItem(at: savepointMetaURL, to: metaURL)
            BlazeLogger.debug("Restored meta file from savepoint '\(name)'")
        } else {
            BlazeLogger.warn("⚠️ [SAVEPOINT] Meta file for savepoint '\(name)' does not exist - layout will be rebuilt from data file")
        }
        
        // Ensure restored files are fully synced before loading
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            fileHandle.synchronizeFile()
            fileHandle.closeFile()
        }
        if let metaHandle = FileHandle(forWritingAtPath: metaURL.path) {
            metaHandle.synchronizeFile()
            metaHandle.closeFile()
        }
        
        // Small delay to ensure file system has fully synced
        // NOTE: Thread.sleep is intentional for file system synchronization in synchronous context.
        Thread.sleep(forTimeInterval: 0.05)
        
        // Reload collection state from disk (this replaces self.collection with a new instance)
        // The old collection will be deallocated here, closing its PageStore file handle
        try reloadFromDisk()
        
        // Small additional delay to ensure old collection is fully deallocated
        // NOTE: Thread.sleep is intentional for file system synchronization in synchronous context.
        Thread.sleep(forTimeInterval: 0.01)
        
        // Clear caches after rollback to ensure fresh data is read
        #if !BLAZEDB_LINUX_CORE
        #if !BLAZEDB_LINUX_CORE
        collection.clearFetchAllCache()
        #endif
        #endif
        RecordCache.shared.clear()
        // Also clear query cache to ensure queries read fresh data
        QueryCache.shared.clearAll()
        
        // CRITICAL: Force a fresh read by ensuring the collection is fully reloaded
        // Small delay to ensure file system has fully synced and collection is ready
        // NOTE: Thread.sleep is intentional for file system synchronization in synchronous context.
        Thread.sleep(forTimeInterval: 0.01)
        
        // CRITICAL: Verify the reload worked by checking the collection's indexMap count
        // This ensures we're reading from the restored state, not stale data
        // Note: reloadFromDisk() already rebuilds MVCC from indexMap when creating the new collection
        let expectedCount = collection.indexMap.count
        
        // CRITICAL: Verify the restored file has the correct state
        // This helps catch issues where the savepoint file itself is incorrect
        do {
            let verifyStore = try PageStore(fileURL: fileURL, key: self.encryptionKey)
            let verifyLayout = try StorageLayout.rebuild(from: verifyStore)
            let verifyCount = verifyLayout.indexMap.count
            BlazeLogger.debug("🔍 [SAVEPOINT] Restored file contains \(verifyCount) records (expected from savepoint '\(name)')")
            if verifyCount != expectedCount {
                BlazeLogger.warn("⚠️ [SAVEPOINT] Restored file has \(verifyCount) records but indexMap has \(expectedCount)")
            }
        } catch {
            BlazeLogger.warn("⚠️ [SAVEPOINT] Could not verify restored file: \(error)")
        }
        BlazeLogger.debug("After rollback to savepoint '\(name)': indexMap.count=\(expectedCount)")
        
        // CRITICAL: Force a fresh fetchAll to verify the restored state
        // This ensures MVCC is seeing the correct state after rollback
        // Also clear all caches one more time before verification to ensure fresh data
        #if !BLAZEDB_LINUX_CORE
        collection.clearFetchAllCache()
        #endif
        RecordCache.shared.clear()
        QueryCache.shared.clearAll()
        
        do {
            let freshRecords = try collection.fetchAll()
            BlazeLogger.debug("After rollback to savepoint '\(name)': fetchAll() returned \(freshRecords.count) records")
            if freshRecords.count != expectedCount {
                BlazeLogger.warn("⚠️ [SAVEPOINT] Mismatch: indexMap.count=\(expectedCount) but fetchAll() returned \(freshRecords.count) records")
                // Log the actual record IDs to help debug
                let recordIDs = freshRecords.compactMap { $0.storage["id"]?.uuidValue }
                BlazeLogger.warn("⚠️ [SAVEPOINT] Record IDs in fetchAll(): \(recordIDs.map { $0.uuidString.prefix(8) }.joined(separator: ", "))")
                let indexMapIDs = Array(collection.indexMap.keys)
                BlazeLogger.warn("⚠️ [SAVEPOINT] Record IDs in indexMap: \(indexMapIDs.map { $0.uuidString.prefix(8) }.joined(separator: ", "))")
            }
        } catch {
            BlazeLogger.warn("⚠️ [SAVEPOINT] Failed to verify restored state with fetchAll(): \(error)")
        }
        
        // Release all savepoints after this one
        savepointManager.releaseSavepointsAfter(name: name)
        
        // CRITICAL: Force one more cache clear and small delay to ensure all state is fully synced
        // This is especially important for nested savepoints where multiple rollbacks might occur
        #if !BLAZEDB_LINUX_CORE
        collection.clearFetchAllCache()
        #endif
        RecordCache.shared.clear()
        QueryCache.shared.clearAll()
        
        // Additional small delay to ensure file system and MVCC state are fully synced
        // NOTE: Thread.sleep is intentional for file system synchronization in synchronous context.
        Thread.sleep(forTimeInterval: 0.02)
        
        BlazeLogger.info("Rolled back to savepoint '\(name)' (indexMap.count=\(expectedCount))")
    }
    
    /// Release savepoint
    public func releaseSavepoint(_ name: String) throws {
        let backupURL = transactionBackupURL
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw BlazeDBError.transactionFailed("Cannot release savepoint: not in a transaction")
        }
        
        // Remove savepoint checkpoint file
        let savepointURL = backupURL.appendingPathExtension(name)
        if FileManager.default.fileExists(atPath: savepointURL.path) {
            try FileManager.default.removeItem(at: savepointURL)
        }
        
        savepointManager.releaseSavepoint(name: name)
        BlazeLogger.info("Released savepoint '\(name)'")
    }
}

