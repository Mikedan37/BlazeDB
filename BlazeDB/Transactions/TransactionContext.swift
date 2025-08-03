//  TransactionContext.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/16/25.
import Foundation

final class TransactionContext {
    private var log = TransactionLog()
    private var stagedPages: [Int: Data] = [:] // New: read/write cache
    private let store: PageStore

    init(store: PageStore) {
        self.store = store
    }

    func write(pageID: Int, data: Data) {
        stagedPages[pageID] = data
        log.recordWrite(pageID: pageID, data: data)
    }

    func read(pageID: Int) throws -> Data {
        if let staged = stagedPages[pageID] {
            return staged
        } else {
            return try store.readPage(index: pageID)
        }
    }

    func delete(pageID: Int) {
        stagedPages[pageID] = Data()
        log.recordDelete(pageID: pageID)
    }

    func commit() throws {
        try log.flush(to: store)
    }

    func rollback() {
        stagedPages.removeAll()
    }
}
