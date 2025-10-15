//  BlazeTransaction.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/16/25.
import Foundation

public final class BlazeTransaction {
    private let context: TransactionContext
    private let txID: UUID
    
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
        self.context = TransactionContext(store: store)
        do {
            try TransactionLog().begin(txID: txID.hashValue)
        } catch {
            print("[TX-TRACE] ⚠️ Failed to initialize WAL for txID: \(txID) — \(error.localizedDescription)")
            print("[TX-TRACE] This may delay WAL file creation until first write.")
        }
    }

    public func read(pageID: Int) throws -> Data {
        guard state == .open else {
            throw NSError(domain: "BlazeTransaction", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Transaction is closed"])
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("[TX-TRACE] 📖 Entering read(pageID:) for txID: \(txID)")
        print("[TX-TRACE] Current state: \(state)")
        print("[TX-TRACE] Attempting context.read(pageID: \(pageID))...")

        let data = try context.read(pageID: pageID)
        print("[TX-TRACE] ✅ context.read(pageID:) returned \(data.count) bytes")

        // Treat an empty payload as a 'record not found' condition, but return empty Data instead of throwing.
        if data.isEmpty {
            print("[TX-TRACE] ⚠️ Record for pageID \(pageID) not found (0 bytes) — returning empty Data")
            return Data()
        }

        print("[TX-TRACE] 📦 Returning \(data.count) bytes for pageID \(pageID)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        return data
    }
    
    public func write(pageID: Int, data: Data) throws {
        guard state == .open else {
            throw NSError(domain: "BlazeTransaction", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Transaction is closed"])
        }
        do {
            try TransactionLog().append(.write(pageID: pageID, data: data))
        } catch {
            // Non-critical logging error, do not break transaction flow
        }
        context.write(pageID: pageID, data: data)
    }

    public func delete(pageID: Int) throws {
        guard state == .open else {
            throw NSError(domain: "BlazeTransaction", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Transaction is closed"])
        }
        do {
            try TransactionLog().append(.delete(pageID: pageID))
        } catch {
            // Non-critical logging error, do not break transaction flow
        }
        context.delete(pageID: pageID)
    }

    public func commit() throws {
        print("[TX] Commit called on \(txID), current state: \(state)")
        guard state == .open else {
            throw NSError(domain: "BlazeTransaction", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Transaction already finalized"])
        }
        try context.commit()
        do {
            try TransactionLog().commit(txID: txID.hashValue)
            try TransactionLog().clear()
        } catch {
            // Non-critical logging error, do not break transaction flow
        }
        state = .committed
        print("[TX] Transaction \(txID) committed successfully")
    }

    public func rollback() throws {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("[TX-TRACE] 🚨 Entering rollback() for txID: \(txID)")
        print("[TX-TRACE] Current state: \(state)")
        print("[TX-TRACE] Transaction Context: \(context)")
        print("[TX-TRACE] Begin rollback flow...")

        switch state {
        case .rolledBack:
            print("[TX-TRACE] ❌ Rollback called but transaction already rolled back.")
            print("[TX-TRACE] About to throw error 1005 (Already rolled back).")
            throw NSError(domain: "BlazeTransaction", code: 1005, userInfo: [NSLocalizedDescriptionKey: "Transaction already rolled back"])

        case .committed:
            print("[TX-TRACE] ❌ Rollback called on committed transaction.")
            print("[TX-TRACE] About to throw error 1006 (Cannot rollback committed transaction).")
            throw NSError(domain: "BlazeTransaction", code: 1006, userInfo: [NSLocalizedDescriptionKey: "Cannot rollback a committed transaction"])

        case .open:
            print("[TX-TRACE] ✅ State is open — proceeding with rollback.")
            print("[TX-TRACE] Invoking context.rollback()...")
            context.rollback()
            print("[TX-TRACE] ✅ Context rollback() completed.")
            
            do {
                print("[TX-TRACE] Attempting to abort WAL for txID hash: \(txID.hashValue)")
                try TransactionLog().abort(txID: txID.hashValue)
                print("[TX-TRACE] ✅ WAL abort succeeded for txID: \(txID)")
                
                print("[TX-TRACE] Attempting to clear WAL logs...")
                try TransactionLog().clear()
                print("[TX-TRACE] ✅ WAL clear() completed successfully.")
            } catch {
                print("[TX-TRACE] ⚠️ Error during WAL cleanup: \(error)")
                print("[TX-TRACE] Continuing rollback despite log cleanup failure.")
            }

            state = .rolledBack
            print("[TX-TRACE] ✅ Transaction state updated to: \(state)")
            print("[TX-TRACE] 🔥 Transaction \(txID) rolled back successfully")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return

        default:
            print("[TX-TRACE] ⚠️ Unknown or finalized state encountered during rollback: \(state)")
            print("[TX-TRACE] Throwing error 1004 (Already finalized).")
            throw NSError(domain: "BlazeTransaction", code: 1004, userInfo: [NSLocalizedDescriptionKey: "Transaction already finalized"])
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
