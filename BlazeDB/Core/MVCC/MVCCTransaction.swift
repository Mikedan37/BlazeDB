//
//  MVCCTransaction.swift
//  BlazeDB
//
//  MVCC Transactions: Snapshot isolation for concurrent access
//
//  Each transaction sees a consistent snapshot of the database.
//  Reads never block writes, writes rarely block reads.
//
//  Created: 2025-11-13
//

import Foundation

/// An MVCC transaction with snapshot isolation
///
/// Key properties:
/// - Sees a consistent snapshot from transaction start
/// - Reads don't block (concurrent)
/// - Writes create new versions
/// - Optimistic concurrency control
public class MVCCTransaction {
    /// The snapshot version this transaction sees
    public let snapshotVersion: UInt64
    
    /// When this transaction started
    public let startTime: Date
    
    /// Unique transaction ID
    public let transactionID: UInt64
    
    /// Version manager
    private let versionManager: VersionManager
    
    /// Page store for reading/writing data
    private weak var pageStore: PageStore?
    
    /// Is this transaction still active?
    private var isActive: Bool = true
    
    /// Changes made in this transaction (for rollback)
    private var pendingWrites: [(UUID, RecordVersion)] = []
    
    // MARK: - Initialization
    
    public init(
        versionManager: VersionManager,
        pageStore: PageStore
    ) {
        self.versionManager = versionManager
        self.pageStore = pageStore
        self.transactionID = versionManager.nextVersion()
        self.snapshotVersion = versionManager.getCurrentVersion()
        self.startTime = Date()
        
        // Register this snapshot for GC tracking
        versionManager.registerSnapshot(snapshotVersion)
        
        BlazeLogger.debug("📸 MVCCTransaction \(transactionID) started (snapshot: \(snapshotVersion))")
    }
    
    deinit {
        if isActive {
            // Transaction wasn't committed or rolled back - rollback automatically
            try? rollback()
        }
        
        // Unregister snapshot
        versionManager.unregisterSnapshot(snapshotVersion)
        
        BlazeLogger.debug("📸 MVCCTransaction \(transactionID) ended")
    }
    
    // MARK: - Read Operations
    
    /// Read a record (sees snapshot version)
    public func read(recordID: UUID) throws -> BlazeDataRecord? {
        guard isActive else {
            throw BlazeDBError.transactionFailed(
                "Transaction is not active",
                underlyingError: nil
            )
        }
        
        // Get the version visible to this snapshot
        guard let version = versionManager.getVersion(
            recordID: recordID,
            snapshot: snapshotVersion
        ) else {
            return nil  // Record doesn't exist at this snapshot
        }
        
        // Read from page store
        guard let pageStore = pageStore else {
            throw BlazeDBError.transactionFailed(
                "Page store not available",
                underlyingError: nil
            )
        }
        
        guard let data = try pageStore.readPage(index: version.pageNumber) else {
            throw BlazeDBError.transactionFailed(
                "Failed to read page \(version.pageNumber)",
                underlyingError: nil
            )
        }
        
        // Deserialize using static method
        return try BlazeBinaryDecoder.decode(data)
    }
    
    /// Read all visible records
    public func readAll() throws -> [BlazeDataRecord] {
        guard isActive else {
            throw BlazeDBError.transactionFailed(
                "Transaction is not active",
                underlyingError: nil
            )
        }
        
        let recordIDs = versionManager.getAllVisibleRecordIDs(snapshot: snapshotVersion)
        
        var records: [BlazeDataRecord] = []
        for recordID in recordIDs {
            if let record = try read(recordID: recordID) {
                records.append(record)
            }
        }
        
        return records
    }
    
    // MARK: - Write Operations
    
