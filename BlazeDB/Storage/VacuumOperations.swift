//
//  VacuumOperations.swift
//  BlazeDB
//
//  Database compaction and space reclamation (VACUUM)
//  Based on design from GARBAGE_COLLECTION_NEEDED.md
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - VACUUM Statistics

public struct VacuumStats {
    public let pagesBefore: Int
    public let pagesAfter: Int
    public let pagesReclaimed: Int
    public let sizeBefore: Int64
    public let sizeAfter: Int64
    public let sizeReclaimed: Int64
    public let duration: TimeInterval
    public let timestamp: Date
    
    public var wastePercentage: Double {
        guard pagesBefore > 0 else { return 0 }
        return Double(pagesReclaimed) / Double(pagesBefore) * 100
    }
    
    public var description: String {
        """
        VACUUM Stats:
          Pages: \(pagesBefore) → \(pagesAfter) (reclaimed \(pagesReclaimed))
          Size: \(sizeBefore / 1024 / 1024) MB → \(sizeAfter / 1024 / 1024) MB (saved \(sizeReclaimed / 1024 / 1024) MB)
          Waste: \(String(format: "%.1f", wastePercentage))%
          Duration: \(String(format: "%.2f", duration))s
        """
    }
}

// MARK: - Storage Statistics

public struct StorageStats {
    public let totalPages: Int
    public let usedPages: Int
    public let emptyPages: Int
    public let fileSize: Int64
    public let wastedSpace: Int64
    
    public var wastePercentage: Double {
        guard fileSize > 0 else { return 0 }
        return Double(wastedSpace) / Double(fileSize) * 100
    }
    
    public var description: String {
        """
        Storage Stats:
          Total pages: \(totalPages)
          Used pages: \(usedPages)
          Empty pages: \(emptyPages)
          File size: \(fileSize / 1024 / 1024) MB
          Wasted: \(wastedSpace / 1024 / 1024) MB (\(String(format: "%.1f", wastePercentage))%)
        """
    }
}

// MARK: - BlazeDBClient VACUUM Extension

extension BlazeDBClient {
    private func loadVacuumLayout() throws -> StorageLayout {
        try StorageLayout.loadSecure(
            from: metaURL,
            signingKey: encryptionKey,
            password: collection.password,
            salt: collection.kdfSalt,
            allowUnsignedLayoutFallback: true
        )
    }
    
    // MARK: - VACUUM Operations
    
