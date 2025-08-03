//  TransactionLog.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/16/25.
import Foundation

struct TransactionLog {
    enum Operation {
        case write(pageID: Int, data: Data)
        case delete(pageID: Int)
    }

    private(set) var operations: [Operation] = []

    mutating func recordWrite(pageID: Int, data: Data) {
        operations.append(.write(pageID: pageID, data: data))
    }

    mutating func recordDelete(pageID: Int) {
        operations.append(.delete(pageID: pageID))
    }

    func flush(to store: PageStore) throws {
        for op in operations {
            switch op {
            case .write(let pageID, let data):
                try store.writePage(index: pageID, plaintext: data)

            case .delete(let pageID):
                // For now, overwrite the page with empty data
                try store.writePage(index: pageID, plaintext: Data())
            }
        }
    }
}
