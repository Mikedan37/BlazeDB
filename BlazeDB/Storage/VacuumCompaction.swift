//
//  VacuumCompaction.swift
//  BlazeDB
//
//  VACUUM operation: Compact database by removing deleted/obsolete data
//
//  Similar to SQLite's VACUUM command - rewrites the database file
//  to reclaim wasted space from deleted records.
//
//  Created: 2025-11-13
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Storage health information
public struct StorageHealth {
    public let fileSizeBytes: Int
    public let activeDataBytes: Int
    public let wastedSpaceBytes: Int
    public let totalPages: Int
    public let activePages: Int
    public let obsoletePages: Int
    
    public var wastedPercentage: Double {
        guard fileSizeBytes > 0 else { return 0 }
        return Double(wastedSpaceBytes) / Double(fileSizeBytes)
    }
    
    public var needsVacuum: Bool {
        wastedPercentage > 0.5  // >50% wasted
    }
    
    public var description: String {
        """
        Storage Health:
          File size:       \(fileSizeBytes / 1_000_000) MB
          Active data:     \(activeDataBytes / 1_000_000) MB
          Wasted space:    \(wastedSpaceBytes / 1_000_000) MB (\(String(format: "%.1f", wastedPercentage * 100))%)
          Total pages:     \(totalPages)
          Active pages:    \(activePages)
          Obsolete pages:  \(obsoletePages)
          Needs VACUUM:    \(needsVacuum ? "⚠️ YES" : "✅ NO")
        """
    }
}

extension BlazeDBClient {
    
    // MARK: - Storage Health
    
    /// Get current storage health metrics
    public func getStorageHealth() throws -> StorageHealth {
        return try collection.queue.sync {
            // Get file size
            let fileSize = try collection.store.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let layout = try collection.loadLayoutForMutation()
            
            let activePages = Set(collection.indexMap.values.flatMap { $0 }).count
            let pageGCStats = collection.versionManager.pageGC.getStats()
            let persistedDeletedPages = layout.deletedPages.count
            
            // Account for both persisted deleted pages and MVCC free pages. These pools are
            // populated by different code paths, so health checks must consider both before
            // deciding whether auto-vacuum should run.
            let pageSize = 4096
            let totalPages = fileSize / pageSize
            let obsoletePages = persistedDeletedPages + pageGCStats.freePagesAvailable
            
            let activeDataBytes = activePages * pageSize
            let wastedBytes = obsoletePages * pageSize
            
            return StorageHealth(
                fileSizeBytes: fileSize,
                activeDataBytes: activeDataBytes,
                wastedSpaceBytes: wastedBytes,
                totalPages: totalPages,
                activePages: activePages,
                obsoletePages: obsoletePages
            )
        }
    }
    
    /// Print storage health to console
    public func printStorageHealth() throws {
        let health = try getStorageHealth()
        BlazeLogger.debug("\n" + health.description)
    }
    
    // MARK: - VACUUM Operation
    
