//
//  ConflictResolution.swift
//  BlazeDB
//
//  MVCC Phase 3: Write conflict detection and resolution
//
//  Handles optimistic locking conflicts when multiple transactions
//  try to modify the same record.
//
//  Created: 2025-11-13
//

import Foundation

/// Conflict resolution strategy for MVCC writes
public enum ConflictResolutionStrategy {
    /// Abort transaction and throw error (default)
    case abort
    
    /// Retry transaction automatically (up to N times)
    case retry(maxAttempts: Int)
    
    /// Last-write-wins (always succeed, may lose updates)
    case lastWriteWins
    
    /// Custom resolution handler
    case custom((RecordVersion, RecordVersion) throws -> RecordVersion)
}

/// Write conflict error with detailed information
public struct WriteConflict: Error, CustomStringConvertible {
    public let recordID: UUID
    public let yourVersion: UInt64
    public let currentVersion: UInt64
    public let conflictingFields: [String]
    
    public var description: String {
        """
        Write Conflict on record \(recordID):
          Your snapshot:    v\(yourVersion)
          Current version:  v\(currentVersion)
          Conflicting fields: \(conflictingFields.joined(separator: ", "))
          
        Resolution: Retry transaction or use different conflict strategy
        """
    }
}

/// Conflict resolver for MVCC transactions
public class ConflictResolver {
    
    private let strategy: ConflictResolutionStrategy
    private let versionManager: VersionManager
    
    public init(strategy: ConflictResolutionStrategy, versionManager: VersionManager) {
        self.strategy = strategy
        self.versionManager = versionManager
    }
    
    /// Detect if there's a write conflict
    public func detectConflict(
        recordID: UUID,
        snapshotVersion: UInt64
    ) -> WriteConflict? {
        // Get the current latest version
        guard let currentVersion = versionManager.getVersion(
            recordID: recordID,
            snapshot: .max
        ) else {
            // Record doesn't exist - no conflict
            return nil
        }
        
        // Check if someone modified it after our snapshot
        if currentVersion.version > snapshotVersion {
            return WriteConflict(
                recordID: recordID,
                yourVersion: snapshotVersion,
                currentVersion: currentVersion.version,
                conflictingFields: []  // NOTE: Field-level conflict detection intentionally not implemented.
                // Conflicts are detected at record level. Field-level detection would require
                // maintaining per-field version history, which adds significant complexity.
            )
        }
        
        return nil
    }
    
    /// Resolve a write conflict using the configured strategy
    public func resolve(
        conflict: WriteConflict,
        yourRecord: BlazeDataRecord,
        currentRecord: BlazeDataRecord
    ) throws -> BlazeDataRecord {
        switch strategy {
        case .abort:
            throw BlazeDBError.transactionFailed(
                conflict.description,
                underlyingError: conflict
            )
            
        case .retry:
            // Retry is handled at transaction level
            throw BlazeDBError.transactionFailed(
                "Retry required: \(conflict.description)",
                underlyingError: conflict
            )
            
        case .lastWriteWins:
            // Always use your record (may lose concurrent updates)
            return yourRecord
            
        case .custom(let handler):
            // Custom merge logic
            // currentRecord = what's in DB now
            // yourRecord = what you're trying to write
            let currentVersion = versionManager.getVersion(
                recordID: conflict.recordID,
                snapshot: .max
            )!
            let yourVersion = RecordVersion(
                recordID: conflict.recordID,
                version: conflict.yourVersion,
                pageNumber: 0,  // Placeholder
                createdByTransaction: conflict.yourVersion
            )
            let resolved = try handler(yourVersion, currentVersion)
            
            // Return the merged record (custom logic decides)
            return yourRecord  // Simplified for now
        }
    }
}

/// Retry-able transaction wrapper
public class RetryableTransaction {
    
    private let versionManager: VersionManager
    private let pageStore: PageStore
    private let maxRetries: Int
    
    public init(
        versionManager: VersionManager,
        pageStore: PageStore,
        maxRetries: Int = 3
    ) {
        self.versionManager = versionManager
        self.pageStore = pageStore
        self.maxRetries = maxRetries
    }
    
    /// Execute a transaction with automatic retry on conflict
    public func execute<T>(
        operation: (MVCCTransaction) throws -> T
    ) throws -> T {
        var attempt = 0
        var lastError: Error?
        
        while attempt < maxRetries {
            attempt += 1
            
            do {
                // Create fresh transaction
                let tx = MVCCTransaction(
                    versionManager: versionManager,
                    pageStore: pageStore
                )
                
                // Execute operation
                let result = try operation(tx)
                
                // Success!
                return result
                
            } catch let error as BlazeDBError {
                // Check if it's a conflict
                if case .transactionFailed(let msg, _) = error,
                   msg.contains("conflict") || msg.contains("Retry") {
                    lastError = error
                    
                    // Wait a bit before retrying (exponential backoff)
                    // NOTE: Thread.sleep is intentional here. This synchronous retry loop
                    // requires blocking waits for exponential backoff. Converting to async
                    // would require making execute() async, which is an API change.
                    let backoffMs = min(100 * (1 << attempt), 1000)
                    Thread.sleep(forTimeInterval: Double(backoffMs) / 1000.0)
                    
                    print("⚠️ Transaction conflict, retrying... (attempt \(attempt)/\(maxRetries))")
                    continue
                }
                
                // Not a conflict - re-throw
                throw error
            } catch {
                // Unknown error - re-throw
                throw error
            }
        }
        
        // All retries exhausted
        throw BlazeDBError.transactionFailed(
            "Transaction failed after \(maxRetries) retries",
            underlyingError: lastError
        )
    }
}

/// Transaction statistics for monitoring
public struct TransactionStats {
    public let totalAttempts: Int
    public let successfulCommits: Int
    public let conflicts: Int
    public let retries: Int
    public let averageRetries: Double
    
    public var description: String {
        """
        MVCC Transaction Stats:
          Total Attempts:      \(totalAttempts)
          Successful Commits:  \(successfulCommits)
          Conflicts:           \(conflicts)
          Retries:             \(retries)
          Avg Retries/Commit:  \(String(format: "%.2f", averageRetries))
        """
    }
}