    /// Write a new version of a record
    public func write(recordID: UUID, record: BlazeDataRecord) throws {
        guard isActive else {
            throw BlazeDBError.transactionFailed(
                "Transaction is not active",
                underlyingError: nil
            )
        }
        
        guard let pageStore = pageStore else {
            throw BlazeDBError.transactionFailed(
                "Page store not available",
                underlyingError: nil
            )
        }
        
        // Check for write conflicts (optimistic locking)
        let currentVersion = versionManager.getVersion(
            recordID: recordID,
            snapshot: UInt64.max  // Get absolute latest
        )
        
        if let current = currentVersion, current.version > snapshotVersion {
            // Someone else modified this record since we started!
            throw BlazeDBError.transactionFailed(
                """
                Write conflict: Record \(recordID) was modified by another transaction.
                Current version: \(current.version), Your snapshot: \(snapshotVersion)
                """,
                underlyingError: nil
            )
        }
        
        // Serialize record using static method
        let data = try BlazeBinaryEncoder.encode(record)
        
        // Try to reuse a freed page first (Page GC!)
        let pageNumber: Int
        if let freePage = versionManager.pageGC.getFreePage() {
            // Reuse freed page! ♻️
            try pageStore.writePageUnsynchronized(
                index: freePage,
                plaintext: data
            )
            pageNumber = freePage
        } else {
            // Allocate new page
            let newPage = pageStore.nextAvailablePageIndex()
            try pageStore.writePageUnsynchronized(
                index: newPage,
                plaintext: data
            )
            pageNumber = newPage
        }
        
        // Create new version
        let version = RecordVersion(
            recordID: recordID,
            version: transactionID,  // Use transaction ID as version
            pageNumber: pageNumber,
            createdAt: Date(),
            deletedAt: nil,
            createdByTransaction: transactionID,
            deletedByTransaction: 0
        )
        
        // Track for commit/rollback
        pendingWrites.append((recordID, version))
    }
    
    /// Delete a record (creates a deleted version)
    public func delete(recordID: UUID) throws {
        guard isActive else {
            throw BlazeDBError.transactionFailed(
                "Transaction is not active",
                underlyingError: nil
            )
        }
        
        // Check if record exists at our snapshot
        guard versionManager.getVersion(
            recordID: recordID,
            snapshot: snapshotVersion
        ) != nil else {
            throw BlazeDBError.recordNotFound(id: recordID)
        }
        
        // Check for conflicts
        let currentVersion = versionManager.getVersion(
            recordID: recordID,
            snapshot: UInt64.max
        )
        
        if let current = currentVersion, current.version > snapshotVersion {
            throw BlazeDBError.transactionFailed(
                "Write conflict: Record was modified by another transaction",
                underlyingError: nil
            )
        }
        
        // Mark as deleted
        try versionManager.deleteVersion(
            recordID: recordID,
            atSnapshot: snapshotVersion,
            byTransaction: transactionID
        )
    }
    
    // MARK: - Transaction Control
    
    /// Commit the transaction (make writes visible)
    public func commit() throws {
        guard isActive else {
            throw BlazeDBError.transactionFailed(
                "Transaction already ended",
                underlyingError: nil
            )
        }
        
        guard let pageStore = pageStore else {
            throw BlazeDBError.transactionFailed(
                "Page store not available",
                underlyingError: nil
            )
        }
        
        // Flush all pending writes to disk
        try pageStore.synchronize()
        
        // Add all versions to version manager
        for (_, version) in pendingWrites {
            versionManager.addVersion(version)
        }
        
        pendingWrites.removeAll()
        isActive = false
        
        BlazeLogger.debug("✅ Transaction \(transactionID) committed")
    }
    
    /// Rollback the transaction (discard writes)
    public func rollback() throws {
        guard isActive else {
            return  // Already ended
        }
        
        // Discard pending writes
        // (Pages are written but versions aren't added to version manager,
        //  so they're invisible and will be GC'd)
        pendingWrites.removeAll()
        isActive = false
        
        BlazeLogger.debug("⏪ Transaction \(transactionID) rolled back")
    }
}

// MARK: - Helper Extensions
// (nextAvailablePageIndex() is now implemented in PageStore.swift)

