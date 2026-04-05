//  BlazeTransaction.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/16/25.
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif

/// Low-level page read/write transaction scoped to a `PageStore`.
///
/// `BlazeDBClient` document CRUD does not use this type for normal operations. Prefer `BlazeDBClient`
/// for application code; use `BlazeTransaction` for tests or advanced page-level scenarios.
///
/// In legacy WAL mode (when `store.walMode != .unified`), this type can persist transaction activity
/// to a newline-delimited JSON `TransactionLog` on disk. Those NDJSON artifacts contain plaintext
/// page payloads and are intended for legacy/debug/advanced workflows, not the default encrypted-at-rest
/// durability path used by `BlazeDBClient`.
public final class BlazeTransaction {
    private let context: TransactionContext
    private let store: PageStore
    private let txID: UUID
    private let unified: Bool
    private var beginFailure: Error?

    internal enum State {
        case open, committed, rolledBack
    }

    /// Exposes the current state for testing and diagnostics (read-only).
    internal var debugState: State {
        return state
    }

    internal var state: State = .open

    init(store: PageStore) {
        self.txID = UUID()
        self.store = store
        self.unified = store.walMode == .unified
        self.context = TransactionContext(store: store)

        if unified {
            // Unified mode: WAL begin via DurabilityManager
            if let dm = store.durabilityManager {
                do {
                    try dm.appendBegin(transactionID: txID)
                } catch {
                    beginFailure = error
                    BlazeLogger.error("Failed to WAL begin: \(error)")
                }
            }
        } else {
            // Legacy mode: TransactionLog begin
            do {
                try TransactionLog().begin(txID: txID.uuidString)
            } catch {
                beginFailure = error
                BlazeLogger.warn("Failed to begin transaction log: \(error)")
            }
        }
    }

    private func ensureBeginSucceeded() throws {
        if let error = beginFailure {
            throw NSError(
                domain: "BlazeTransaction",
                code: 1007,
                userInfo: [
                    NSLocalizedDescriptionKey: "Transaction begin failed; transaction is invalid",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
    }

    public func read(pageID: Int) throws -> Data {
        try ensureBeginSucceeded()
        guard state == .open else {
            throw NSError(domain: "BlazeTransaction", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Transaction is closed"])
        }

        let data = try context.read(pageID: pageID)
        return data.isEmpty ? Data() : data
    }

    public func write(pageID: Int, data: Data) throws {
        try ensureBeginSucceeded()
        guard state == .open else {
            throw NSError(domain: "BlazeTransaction", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Transaction is closed"])
        }

        if !unified {
            // Legacy: append to TransactionLog on disk
            do {
                try TransactionLog().append(.write(pageID: pageID, data: data))
            } catch {
                BlazeLogger.warn("Failed to append write to transaction log: \(error)")
            }
        }
        // Both modes: stage in context (in-memory only, no disk write yet)
        context.write(pageID: pageID, data: data)
    }

    public func delete(pageID: Int) throws {
        try ensureBeginSucceeded()
        guard state == .open else {
            throw NSError(domain: "BlazeTransaction", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Transaction is closed"])
        }

        if !unified {
            do {
                try TransactionLog().append(.delete(pageID: pageID))
            } catch {
                BlazeLogger.warn("Failed to append delete to transaction log: \(error)")
            }
        }
        context.delete(pageID: pageID)
    }

    public func commit() throws {
        try ensureBeginSucceeded()
        guard state == .open else {
            throw NSError(domain: "BlazeTransaction", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Transaction already finalized"])
        }

        if unified {
            try _commitUnified()
        } else {
            try _commitLegacy()
        }
        state = .committed
    }

    /// Unified commit: WAL writes → WAL commit (fsync) → pwrite pages → fsync main.
    /// The ordering invariant WAL-durable-before-page-write is enforced here.
    private func _commitUnified() throws {
        guard let dm = store.durabilityManager else {
            throw NSError(domain: "BlazeTransaction", code: 1010, userInfo: [
                NSLocalizedDescriptionKey: "Unified mode but no DurabilityManager"
            ])
        }

        let stagedPages = context.commitUnified().sorted { $0.key < $1.key }

        // Phase 1: Encrypt all pages and append to WAL
        var encryptedBuffers: [(index: Int, buffer: Data)] = []
        for (pageID, plaintext) in stagedPages {
            guard pageID >= 0 && pageID <= Int(UInt32.max) else {
                throw NSError(
                    domain: "BlazeTransaction",
                    code: 1011,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid page ID out of UInt32 range: \(pageID)"]
                )
            }
            let pageIndex = UInt32(pageID)
            if plaintext.isEmpty {
                // Delete operation — skip encryption, just record in WAL
                try dm.appendDelete(transactionID: txID, pageIndex: pageIndex)
                continue
            }
            let buffer = try store._encryptPageBuffer(plaintext: plaintext)
            try dm.appendWrite(transactionID: txID, pageIndex: pageIndex, data: buffer)
            encryptedBuffers.append((index: pageID, buffer: buffer))
        }

        // Phase 2: WAL commit — this fsyncs the WAL. Durability guarantee.
        try dm.appendCommit(transactionID: txID)

        // Phase 3: Apply pages to the main file (WAL is now durable)
        for (pageID, buffer) in encryptedBuffers {
            try store._writeEncryptedBuffer(index: pageID, buffer: buffer)
        }

        // Phase 4: fsync main file
        try store.fileHandle.compatSynchronize()
    }

    /// Legacy commit: delegate to TransactionContext → TransactionLog → PageStore.
    private func _commitLegacy() throws {
        try context.commitLegacy()
        if ProcessInfo.processInfo.environment["BLAZEDB_OVERFLOW_CRASH_HOOK"] == "afterWALAppendBeforeCommitMark" {
            let code = Int32(ProcessInfo.processInfo.environment["BLAZEDB_OVERFLOW_CRASH_EXIT_CODE"] ?? "86") ?? 86
            _exit(code)
        }
        do {
            try TransactionLog().commit(txID: txID.uuidString)
            try TransactionLog().clear()
        } catch {
            BlazeLogger.warn("Failed to commit/clear transaction log: \(error)")
        }
    }

    public func rollback() throws {
        try ensureBeginSucceeded()
        switch state {
        case .rolledBack:
            throw NSError(domain: "BlazeTransaction", code: 1005, userInfo: [NSLocalizedDescriptionKey: "Transaction already rolled back"])

        case .committed:
            throw NSError(domain: "BlazeTransaction", code: 1006, userInfo: [NSLocalizedDescriptionKey: "Cannot rollback a committed transaction"])

        case .open:
            if unified {
                context.rollbackUnified()
                // WAL abort — fsyncs the abort record
                if let dm = store.durabilityManager {
                    do {
                        try dm.appendAbort(transactionID: txID)
                    } catch {
                        BlazeLogger.warn("Failed to WAL abort: \(error)")
                    }
                }
            } else {
                context.rollbackLegacy()
                do {
                    try TransactionLog().abort(txID: txID.uuidString)
                    try TransactionLog().clear()
                } catch {
                    BlazeLogger.warn("Failed to clean WAL during rollback: \(error)")
                }
            }
            state = .rolledBack
        }
    }
    #if DEBUG
    /// Forces a flush of staged writes for testing WAL existence before commit.
    public func flushStagedWritesForTesting() {
        try? context.flushStagedWritesForTesting()
    }

    /// Ensures the WAL file exists for testing purposes.
    public func ensureWALCreatedForTesting() {
        try? TransactionLog().ensureExists()
    }
    #endif
}
