//
//  RecordVersion.swift
//  BlazeDB
//
//  MVCC Foundation: Record versioning
//
//  Each record can have multiple versions. Transactions see a consistent
//  snapshot based on when they started.
//
//  Created: 2025-11-13
//

import Foundation

/// A single version of a record
///
/// MVCC keeps multiple versions of each record. Each version has:
/// - A unique version number (monotonically increasing)
/// - Creation timestamp
/// - Deletion timestamp (if deleted)
/// - Page location for the actual data
public struct RecordVersion: Codable, Equatable, Hashable {
    /// Unique identifier for the record (constant across versions)
    public let recordID: UUID
    
    /// Version number (higher = newer)
    public let version: UInt64
    
    /// Page number where this version's data is stored
    public let pageNumber: Int
    
    /// When this version was created
    public let createdAt: Date
    
    /// When this version was deleted (nil if active)
    public let deletedAt: Date?
    
    /// Transaction ID that created this version
    public let createdByTransaction: UInt64
    
    /// Transaction ID that deleted this version (0 if not deleted)
    public let deletedByTransaction: UInt64
    
    /// Is this version currently visible?
    public var isActive: Bool {
        deletedAt == nil
    }
    
    /// Is this version visible to a transaction at the given snapshot version?
    public func isVisibleTo(snapshotVersion: UInt64) -> Bool {
        // Must be created before or at snapshot
        guard version <= snapshotVersion else {
            return false
        }
        
        // Must not be deleted, or deleted after snapshot
        if deletedByTransaction != 0 {
            return deletedByTransaction > snapshotVersion
        }
        
        return true
    }
    
    public init(
        recordID: UUID,
        version: UInt64,
        pageNumber: Int,
        createdAt: Date = Date(),
        deletedAt: Date? = nil,
        createdByTransaction: UInt64,
        deletedByTransaction: UInt64 = 0
    ) {
        self.recordID = recordID
        self.version = version
        self.pageNumber = pageNumber
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.createdByTransaction = createdByTransaction
        self.deletedByTransaction = deletedByTransaction
    }
}

/// Manager for record versions
///
/// This is the heart of MVCC. It:
/// - Tracks all versions of all records
/// - Provides snapshot isolation for reads
/// - Manages version creation and deletion
/// - Coordinates garbage collection
public class VersionManager {
    /// All versions, indexed by record ID
    /// Key: Record UUID
    /// Value: Array of versions (sorted by version number, oldest first)
    private var versions: [UUID: [RecordVersion]] = [:]
    
    /// Global version counter (monotonically increasing)
    private var currentVersion: UInt64 = 0
    
    /// Active transactions (snapshot version → count)
    /// Used for garbage collection
    private var activeSnapshots: [UInt64: Int] = [:]
    
    /// Page garbage collector (tracks obsolete disk pages)
    public let pageGC: PageGarbageCollector
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init(pageGC: PageGarbageCollector = PageGarbageCollector()) {
        self.pageGC = pageGC
    }
    
    // MARK: - Version Management
    
