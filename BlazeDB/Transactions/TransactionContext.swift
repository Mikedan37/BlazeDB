//  TransactionContext.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/16/25.
import Foundation

final class TransactionContext {
    private var log = TransactionLog()
    private var stagedPages: [Int: Data] = [:] // New: read/write cache
    private var baselinePages: [Int: Data] = [:] // 🔄 Baseline state for rollback
    private let store: PageStore

    init(store: PageStore) {
        self.store = store
    }

    func write(pageID: Int, data: Data) {
        // Save baseline before first write to this page
        if baselinePages[pageID] == nil {
            if let existing = try? store.readPage(index: pageID) {
                baselinePages[pageID] = existing
            } else {
                // Page doesn't exist yet - mark as "new" with empty data
                baselinePages[pageID] = Data()
            }
        }
        
        stagedPages[pageID] = data
        log.recordWrite(pageID: pageID, data: data)
    }

    func read(pageID: Int) throws -> Data {
        if let staged = stagedPages[pageID] {
            if staged.count == 0 {
                throw NSError(domain: "TransactionContext", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Attempted to read rolled-back or deleted page"])
            }
            return staged
        } else {
            return try store.readPage(index: pageID) ?? Data()
        }
    }

    func delete(pageID: Int) {
        // Save baseline before delete
        if baselinePages[pageID] == nil {
            if let existing = try? store.readPage(index: pageID) {
                baselinePages[pageID] = existing
            } else {
                baselinePages[pageID] = Data()
            }
        }
        
        stagedPages[pageID] = Data()
        log.recordDelete(pageID: pageID)
    }

    func commit() throws {
        try log.flush(to: store)
        stagedPages.removeAll()
        baselinePages.removeAll()
    }

    func rollback() {
        guard !stagedPages.isEmpty else {
            return
        }

        // Restore baseline state for all modified pages
        for (pageID, _) in stagedPages {
            if let baseline = baselinePages[pageID] {
                do {
                    if baseline.isEmpty {
                        // Page was new - delete it
                        try store.deletePage(index: pageID)
                    } else {
                        // Page existed - restore original data
                        try store.writePage(index: pageID, plaintext: baseline)
                    }
                } catch {
                    BlazeLogger.warn("Failed to restore page \(pageID): \(error)")
                }
            } else {
                BlazeLogger.warn("No baseline found for page \(pageID)")
            }
        }

        stagedPages.removeAll()
        baselinePages.removeAll()
    }
    #if DEBUG
    func flushStagedWritesForTesting() throws {
        BlazeLogger.debug("Flushing staged writes manually (for testing)")
        try log.flush(to: store)
    }
    #endif
}
