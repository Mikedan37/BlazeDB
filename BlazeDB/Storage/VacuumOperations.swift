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
                    let statsBefore = try self._getStorageStatsSync()
                    _ = try self.vacuum()
                    let statsAfter = try self._getStorageStatsSync()
                    let duration = Date().timeIntervalSince(startTime)

                    let stats = VacuumStats(
                        pagesBefore: statsBefore.totalPages,
                        pagesAfter: statsAfter.totalPages,
                        pagesReclaimed: statsBefore.totalPages - statsAfter.totalPages,
                        sizeBefore: statsBefore.fileSize,
                        sizeAfter: statsAfter.fileSize,
                        sizeReclaimed: statsBefore.fileSize - statsAfter.fileSize,
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