    /// Get the next version number
    public func nextVersion() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        
        currentVersion += 1
        return currentVersion
    }
    
    /// Get current version (for snapshots)
    public func getCurrentVersion() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        
        return currentVersion
    }
    
    /// Add a new version of a record
    public func addVersion(_ version: RecordVersion) {
        lock.lock()
        defer { lock.unlock() }
        
        versions[version.recordID, default: []].append(version)
        
        // Keep sorted by version number
        versions[version.recordID]?.sort { $0.version < $1.version }
    }
    
    /// Mark a record version as deleted
    public func deleteVersion(
        recordID: UUID,
        atSnapshot snapshotVersion: UInt64,
        byTransaction transactionID: UInt64
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard var recordVersions = versions[recordID] else {
            throw BlazeDBError.recordNotFound(id: recordID)
        }
        
        // Find the visible version at this snapshot
        guard let index = recordVersions.firstIndex(where: {
            $0.isVisibleTo(snapshotVersion: snapshotVersion)
        }) else {
            throw BlazeDBError.recordNotFound(id: recordID)
        }
        
        // Mark as deleted
        var version = recordVersions[index]
        version = RecordVersion(
            recordID: version.recordID,
            version: version.version,
            pageNumber: version.pageNumber,
            createdAt: version.createdAt,
            deletedAt: Date(),
            createdByTransaction: version.createdByTransaction,
            deletedByTransaction: transactionID
        )
        
        recordVersions[index] = version
        versions[recordID] = recordVersions
    }
    
    /// Get the visible version of a record for a given snapshot
    public func getVersion(
        recordID: UUID,
        snapshot: UInt64
    ) -> RecordVersion? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let recordVersions = versions[recordID] else {
            return nil
        }
        
        // Find the newest version visible to this snapshot
        return recordVersions
            .filter { $0.isVisibleTo(snapshotVersion: snapshot) }
            .max { $0.version < $1.version }
    }
    
    /// Get all record IDs that have visible versions at a snapshot
    public func getAllVisibleRecordIDs(snapshot: UInt64) -> [UUID] {
        lock.lock()
        defer { lock.unlock() }
        
        return versions.keys.filter { recordID in
            versions[recordID]?.contains { $0.isVisibleTo(snapshotVersion: snapshot) } ?? false
        }
    }
    
    // MARK: - Snapshot Tracking (for GC)
    
    /// Register a new snapshot (transaction started)
    public func registerSnapshot(_ snapshot: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        
        activeSnapshots[snapshot, default: 0] += 1
    }
    
    /// Unregister a snapshot (transaction ended)
    public func unregisterSnapshot(_ snapshot: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        
        if let count = activeSnapshots[snapshot] {
            if count <= 1 {
                activeSnapshots.removeValue(forKey: snapshot)
            } else {
                activeSnapshots[snapshot] = count - 1
            }
        }
    }
    
    /// Get the oldest active snapshot (for GC)
    public func getOldestActiveSnapshot() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        
        return activeSnapshots.keys.min()
    }
    
    // MARK: - Garbage Collection
    
    /// Clean up old versions that no transaction can see
    ///
    /// This is critical for memory management. Without GC, versions accumulate forever.
    public func garbageCollect() -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        // Find the oldest snapshot anyone might need
        guard let oldestSnapshot = activeSnapshots.keys.min() else {
            // No active transactions - can clean everything except current
            return garbageCollectAggressively()
        }
        
        var removedCount = 0
        var freedPages: [Int] = []
        
        for (recordID, recordVersions) in versions {
            // Keep only versions that might be visible to active snapshots
            let kept = recordVersions.filter { version in
                // Keep if visible to oldest snapshot
                version.isVisibleTo(snapshotVersion: oldestSnapshot) ||
                // Or if it's the newest version (for future reads)
                version.version > oldestSnapshot
            }
            
            // Track pages from removed versions
            let removed = Set(recordVersions).subtracting(kept)
            for version in removed {
                freedPages.append(version.pageNumber)
            }
            
            removedCount += recordVersions.count - kept.count
            
            if kept.isEmpty {
                versions.removeValue(forKey: recordID)
            } else {
                versions[recordID] = kept
            }
        }
        
        // Free the pages for reuse! 🗑️
        if !freedPages.isEmpty {
            pageGC.markPagesObsolete(freedPages)
            BlazeLogger.debug("🗑️ Version GC freed \(freedPages.count) disk pages for reuse")
        }
        
        return removedCount
    }
    
    /// Aggressive GC when no transactions are active
    private func garbageCollectAggressively() -> Int {
        var removedCount = 0
        var freedPages: [Int] = []
        
        for (recordID, recordVersions) in versions {
            // Keep only the newest version of each record
            if let newest = recordVersions.max(by: { $0.version < $1.version }) {
                // Free pages from old versions
                let oldVersions = recordVersions.filter { $0.version != newest.version }
                for version in oldVersions {
                    freedPages.append(version.pageNumber)
                }
                
                removedCount += recordVersions.count - 1
                versions[recordID] = [newest]
            }
        }
        
        // Free the pages for reuse! 🗑️
        if !freedPages.isEmpty {
            pageGC.markPagesObsolete(freedPages)
            BlazeLogger.debug("🗑️ Aggressive GC freed \(freedPages.count) disk pages")
        }
        
        return removedCount
    }
    
    // MARK: - Statistics
    
    /// Get version statistics (for monitoring/debugging)
    public func getStats() -> VersionStats {
        lock.lock()
        defer { lock.unlock() }
        
        let totalVersions = versions.values.reduce(0) { $0 + $1.count }
        let uniqueRecords = versions.count
        let activeTransactions = activeSnapshots.values.reduce(0, +)
        let avgVersionsPerRecord = uniqueRecords > 0 ? Double(totalVersions) / Double(uniqueRecords) : 0
        
        return VersionStats(
            totalVersions: totalVersions,
            uniqueRecords: uniqueRecords,
            averageVersionsPerRecord: avgVersionsPerRecord,
            currentVersion: currentVersion,
            activeSnapshots: activeTransactions,
            oldestActiveSnapshot: activeSnapshots.keys.min()
        )
    }
}

/// Statistics about version storage
public struct VersionStats {
    public let totalVersions: Int
    public let uniqueRecords: Int
    public let averageVersionsPerRecord: Double
    public let currentVersion: UInt64
    public let activeSnapshots: Int
    public let oldestActiveSnapshot: UInt64?
    
    public var description: String {
        """
        MVCC Version Stats:
          Total Versions: \(totalVersions)
          Unique Records: \(uniqueRecords)
          Avg Versions/Record: \(String(format: "%.2f", averageVersionsPerRecord))
          Current Version: \(currentVersion)
          Active Snapshots: \(activeSnapshots)
          Oldest Snapshot: \(oldestActiveSnapshot?.description ?? "none")
        """
    }
}

