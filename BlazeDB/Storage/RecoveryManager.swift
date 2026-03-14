import Foundation

/// Result of WAL recovery.
public struct RecoveryResult: Sendable {
    /// Page writes from committed transactions, in LSN order.
    /// The caller should apply these to the page store.
    public let committedWrites: [WALEntry]

    /// Number of transactions that were not committed (discarded).
    public let uncommittedTransactions: Int

    /// The highest LSN seen during recovery.
    public let highestLSN: UInt64
}

/// Recovers database state from a WAL file.
///
/// Recovery strategy:
/// 1. Scan all valid entries from WAL (via DurabilityManager.scanEntries)
/// 2. Group entries by transactionID
/// 3. A transaction is committed iff a .commit record exists for its ID
/// 4. Collect .write and .delete entries from committed transactions only
/// 5. Return them in LSN order for the caller to apply
///
/// Torn-write handling is delegated to DurabilityManager.scanEntries:
/// - Invalid trailing entry → ignored (torn write from crash)
/// - Invalid entry in the middle with valid entries after → hard failure
public enum RecoveryManager {

    /// Recover committed writes from a WAL file.
    public static func recover(walURL: URL) throws -> RecoveryResult {
        let entries = try DurabilityManager.scanEntries(from: walURL)
        return processEntries(entries)
    }

    /// Process a list of WAL entries and extract committed writes.
    static func processEntries(_ entries: [WALEntry]) -> RecoveryResult {
        var committedTxIDs: Set<UUID> = []
        var abortedTxIDs: Set<UUID> = []
        var allTxIDs: Set<UUID> = []
        var highestLSN: UInt64 = 0

        for entry in entries {
            if entry.lsn > highestLSN {
                highestLSN = entry.lsn
            }

            // Basic payload sanity checks before replay classification.
            if entry.operation == .delete && !entry.payload.isEmpty {
                continue
            }
            if (entry.operation == .begin || entry.operation == .commit || entry.operation == .abort || entry.operation == .checkpoint)
                && !entry.payload.isEmpty {
                continue
            }

            switch entry.operation {
            case .begin:
                allTxIDs.insert(entry.transactionID)
            case .commit:
                committedTxIDs.insert(entry.transactionID)
            case .abort:
                abortedTxIDs.insert(entry.transactionID)
            case .write, .delete:
                allTxIDs.insert(entry.transactionID)
            case .checkpoint:
                break
            }
        }

        // Collect writes/deletes from committed transactions, preserving LSN order
        let committedWrites = entries.filter { entry in
            (entry.operation == .write || entry.operation == .delete)
            && committedTxIDs.contains(entry.transactionID)
        }

        // Uncommitted = seen but neither committed nor aborted
        let uncommitted = allTxIDs.subtracting(committedTxIDs).subtracting(abortedTxIDs)

        return RecoveryResult(
            committedWrites: committedWrites,
            uncommittedTransactions: uncommitted.count,
            highestLSN: highestLSN
        )
    }
}
