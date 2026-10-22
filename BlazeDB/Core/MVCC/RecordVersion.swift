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
    
    /// Main page index for this version (start of overflow chain)
    public let pageNumber: Int
    
    /// Every disk page this version occupies, main page first. Matches catalog `indexMap` chains.
    public let pageIndices: [Int]
    
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
    
    /// All page indices that must be reclaimed when this version is garbage-collected.
    public var diskPageIndices: [Int] {
        pageIndices.isEmpty ? [pageNumber] : pageIndices
    }
    
    public init(
        recordID: UUID,
        version: UInt64,
        pageNumber: Int,
        pageIndices: [Int]? = nil,
        createdAt: Date = Date(),
        deletedAt: Date? = nil,
        createdByTransaction: UInt64,
        deletedByTransaction: UInt64 = 0
    ) {
        self.recordID = recordID
        self.version = version
        self.pageNumber = pageNumber
        if let pageIndices, !pageIndices.isEmpty {
            self.pageIndices = pageIndices
        } else {
            self.pageIndices = [pageNumber]
        }
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.createdByTransaction = createdByTransaction
        self.deletedByTransaction = deletedByTransaction
    }
    
    private enum CodingKeys: String, CodingKey {
        case recordID, version, pageNumber, pageIndices
        case createdAt, deletedAt, createdByTransaction, deletedByTransaction
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordID = try container.decode(UUID.self, forKey: .recordID)
        version = try container.decode(UInt64.self, forKey: .version)
        pageNumber = try container.decode(Int.self, forKey: .pageNumber)
        pageIndices = try container.decodeIfPresent([Int].self, forKey: .pageIndices) ?? [pageNumber]
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        createdByTransaction = try container.decode(UInt64.self, forKey: .createdByTransaction)
        deletedByTransaction = try container.decode(UInt64.self, forKey: .deletedByTransaction)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recordID, forKey: .recordID)
        try container.encode(version, forKey: .version)
        try container.encode(pageNumber, forKey: .pageNumber)
        if pageIndices.count > 1 {
            try container.encode(pageIndices, forKey: .pageIndices)
        }
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(createdByTransaction, forKey: .createdByTransaction)
        try container.encode(deletedByTransaction, forKey: .deletedByTransaction)
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
    
    /// Reset all MVCC state. Used when enabling MVCC on an existing database to rebuild
    /// version information from the authoritative indexMap.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        versions.removeAll()
        currentVersion = 0
        activeSnapshots.removeAll()
        pageGC.reset()
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
    
    /// Mark the version visible at `snapshotVersion` as deleted.
    ///
    /// Versions are stored oldest-first. Tombstoning the first visible row
    /// leaves a newer update in place, so a later read resurrects the previous
    /// value and a following insert reuses the live page chain.
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
        
        guard let target = visibleVersion(in: recordVersions, snapshot: snapshotVersion),
              let index = recordVersions.firstIndex(of: target) else {
            throw BlazeDBError.recordNotFound(id: recordID)
        }
        
        // Mark as deleted
        var version = recordVersions[index]
        version = RecordVersion(
            recordID: version.recordID,
            version: version.version,
            pageNumber: version.pageNumber,
            pageIndices: version.pageIndices,
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
        
        return visibleVersion(in: recordVersions, snapshot: snapshot)
    }
    
    /// Get all record IDs that have visible versions at a snapshot
    public func getAllVisibleRecordIDs(snapshot: UInt64) -> [UUID] {
        lock.lock()
        defer { lock.unlock() }
        
        return versions.keys.filter { recordID in
            guard let recordVersions = versions[recordID] else { return false }
            return visibleVersion(in: recordVersions, snapshot: snapshot) != nil
        }
    }
    
    /// The row a snapshot reads.
    ///
    /// A newer version hides every earlier one, including when updates never
    /// tombstone the previous row. A delete on the latest version therefore
    /// hides the whole record instead of falling through to older data.
    /// Caller must hold `lock`.
    private func visibleVersion(
        in recordVersions: [RecordVersion],
        snapshot: UInt64
    ) -> RecordVersion? {
        var best: RecordVersion?
        for version in recordVersions {
            guard version.version <= snapshot else { continue }
            if version.deletedByTransaction != 0 && version.deletedByTransaction <= snapshot {
                continue
            }
            let superseded = recordVersions.contains { newer in
                newer.version > version.version && newer.version <= snapshot
            }
            if superseded { continue }
            if best == nil || version.version > best!.version {
                best = version
            }
        }
        return best
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
            // Keep the newest row even when it is a delete tombstone. Dropping
            // that tombstone makes an older update visible again. Also keep the
            // row the oldest snapshot still reads, and anything newer than it.
            let newestVersionNumber = recordVersions.map(\.version).max()
            let visibleAtOldest = visibleVersion(in: recordVersions, snapshot: oldestSnapshot)
            let kept = recordVersions.filter { version in
                version.version == newestVersionNumber
                    || version.version == visibleAtOldest?.version
                    || version.version > oldestSnapshot
            }
            
            // Never recycle a page a surviving version still names. Overlapping
            // chains would otherwise hand a live overflow page to the next insert.
            let keptPages = Set(kept.flatMap(\.diskPageIndices))
            let removed = Set(recordVersions).subtracting(kept)
            for version in removed {
                for page in version.diskPageIndices where !keptPages.contains(page) {
                    freedPages.append(page)
                }
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
            BlazeLogger.debug("🗑️ Version GC freed \(freedPages.count) disk page slots for reuse")
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
                // Free pages from old versions, but not pages the surviving row still uses.
                let newestPages = Set(newest.diskPageIndices)
                let oldVersions = recordVersions.filter { $0.version != newest.version }
                for version in oldVersions {
                    for page in version.diskPageIndices where !newestPages.contains(page) {
                        freedPages.append(page)
                    }
                }
                
                removedCount += recordVersions.count - 1
                versions[recordID] = [newest]
            }
        }
        
        // Free the pages for reuse! 🗑️
        if !freedPages.isEmpty {
            pageGC.markPagesObsolete(freedPages)
            BlazeLogger.debug("🗑️ Aggressive GC freed \(freedPages.count) disk page slots")
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

