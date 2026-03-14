//  TransactionContext.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/16/25.
import Foundation

final class TransactionContext {
    private var log = TransactionLog()
    private var stagedPages: [Int: Data] = [:]
    private var baselinePages: [Int: Data] = [:]
    internal let store: PageStore
    private let unified: Bool

    init(store: PageStore) {
        self.store = store
        self.unified = store.walMode == .unified
    }

    func write(pageID: Int, data: Data) {
        // Save baseline before first write (needed for legacy rollback)
        if !unified && baselinePages[pageID] == nil {
            if let existing = try? store.readPage(index: pageID) {
                baselinePages[pageID] = existing
            } else {
                baselinePages[pageID] = Data()
            }
        }

        stagedPages[pageID] = data
        if !unified {
            log.recordWrite(pageID: pageID, data: data)
        }
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
        if !unified && baselinePages[pageID] == nil {
            if let existing = try? store.readPage(index: pageID) {
                baselinePages[pageID] = existing
            } else {
                baselinePages[pageID] = Data()
            }
        }

        stagedPages[pageID] = Data()
        if !unified {
            log.recordDelete(pageID: pageID)
        }
    }

    /// Legacy commit: flush staged writes through TransactionLog to PageStore.
    func commitLegacy() throws {
        try log.flush(to: store)
        stagedPages.removeAll()
        baselinePages.removeAll()
    }

    /// Unified commit: returns staged pages for the caller (BlazeTransaction) to
    /// handle WAL-then-pwrite ordering. Does NOT write to disk.
    func commitUnified() -> [Int: Data] {
        let pages = stagedPages
        stagedPages.removeAll()
        return pages
    }

    /// Legacy rollback: restores baseline pages.
    func rollbackLegacy() {
        guard !stagedPages.isEmpty else { return }

        for (pageID, _) in stagedPages {
            if let baseline = baselinePages[pageID] {
                do {
                    if baseline.isEmpty {
                        try store.deletePage(index: pageID)
                    } else {
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

    /// Unified rollback: discard staged pages. No disk writes needed because
    /// pages were never written to the main file in unified mode.
    func rollbackUnified() {
        stagedPages.removeAll()
    }

    #if DEBUG
    func flushStagedWritesForTesting() throws {
        BlazeLogger.debug("Flushing staged writes manually (for testing)")
        try log.flush(to: store)
    }
    #endif
}
