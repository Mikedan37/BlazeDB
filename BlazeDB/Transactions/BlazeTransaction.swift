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
            try TransactionLog().begin(txID: txID.uuidString)
        } catch {
            BlazeLogger.warn("Failed to begin transaction log: \(error)")
        }
    }

    public func read(pageID: Int) throws -> Data {
        guard state == .open else {
            throw NSError(domain: "BlazeTransaction", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Transaction is closed"])
        }
        
        let data = try context.read(pageID: pageID)

        // Treat an empty payload as a 'record not found' condition, but return empty Data instead of throwing.
        return data.isEmpty ? Data() : data
    }
    
    public func write(pageID: Int, data: Data) throws {
        guard state == .open else {
            throw NSError(domain: "BlazeTransaction", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Transaction is closed"])
        }
        do {
            try TransactionLog().append(.write(pageID: pageID, data: data))
        } catch {
            BlazeLogger.warn("Failed to append write to transaction log: \(error)")
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
            BlazeLogger.warn("Failed to append delete to transaction log: \(error)")
        }
        context.delete(pageID: pageID)
    }

    public func commit() throws {
        guard state == .open else {
            throw NSError(domain: "BlazeTransaction", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Transaction already finalized"])
        }
        try context.commit()
        do {
            try TransactionLog().commit(txID: txID.uuidString)
            try TransactionLog().clear()
        } catch {
            BlazeLogger.warn("Failed to commit/clear transaction log: \(error)")
        }
        state = .committed
    }

    public func rollback() throws {
        switch state {
        case .rolledBack:
            throw NSError(domain: "BlazeTransaction", code: 1005, userInfo: [NSLocalizedDescriptionKey: "Transaction already rolled back"])

        case .committed:
            throw NSError(domain: "BlazeTransaction", code: 1006, userInfo: [NSLocalizedDescriptionKey: "Cannot rollback a committed transaction"])

        case .open:
            context.rollback()
            
            do {
                try TransactionLog().abort(txID: txID.uuidString)
                try TransactionLog().clear()
            } catch {
                BlazeLogger.warn("Failed to clean WAL during rollback: \(error)")
            }

            state = .rolledBack
            return

        default:
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
