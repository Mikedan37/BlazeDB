//  BlazeTransaction.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/16/25.
import Foundation

public final class BlazeTransaction {
    private let context: TransactionContext
    private var isCommitted = false

    init(store: PageStore) {
        self.context = TransactionContext(store: store)
    }

    public func read(pageID: Int) throws -> Data {
        return try context.read(pageID: pageID)
    }
    
    public func write(pageID: Int, data: Data) {
        context.write(pageID: pageID, data: data)
    }

    public func delete(pageID: Int) {
        context.delete(pageID: pageID)
    }

    public func commit() throws {
        guard !isCommitted else { return }
        try context.commit()
        isCommitted = true
    }

    public func rollback() {
        context.rollback()
    }
}