    /// Compact the database and reclaim deleted space
    ///
    /// Rewrites the database file, removing deleted pages and compacting data.
    /// This operation can take time for large databases.
    ///
    /// - Returns: Statistics about the VACUUM operation
    /// - Throws: BlazeDBError if VACUUM fails
    ///
    /// ## Example
    /// ```swift
    /// // After deleting many records
    /// let stats = try await db.vacuum()
    /// print(stats.description)
    /// // Output: Reclaimed 9000 pages, saved 36 MB
    /// ```
    ///
    /// ## When to Use
    /// - After deleting many records
    /// - Monthly maintenance
    /// - Before creating backups
    /// - When storage space is limited
    public func vacuum() async throws -> VacuumStats {
        BlazeLogger.info("🧹 Starting VACUUM operation for '\(name)'...")
        let startTime = Date()
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    // Use queue barrier to ensure exclusive access during vacuum
                    // (No separate writeLock needed - queue handles synchronization)
                    
                    // Get storage stats before
                    let statsBefore = try self._getStorageStatsSync()
                    
                    // Flush all pending changes, then copy the committed WAL into the
                    // main file. Since legacy commits stay in the WAL until checkpoint,
                    // a later crash must still find those pages in the live file.
                    try self.persist()
                    try self.collection.store.checkpoint()
                    
                    let attrsOld = try FileManager.default.attributesOfItem(atPath: self.fileURL.path)
                    let sizeOld = attrsOld[.size] as? Int64 ?? 0
                    
                    // The temp file's extension has to stay `.blazedb`. Naming it
                    // `name.blazedb.vacuum-…` makes PageStore strip that suffix and
                    // open `name.blazedb.wal` — the live log — then clear it on replay.
                    let tempURL = self.fileURL
                        .deletingPathExtension()
                        .appendingPathExtension("vacuum-\(UUID().uuidString).blazedb")
                    let tempMetaURL = self.metaURL
                        .deletingPathExtension()
                        .appendingPathExtension("vacuum-\(UUID().uuidString).meta")
                    let tempWALURL = tempURL.deletingPathExtension().appendingPathExtension("wal")
                    
                    defer {
                        BlazeAuthoritativeFileOps.removeItemIfExists(at: tempURL, context: "VacuumOperations(defer temp)")
                        BlazeAuthoritativeFileOps.removeItemIfExists(at: tempMetaURL, context: "VacuumOperations(defer temp meta)")
                        BlazeAuthoritativeFileOps.removeItemIfExists(at: tempWALURL, context: "VacuumOperations(defer temp wal)")
                    }
                    
                    BlazeLogger.debug("Creating compacted database at \(tempURL.path)")
                    
                    // Create new PageStore for compacted file
                    let compactedStore = try PageStore(fileURL: tempURL, key: self.encryptionKey)
                    
                    // Fetch all records
                    let allRecords = try self.fetchAll()
                    
                    BlazeLogger.debug("Compacting \(allRecords.count) records...")
                    
                    // Write all records to compacted file (sequential, no gaps)
                    var newIndexMap: [UUID: [Int]] = [:]
                    var newPageIndex = 0
                    
                    for record in allRecords {
                        guard let id = record.storage["id"]?.uuidValue else { continue }
                        
                        // Encode record using canonical BlazeBinary format
                        let encoded = try BlazeBinaryEncoder.encode(record)
                        
                        // Write to new file
                        try compactedStore.writePage(index: newPageIndex, plaintext: encoded)
                        
                        newIndexMap[id] = [newPageIndex]  // Store as [Int] array for consistency
                        newPageIndex += 1
                    }
                    
                    BlazeLogger.debug("Wrote \(newPageIndex) compacted pages")
                    
                    // Catalog stays on the temp meta until the data file is replaced.
                    // Publishing it onto the live meta first makes a crash read old
                    // pages through the compacted index.
                    var layout = try self.loadVacuumLayout()
                    layout.indexMap = newIndexMap
                    layout.nextPageIndex = newPageIndex
                    // Compaction rewrites live rows at low page indexes. The previous
                    // freelist still names those indexes, so the next insert would
                    // overwrite a record vacuum just kept.
                    layout.deletedPages = []
                    try layout.saveSecure(to: tempMetaURL, signingKey: self.encryptionKey)
                    
                    // Close temporary compacted store before swapping files.
                    compactedStore.close()
                    
                    let attrsNew = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                    let sizeNew = attrsNew[.size] as? Int64 ?? 0
                    
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["BLAZEDB_CRASH_ASYNC_VACUUM_BEFORE_SWAP"] == "1" {
                        self.collection.store.simulateCrashForTests()
                        throw BlazeDBError.transactionFailed("Simulated crash before async vacuum file swap")
                    }
                    #endif
                    
                    try self.replaceLiveFilesWithCompactedDatabase(tempDataURL: tempURL, tempMetaURL: tempMetaURL)
                    
                    let duration = Date().timeIntervalSince(startTime)
                    
                    let stats = VacuumStats(
                        pagesBefore: statsBefore.totalPages,
                        pagesAfter: newPageIndex,
                        pagesReclaimed: statsBefore.totalPages - newPageIndex,
                        sizeBefore: sizeOld,
                        sizeAfter: sizeNew,
                        sizeReclaimed: sizeOld - sizeNew,
                        duration: duration,
                        timestamp: Date()
                    )
                    
                    BlazeLogger.info("✅ VACUUM complete: \(stats.description)")
                    
                    continuation.resume(returning: stats)
                    
                } catch {
                    BlazeLogger.error("❌ VACUUM failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Swap in a finished compact database. The live catalog is not replaced
    /// until the compacted data file is in its place, and `vacuum_in_progress`
    /// plus the backups let open restore the previous files if the process dies
    /// between the two renames.
    private func replaceLiveFilesWithCompactedDatabase(tempDataURL: URL, tempMetaURL: URL) throws {
        let originalDataURL = fileURL
        let originalMetaURL = metaURL
        let baseURL = originalDataURL.deletingPathExtension()
        let vacuumLogURL = baseURL.appendingPathExtension("vacuum_in_progress")
        let dataBackupURL = baseURL.appendingPathExtension("vacuum_backup.blazedb")
        let metaBackupURL = baseURL.appendingPathExtension("vacuum_backup.meta")
        let successMarkerURL = baseURL.appendingPathExtension("vacuum_success")

        BlazeAuthoritativeFileOps.removeItemIfExists(at: dataBackupURL, context: "VacuumOperations(stale data backup)")
        BlazeAuthoritativeFileOps.removeItemIfExists(at: metaBackupURL, context: "VacuumOperations(stale meta backup)")
        try Data().write(to: vacuumLogURL, options: .atomic)

        let preservedProject = self.project
        let key = encryptionKey
        let password = collection.password
        let salt = collection.kdfSalt

        // Release the live flock before renaming the file it holds.
        try collection.close()

        do {
            if FileManager.default.fileExists(atPath: originalDataURL.path) {
                try FileManager.default.moveItem(at: originalDataURL, to: dataBackupURL)
            }
            if FileManager.default.fileExists(atPath: originalMetaURL.path) {
                try FileManager.default.moveItem(at: originalMetaURL, to: metaBackupURL)
            }
            try FileManager.default.moveItem(at: tempDataURL, to: originalDataURL)
            try FileManager.default.moveItem(at: tempMetaURL, to: originalMetaURL)

            let newStore = try PageStore(fileURL: originalDataURL, key: key)
            collection = try DynamicCollection(
                store: newStore,
                metaURL: originalMetaURL,
                project: preservedProject,
                encryptionKey: key,
                password: password,
                kdfSalt: salt
            )

            try Data().write(to: successMarkerURL, options: .atomic)
            BlazeAuthoritativeFileOps.removeItemIfExists(at: dataBackupURL, context: "VacuumOperations(post-success data backup)")
            BlazeAuthoritativeFileOps.removeItemIfExists(at: metaBackupURL, context: "VacuumOperations(post-success meta backup)")
            BlazeAuthoritativeFileOps.removeItemIfExists(at: successMarkerURL, context: "VacuumOperations(success marker)")
            BlazeAuthoritativeFileOps.removeItemIfExists(at: vacuumLogURL, context: "VacuumOperations(intent)")
        } catch {
            BlazeLogger.error("Async VACUUM file swap failed, restoring previous files: \(error)")
            if FileManager.default.fileExists(atPath: dataBackupURL.path) {
                BlazeAuthoritativeFileOps.removeItemIfExists(at: originalDataURL, context: "VacuumOperations(rollback partial data)")
                try FileManager.default.moveItem(at: dataBackupURL, to: originalDataURL)
            }
            if FileManager.default.fileExists(atPath: metaBackupURL.path) {
                BlazeAuthoritativeFileOps.removeItemIfExists(at: originalMetaURL, context: "VacuumOperations(rollback partial meta)")
                try FileManager.default.moveItem(at: metaBackupURL, to: originalMetaURL)
            }
            let restored = try PageStore(fileURL: originalDataURL, key: key)
            collection = try DynamicCollection(
                store: restored,
                metaURL: originalMetaURL,
                project: preservedProject,
                encryptionKey: key,
                password: password,
                kdfSalt: salt
            )
            BlazeAuthoritativeFileOps.removeItemIfExists(at: vacuumLogURL, context: "VacuumOperations(rollback intent)")
            throw error
        }
    }
    
    /// Get current storage statistics
    ///
    /// Shows disk usage, wasted space, and page counts.
    ///
    /// - Returns: Storage statistics
    ///
    /// ## Example
    /// ```swift
    /// let stats = try await db.getStorageStats()
    /// if stats.wastePercentage > 20 {
    ///     print("Consider running VACUUM")
    ///     try await db.vacuum()
    /// }
    /// ```
    public func getStorageStats() async throws -> StorageStats {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let stats = try self._getStorageStatsSync()
                    continuation.resume(returning: stats)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Internal sync version of getStorageStats
    private func _getStorageStatsSync() throws -> StorageStats {
        let layout = try loadVacuumLayout()
        
        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        // Calculate page counts
        let totalPages = layout.nextPageIndex
        let usedPages = layout.indexMap.count
        let emptyPages = totalPages - usedPages
        
        // Estimate wasted space (empty pages × page size)
        let pageSize: Int64 = 4096
        let wastedSpace = Int64(emptyPages) * pageSize
        
        return StorageStats(
            totalPages: totalPages,
            usedPages: usedPages,
            emptyPages: emptyPages,
            fileSize: fileSize,
            wastedSpace: wastedSpace
        )
    }
    
    // MARK: - Auto-VACUUM
    
    nonisolated(unsafe) private static var autoVacuumTimers: [String: Timer] = [:]
    private static let timerLock = NSLock()
    
    /// Enable automatic VACUUM when waste exceeds threshold
    ///
    /// Periodically checks storage stats and runs VACUUM if waste exceeds threshold.
    ///
    /// - Parameters:
    ///   - wasteThreshold: Minimum waste percentage to trigger (default 20%)
    ///   - checkInterval: Seconds between checks (default 300 = 5 minutes)
    ///
    /// ## Example
    /// ```swift
    /// // Auto-vacuum when 20% wasted
    /// db.enableAutoVacuum(wasteThreshold: 0.20, checkInterval: 300)
    ///
    /// // Runs in background, no manual intervention needed!
    /// ```
    public func enableAutoVacuum(wasteThreshold: Double = 0.20, checkInterval: TimeInterval = 300) {
        let key = "\(name)-\(fileURL.path)"
        
        BlazeLogger.info("🤖 Enabling auto-VACUUM (threshold: \(Int(wasteThreshold * 100))%, check every \(Int(checkInterval))s)")
        
        // Cancel existing timer if any
        Self.timerLock.lock()
        Self.autoVacuumTimers[key]?.invalidate()
        Self.timerLock.unlock()
        
        // Create timer
        let timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task {
                do {
                    let stats = try await self.getStorageStats()
                    
                    if stats.wastePercentage >= wasteThreshold * 100 {
                        BlazeLogger.info("🤖 Auto-VACUUM triggered: \(String(format: "%.1f", stats.wastePercentage))% waste")
                        
                        let vacuumStats = try await self.vacuum()
                        
                        BlazeLogger.info("🤖 Auto-VACUUM complete: reclaimed \(vacuumStats.sizeReclaimed / 1024 / 1024) MB")
                    } else {
                        BlazeLogger.trace("🤖 Auto-VACUUM check: \(String(format: "%.1f", stats.wastePercentage))% waste (below \(Int(wasteThreshold * 100))% threshold)")
                    }
                } catch {
                    BlazeLogger.warn("🤖 Auto-VACUUM check failed: \(error)")
                }
            }
        }
        
        // Store timer
        Self.timerLock.lock()
        Self.autoVacuumTimers[key] = timer
        Self.timerLock.unlock()
    }
    
    /// Disable automatic VACUUM
    public func disableAutoVacuum() {
        let key = "\(name)-\(fileURL.path)"
        
        Self.timerLock.lock()
        Self.autoVacuumTimers[key]?.invalidate()
        Self.autoVacuumTimers.removeValue(forKey: key)
        Self.timerLock.unlock()
        
        BlazeLogger.info("🤖 Auto-VACUUM disabled")
    }
    
    /// Cleanup auto vacuum timer for this database instance
    internal func cleanupAutoVacuumTimer() {
        let key = "\(name)-\(fileURL.path)"
        
        Self.timerLock.lock()
        Self.autoVacuumTimers[key]?.invalidate()
        Self.autoVacuumTimers.removeValue(forKey: key)
        Self.timerLock.unlock()
    }
}