    /// Compact the database by removing deleted/obsolete data (CRASH-SAFE)
    ///
    /// This operation:
    /// 1. Creates a new database file
    /// 2. Copies only active records
    /// 3. Persists and fsyncs new file
    /// 4. Atomically replaces old file with new
    /// 5. Recovers from crashes at any point
    ///
    /// CRASH SAFETY:
    /// - Old file kept as backup until new file confirmed
    /// - Atomic file replacement (POSIX rename)
    /// - Recovery on startup if crash during VACUUM
    /// - Write-ahead log for VACUUM operation
    ///
    /// WARNING: This is a blocking operation that can take seconds/minutes.
    /// Run during maintenance windows or show progress UI.
    ///
    /// - Returns: Bytes reclaimed
    @discardableResult
    public func vacuum() throws -> Int {
        // BLOCKER #2 FIX: Prevent concurrent operations during VACUUM
        vacuumLock.lock()
        guard !isVacuuming else {
            vacuumLock.unlock()
            throw BlazeDBError.databaseLocked(
                operation: "VACUUM",
                timeout: nil
            )
        }
        isVacuuming = true
        vacuumLock.unlock()
        
        defer {
            vacuumLock.lock()
            isVacuuming = false
            vacuumLock.unlock()
        }

        let activeCollection = collection
        var retiredCollection: DynamicCollection? = activeCollection

        let reclaimed = try activeCollection.queue.sync(flags: .barrier) {
            let collection = activeCollection
            BlazeLogger.info("🗑️ VACUUM: Starting CRASH-SAFE database compaction...")

            let startTime = Date()

            // Flush in-memory state to disk before measuring / copying.
            // Without this, the .blazedb file may not exist yet if records
            // are still only in the WAL or in-memory cache.
            // We're already inside queue.sync(.barrier), so call store/layout directly.
            try collection.store.synchronize()
            try collection.saveLayout()

            // CRASH SAFETY: Write VACUUM intent log
            let vacuumLogURL = collection.store.fileURL
                .deletingPathExtension()
                .appendingPathExtension("vacuum_in_progress")
            try Data().write(to: vacuumLogURL, options: .atomic)
            
            defer {
                BlazeAuthoritativeFileOps.removeItemIfExists(at: vacuumLogURL, context: "VACUUM(intent log)")
            }
            
            // Get current file size
            let oldSize = try collection.store.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            
            // Fetch all active records without re-entering collection.queue sync.
            // We are already executing inside collection.queue.sync(flags: .barrier).
            // Calling collection.fetchAll() here can trigger nested queue.sync and
            // crash with "dispatch_sync called on queue already owned by current thread".
            let activeRecords: [BlazeDataRecord]
            if collection.mvccEnabled {
                let tx = MVCCTransaction(versionManager: collection.versionManager, pageStore: collection.store)
                let mvccRecords = try tx.readAll()
                if mvccRecords.isEmpty && !collection.indexMap.isEmpty {
                    BlazeLogger.warn("⚠️ VACUUM: MVCC returned 0 records while indexMap has \(collection.indexMap.count) entries; falling back to no-sync legacy fetch.")
                    activeRecords = try collection._fetchAllNoSync()
                } else {
                    activeRecords = mvccRecords
                }
            } else {
                activeRecords = try collection._fetchAllNoSync()
            }
            BlazeLogger.info("   📊 Found \(activeRecords.count) active records")
            
            // Create temporary database
            let tempURL = collection.store.fileURL
                .deletingPathExtension()
                .appendingPathExtension("vacuum.blazedb")
            let tempMetaURL = collection.metaURL
                .deletingPathExtension()
                .appendingPathExtension("vacuum.meta")
            
            // Clean up any existing temp files
            BlazeAuthoritativeFileOps.removeItemIfExists(at: tempURL, context: "VACUUM(temp data)")
            BlazeAuthoritativeFileOps.removeItemIfExists(at: tempMetaURL, context: "VACUUM(temp meta)")
            
            // Create new store
            let tempStore = try PageStore(fileURL: tempURL, key: collection.encryptionKey)
            let tempCollection = try DynamicCollection(
                store: tempStore,
                metaURL: tempMetaURL,
                project: collection.project,
                encryptionKey: collection.encryptionKey
            )
            
            BlazeLogger.info("   ✅ Created temporary database")
            
            // Copy all active records (this rewrites them compactly)
            for (index, record) in activeRecords.enumerated() {
                _ = try tempCollection.insert(record)
                
                if index % 1000 == 0 {
                    BlazeLogger.debug("   📝 Copied \(index)/\(activeRecords.count) records...")
                }
            }
            
            // Persist and FSYNC the new database (CRASH SAFETY!)
            try tempCollection.persist()
            try tempCollection.close()
            
            // CRITICAL: Ensure all data is on disk before replacing files
            // This is the "barrier" - if we crash before this, old DB is still intact
            BlazeLogger.info("   ✅ Persisted compacted database (fsynced to disk)")
            
            // Get new file size
            let newSize = try tempURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let reclaimed = oldSize - newSize
            
            BlazeLogger.info("   ✅ Copied all records to compacted database")
            
            // CRASH SAFETY: Use atomic file replacement
            // Strategy: Keep old file as .backup until new file is confirmed
            
            // Step 1: Rename old files to .backup (atomic on POSIX)
            let dataBackupURL = collection.store.fileURL
                .deletingPathExtension()
                .appendingPathExtension("vacuum_backup.blazedb")
            let metaBackupURL = collection.metaURL
                .deletingPathExtension()
                .appendingPathExtension("vacuum_backup.meta")
            let originalDataURL = collection.store.fileURL
            let originalMetaURL = collection.metaURL
            let originalProject = collection.project
            let originalKey = collection.encryptionKey
            let originalPassword = collection.password
            let originalSalt = collection.kdfSalt
            
            // Clean up any old backups first
            BlazeAuthoritativeFileOps.removeItemIfExists(at: dataBackupURL, context: "VACUUM(stale data backup)")
            BlazeAuthoritativeFileOps.removeItemIfExists(at: metaBackupURL, context: "VACUUM(stale meta backup)")

            // Release the live file handles before swapping files in place.
            collection.store.close()
            
            // ATOMIC: Rename old → backup (if crash here, old file still exists)
            try FileManager.default.moveItem(at: originalDataURL, to: dataBackupURL)
            try FileManager.default.moveItem(at: originalMetaURL, to: metaBackupURL)
            
            BlazeLogger.info("   ✅ Old files backed up")
            
            // Step 2: Rename new → current (atomic on POSIX)
            // If crash here, we have backup to restore from
            do {
                // TEST HOOK: simulate rename failure for fault-injection tests
                if ProcessInfo.processInfo.environment["BLAZEDB_SIMULATE_VACUUM_RENAME_FAILURE"] != nil {
                    BlazeLogger.warn("   ⚠️ Simulating VACUUM rename failure (test hook)")
                    throw BlazeDBError.transactionFailed("Simulated VACUUM rename failure")
                }

                try FileManager.default.moveItem(at: tempURL, to: originalDataURL)
                try FileManager.default.moveItem(at: tempMetaURL, to: originalMetaURL)
                
                BlazeLogger.info("   ✅ New files activated")

                let reloadedStore = try PageStore(fileURL: originalDataURL, key: originalKey)
                self.collection = try DynamicCollection(
                    store: reloadedStore,
                    metaURL: originalMetaURL,
                    project: originalProject,
                    encryptionKey: originalKey,
                    password: originalPassword,
                    kdfSalt: originalSalt
                )
                
                // Step 3: Success! Create success marker
                let successMarkerURL = originalDataURL
                    .deletingPathExtension()
                    .appendingPathExtension("vacuum_success")
                try Data().write(to: successMarkerURL, options: .atomic)
                
                // Step 4: Safe to delete backups now
                BlazeAuthoritativeFileOps.removeItemIfExists(at: dataBackupURL, context: "VACUUM(post-success data backup)")
                BlazeAuthoritativeFileOps.removeItemIfExists(at: metaBackupURL, context: "VACUUM(post-success meta backup)")
                BlazeAuthoritativeFileOps.removeItemIfExists(at: successMarkerURL, context: "VACUUM(success marker)")
                
                BlazeLogger.info("   ✅ Backup files cleaned up")
                
            } catch {
                // ROLLBACK: Restore from backup if new file activation failed
                BlazeLogger.error("   ❌ VACUUM failed during file replacement, rolling back...")
                
                // Restore old files
                BlazeAuthoritativeFileOps.removeItemIfExists(at: originalDataURL, context: "VACUUM(rollback partial)")
                BlazeAuthoritativeFileOps.removeItemIfExists(at: originalMetaURL, context: "VACUUM(rollback partial meta)")
                do {
                    try FileManager.default.moveItem(at: dataBackupURL, to: originalDataURL)
                } catch {
                    BlazeLogger.error("VACUUM rollback: could not restore data from backup: \(error.localizedDescription)")
                    throw BlazeDBError.transactionFailed("VACUUM rollback failed", underlyingError: error)
                }
                do {
                    try FileManager.default.moveItem(at: metaBackupURL, to: originalMetaURL)
                } catch {
                    BlazeLogger.error("VACUUM rollback: could not restore meta from backup: \(error.localizedDescription)")
                    throw BlazeDBError.transactionFailed("VACUUM rollback failed", underlyingError: error)
                }
                
                // Clean up temp files
                BlazeAuthoritativeFileOps.removeItemIfExists(at: tempURL, context: "VACUUM(rollback temp)")
                BlazeAuthoritativeFileOps.removeItemIfExists(at: tempMetaURL, context: "VACUUM(rollback temp meta)")
                
                throw BlazeDBError.transactionFailed(
                    "VACUUM rollback: \(error.localizedDescription)",
                    underlyingError: error
                )
            }
            
            let duration = Date().timeIntervalSince(startTime)
            
            BlazeLogger.info("""
                ✅ VACUUM Complete:
                   Old size:     \(oldSize / 1_000_000) MB
                   New size:     \(newSize / 1_000_000) MB
                   Reclaimed:    \(reclaimed / 1_000_000) MB (\(String(format: "%.1f", Double(reclaimed) / Double(oldSize) * 100))%)
                   Records:      \(activeRecords.count)
                   Duration:     \(String(format: "%.2f", duration))s
                """)
            
            return reclaimed
        }

        retiredCollection = nil
        return reclaimed
    }
    
    /// Auto-vacuum if storage health is poor
    ///
    /// Checks storage health and runs VACUUM if >50% wasted space
    public func autoVacuumIfNeeded() throws {
        let health = try getStorageHealth()
        
        if health.needsVacuum {
            BlazeLogger.warn("⚠️ Storage is \(String(format: "%.1f", health.wastedPercentage * 100))% wasted, running VACUUM...")
            try vacuum()
        } else {
            BlazeLogger.info("✅ Storage is healthy (\(String(format: "%.1f", health.wastedPercentage * 100))% wasted)")
        }
    }
}

