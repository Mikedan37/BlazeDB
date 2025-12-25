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
                    
                    // Flush all pending changes
                    try self.persist()
                    
                    // Create temporary compacted file
                    let tempURL = self.fileURL.deletingLastPathComponent()
                        .appendingPathComponent("\(self.fileURL.lastPathComponent).vacuum-\(UUID().uuidString)")
                    
                    defer {
                        try? FileManager.default.removeItem(at: tempURL)
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
                        
                        // Encode record
                        let encoded = try JSONEncoder().encode(record.storage)
                        
                        // Write to new file
                        try compactedStore.writePage(index: newPageIndex, plaintext: encoded)
                        
                        newIndexMap[id] = [newPageIndex]  // Store as [Int] array for consistency
                        newPageIndex += 1
                    }
                    
                    BlazeLogger.debug("Wrote \(newPageIndex) compacted pages")
                    
                    // Update metadata with new index map
                    var layout = try StorageLayout.load(from: self.metaURL)
                    layout.indexMap = newIndexMap
                    layout.nextPageIndex = newPageIndex
                    try layout.save(to: self.metaURL)
                    
                    // Get file sizes
                    let attrsOld = try FileManager.default.attributesOfItem(atPath: self.fileURL.path)
                    let sizeOld = attrsOld[.size] as? Int64 ?? 0
                    
                    let attrsNew = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                    let sizeNew = attrsNew[.size] as? Int64 ?? 0
                    
                    // Replace old file with compacted file
                    BlazeLogger.debug("Replacing old database file...")
                    try FileManager.default.removeItem(at: self.fileURL)
                    try FileManager.default.moveItem(at: tempURL, to: self.fileURL)
                    
                    // Reload collection with compacted data
                    let newStore = try PageStore(fileURL: self.fileURL, key: self.encryptionKey)
                    self.collection = try DynamicCollection(
                        store: newStore,
                        metaURL: self.metaURL,
                        project: self.project,
                        encryptionKey: self.encryptionKey
                    )
                    
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
        let layout = try StorageLayout.load(from: metaURL)
        
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

