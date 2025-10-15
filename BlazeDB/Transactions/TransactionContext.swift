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
        print("[CTX-TRACE] 📝 Staging write for pageID \(pageID) (\(data.count) bytes)")
        stagedPages[pageID] = data
        log.recordWrite(pageID: pageID, data: data)
        print("[CTX-TRACE] ✅ Recorded staged write in log for page \(pageID)")
    }

    func read(pageID: Int) throws -> Data {
        if let staged = stagedPages[pageID] {
            print("[CTX-TRACE] 📖 Read from stagedPages for pageID \(pageID) (\(staged.count) bytes)")
            if staged.count == 0 {
                print("[CTX-TRACE] ⚠️ Attempted to read rolled-back or deleted page (pageID \(pageID)) from stagedPages.")
                throw NSError(domain: "TransactionContext", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Attempted to read rolled-back or deleted page"])
            }
            return staged
        } else {
            let data = try store.readPage(index: pageID) ?? Data()
            print("[CTX-TRACE] 📖 Read from store for pageID \(pageID) (\(data.count) bytes)")
            if data.count == 0 {
                print("[CTX-TRACE] ⚠️ Attempted to read rolled-back or deleted page (pageID \(pageID)) from store.")
                return Data() // Previously threw an error
            }
            return data
        }
    }

    func delete(pageID: Int) {
        stagedPages[pageID] = Data()
        log.recordDelete(pageID: pageID)
    }

    func commit() throws {
        print("[CTX-TRACE] 💾 Committing \(stagedPages.count) staged pages...")
        try log.flush(to: store)
        print("[CTX-TRACE] ✅ Commit completed — all staged writes flushed to store.")
        stagedPages.removeAll()
    }

    func rollback() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("[CTX-TRACE] 🚨 Entering rollback()")
        print("[CTX-TRACE] Staged pages count before rollback: \(stagedPages.count)")

        if stagedPages.isEmpty {
            print("[CTX-TRACE] ⚠️ No staged pages to rollback.")
        } else {
            for (pageID, data) in stagedPages {
                print("[CTX-TRACE] 🔄 Reverting staged page \(pageID) (\(data.count) bytes)")
                do {
                    try store.deletePage(index: pageID)
                    print("[CTX-TRACE] ✅ Deleted page \(pageID) from store.")
                } catch {
                    print("[CTX-TRACE] ⚠️ Failed to delete page \(pageID): \(error)")
                }
            }
        }

        stagedPages.removeAll()
        print("[CTX-TRACE] ✅ Cleared stagedPages. Context rollback complete.")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
#if DEBUG
    func flushStagedWritesForTesting() throws {
        print("[CTX-DEBUG] 💾 Flushing staged writes manually (for testing)...")
        try log.flush(to: store)
    }
#endif
}
