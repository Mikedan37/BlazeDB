import Foundation
import XCTest
@testable import BlazeDBCore

/// `transaction { }` promises all-or-nothing: a throw inside the block must
/// restore every insert, update AND delete made earlier in the block, and must
/// leave the client able to start the next transaction.
final class TransactionThrowRollbackTests: XCTestCase {
    private struct Forced: Error {}
    private let password = "TxThrowRollback-Test-2026!"
    private var databaseURL: URL!

    override func setUp() {
        super.setUp()
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TxThrowRollback-\(UUID().uuidString).blazedb")
    }

    override func tearDown() {
        if let databaseURL {
            let base = databaseURL.deletingPathExtension()
            for ext in ["meta", "wal", "salt", "txn_backup", "txn_state"] {
                try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
            }
            try? FileManager.default.removeItem(at: databaseURL)
        }
        super.tearDown()
    }

    private func open() throws -> BlazeDBClient {
        try BlazeDBClient(name: "tx-throw-rollback", fileURL: databaseURL, password: password)
    }

    private func marker(_ db: BlazeDBClient, _ id: UUID) throws -> String? {
        try db.fetch(id: id)?.storage["marker"]?.stringValue
    }

    /// Records larger than one page span an overflow chain — the Seeker job
    /// records do (descriptions run well past 4 KB).
    private func seed(_ db: BlazeDBClient, padBytes: Int = 0) throws -> (keep: UUID, edit: UUID, gone: UUID) {
        func rec(_ m: String) -> BlazeDataRecord {
            BlazeDataRecord(["marker": .string(m), "pad": .string(String(repeating: "x", count: padBytes))])
        }
        return (try db.insert(rec("keep")), try db.insert(rec("edit-before")), try db.insert(rec("gone-before")))
    }

    private func assertBaseline(_ db: BlazeDBClient, _ ids: (keep: UUID, edit: UUID, gone: UUID),
                                inserted: UUID?, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try marker(db, ids.keep), "keep", file: file, line: line)
        XCTAssertEqual(try marker(db, ids.edit), "edit-before", "update must be undone", file: file, line: line)
        XCTAssertEqual(try marker(db, ids.gone), "gone-before", "delete must be undone", file: file, line: line)
        if let inserted {
            XCTAssertNil(try db.fetch(id: inserted), "insert must be undone", file: file, line: line)
        }
        XCTAssertEqual(try db.fetchAll().count, 3, file: file, line: line)
    }

    /// The Seeker shape: delete, then insert, then update, then throw.
    func testThrowInsideTransactionRestoresInsertUpdateAndDelete() throws {
        try throwInsideTransactionRestoresInsertUpdateAndDelete(padBytes: 0)
    }

    /// Same, with multi-page (overflow) records — the shape that fails on device.
    func testThrowInsideTransactionRestoresMultiPageRecords() throws {
        try throwInsideTransactionRestoresInsertUpdateAndDelete(padBytes: 20_000)
    }

    private func throwInsideTransactionRestoresInsertUpdateAndDelete(padBytes: Int) throws {
        let db = try open()
        defer { try? db.close() }
        let ids = try seed(db, padBytes: padBytes)

        var inserted: UUID?
        XCTAssertThrowsError(try db.transaction {
            try db.delete(id: ids.gone)
            inserted = try db.insert(BlazeDataRecord(["marker": .string("new")]))
            try db.update(id: ids.edit, with: BlazeDataRecord(["marker": .string("edit-after")]))
            throw Forced()
        }) { XCTAssertTrue($0 is Forced, "caller must see the block's own error, got \($0)") }

        try assertBaseline(db, ids, inserted: inserted)

        // Pages freed by the rolled-back delete belong to the restored row again:
        // later inserts must not be handed them.
        for i in 0..<4 {
            _ = try db.insert(BlazeDataRecord(["marker": .string("later-\(i)"),
                                               "pad": .string(String(repeating: "y", count: padBytes))]))
        }
        XCTAssertEqual(try marker(db, ids.gone), "gone-before", "post-rollback insert overwrote a restored row")
        XCTAssertEqual(try marker(db, ids.edit), "edit-before", "post-rollback insert overwrote a restored row")
        XCTAssertEqual(try db.fetchAll().count, 7)

        // Next transaction must start and commit.
        try db.transaction { try db.delete(id: ids.gone) }
        XCTAssertNil(try db.fetch(id: ids.gone))
        XCTAssertEqual(try db.fetchAll().count, 6)

        // And the rolled-back state is what is on disk.
        try db.close()
        let reopened = try open()
        defer { try? reopened.close() }
        XCTAssertEqual(try marker(reopened, ids.edit), "edit-before")
        XCTAssertNil(try reopened.fetch(id: ids.gone))
        XCTAssertEqual(try reopened.fetchAll().count, 6)
    }

    /// Delete only, then throw — the narrowest reproduction of the report.
    func testThrowAfterDeleteOnlyRestoresDeletedRows() throws {
        for pad in [0, 20_000] {
            setUp()
            try throwAfterDeleteOnly(padBytes: pad)
            tearDown()
        }
    }

    private func throwAfterDeleteOnly(padBytes: Int) throws {
        let db = try open()
        defer { try? db.close() }
        let ids = try seed(db, padBytes: padBytes)

        XCTAssertThrowsError(try db.transaction {
            try db.delete(id: ids.gone)
            try db.delete(id: ids.edit)
            throw Forced()
        })
        try assertBaseline(db, ids, inserted: nil)
        try db.transaction {}
    }

    /// The freed page of a delete is reused by a later insert in the same
    /// transaction; rollback must still bring the deleted row back intact.
    func testDeleteThenInsertReusingFreedPageRestoresDeletedRow() throws {
        for pad in [0, 20_000] {
            setUp()
            try deleteThenInsertReusingFreedPageRestoresDeletedRow(padBytes: pad)
            tearDown()
        }
    }

    private func deleteThenInsertReusingFreedPageRestoresDeletedRow(padBytes: Int) throws {
        let db = try open()
        defer { try? db.close() }
        let ids = try seed(db, padBytes: padBytes)

        var newIDs: [UUID] = []
        XCTAssertThrowsError(try db.transaction {
            try db.delete(id: ids.gone)
            for i in 0..<4 { newIDs.append(try db.insert(BlazeDataRecord(["marker": .string("new-\(i)"), "pad": .string(String(repeating: "z", count: padBytes))]))) }
            throw Forced()
        })
        try assertBaseline(db, ids, inserted: nil)
        for id in newIDs { XCTAssertNil(try db.fetch(id: id)) }
        try db.transaction {}
    }

    /// Nested begin is rejected; the inner rejection must not leave the outer
    /// transaction (or the client) wedged.
    func testNestedTransactionThrowRollsBackOuterAndClientRecovers() throws {
        for pad in [0, 20_000] {
            setUp()
            try nestedTransactionThrowRollsBackOuterAndClientRecovers(padBytes: pad)
            tearDown()
        }
    }

    private func nestedTransactionThrowRollsBackOuterAndClientRecovers(padBytes: Int) throws {
        let db = try open()
        defer { try? db.close() }
        let ids = try seed(db, padBytes: padBytes)

        XCTAssertThrowsError(try db.transaction {
            try db.delete(id: ids.gone)
            try db.transaction { try db.delete(id: ids.edit) } // throws "already in progress"
        })
        try assertBaseline(db, ids, inserted: nil)
        try db.transaction {}
    }

    /// Two throwing transactions in a row: the second must not report
    /// "Transaction already in progress".
    func testRepeatedThrowingTransactionsDoNotWedgeClient() throws {
        for pad in [0, 20_000] {
            setUp()
            try repeatedThrowingTransactionsDoNotWedgeClient(padBytes: pad)
            tearDown()
        }
    }

    private func repeatedThrowingTransactionsDoNotWedgeClient(padBytes: Int) throws {
        let db = try open()
        defer { try? db.close() }
        let ids = try seed(db, padBytes: padBytes)
        for _ in 0..<3 {
            XCTAssertThrowsError(try db.transaction {
                try db.delete(id: ids.gone)
                throw Forced()
            }) { XCTAssertTrue($0 is Forced, "got \($0)") }
        }
        try assertBaseline(db, ids, inserted: nil)
    }

    /// Crash mid-transaction (client never commits or rolls back, process
    /// dies): reopening restores the pre-transaction state, deletes included.
    func testCrashMidTransactionRestoresDeletesOnReopen() throws {
        for pad in [0, 20_000] {
            setUp()
            try crashMidTransaction(padBytes: pad)
            tearDown()
        }
    }

    private func crashMidTransaction(padBytes: Int) throws {
        var db: BlazeDBClient? = try open()
        let ids = try seed(db!, padBytes: padBytes)
        try db!.beginTransaction()
        try db!.delete(id: ids.gone)
        _ = try db!.insert(BlazeDataRecord(["marker": .string("new")]))
        try db!.update(id: ids.edit, with: BlazeDataRecord(["marker": .string("edit-after")]))
        try db!.persist()
        db = nil // simulate crash: no commit, no rollback, no close

        let reopened = try open()
        defer { try? reopened.close() }
        try assertBaseline(reopened, ids, inserted: nil)
        try reopened.transaction {}
    }

    /// A crash outside a transaction still replays the WAL. Discarding the log is
    /// only valid when a pre-transaction backup is restored.
    func testCrashOutsideTransactionStillReplaysWAL() throws {
        let marker = try crashImage(after: { db in
            let id = try db.insert(BlazeDataRecord(["marker": .string("kept")]))
            try db.persist()
            return id
        }, requireTransactionState: false)
        let handle = try FileHandle(forUpdating: marker.url)
        try handle.truncate(atOffset: 0)
        try handle.close()

        let reopened = try BlazeDBClient(name: "tx-crash-wal", fileURL: marker.url, password: password)
        defer { try? reopened.close() }
        XCTAssertEqual(try reopened.fetch(id: marker.id)?.storage["marker"]?.stringValue, "kept")
    }

    /// Kill during an open transaction: the pre-transaction backup must win over
    /// the WAL. Replaying post-begin page images onto the restored file publishes
    /// the aborted write on the original record's page.
    func testCrashMidUpdateDoesNotReplayAbortedWrite() throws {
        let marker = try crashImage(after: { db in
            let id = try db.insert(BlazeDataRecord(["marker": .string("before")]))
            try db.persist()
            try db.beginTransaction()
            try db.update(id: id, with: BlazeDataRecord(["marker": .string("after")]))
            try db.persist()
            return id
        })
        let reopened = try BlazeDBClient(name: "tx-crash-wal", fileURL: marker.url, password: password)
        defer { try? reopened.close() }
        XCTAssertEqual(try reopened.fetch(id: marker.id)?.storage["marker"]?.stringValue, "before")
        XCTAssertEqual(try reopened.fetchAll().count, 1)
    }

    /// The aborted insert reused the deleted row's page. Replaying that WAL image
    /// after backup restore makes fetch(original) return the intruder.
    func testCrashMidDeleteAndReuseDoesNotOverwriteRestoredRow() throws {
        let marker = try crashImage(after: { db in
            let id = try db.insert(BlazeDataRecord(["marker": .string("original")]))
            try db.persist()
            try db.beginTransaction()
            try db.delete(id: id)
            _ = try db.insert(BlazeDataRecord(["marker": .string("intruder")]))
            try db.persist()
            return id
        })
        let reopened = try BlazeDBClient(name: "tx-crash-wal", fileURL: marker.url, password: password)
        defer { try? reopened.close() }
        XCTAssertEqual(try reopened.fetch(id: marker.id)?.storage["marker"]?.stringValue, "original")
        XCTAssertNil(try reopened.fetchAll().first { $0.storage["marker"]?.stringValue == "intruder" })
        XCTAssertEqual(try reopened.fetchAll().count, 1)
    }

    private struct CrashMarker {
        let url: URL
        let id: UUID
    }

    /// Runs `body` through an open transaction, copies the on-disk image, then
    /// closes the live client (which rolls the original back) and puts the
    /// copied image back. Reopening that image is the crash.
    private func crashImage(after body: (BlazeDBClient) throws -> UUID, requireTransactionState: Bool = true) throws -> CrashMarker {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("TxCrashWAL-\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("crash.blazedb")
        let db = try BlazeDBClient(name: "tx-crash-wal", fileURL: url, password: password)
        let id = try body(db)

        let walURL = url.deletingPathExtension().appendingPathExtension("wal")
        let walSize = (try? Data(contentsOf: walURL).count) ?? 0
        XCTAssertGreaterThan(walSize, 0, "the crash image must include a durable WAL")
        if requireTransactionState {
            let stateFiles = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("txn_in_progress-") && $0.pathExtension == "state" }
            XCTAssertEqual(stateFiles.count, 1)
        }

        let snapshot = fm.temporaryDirectory.appendingPathComponent("TxCrashWAL-snap-\(UUID().uuidString)")
        try fm.createDirectory(at: snapshot, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try fm.copyItem(at: item, to: snapshot.appendingPathComponent(item.lastPathComponent))
        }

        try db.close()

        for item in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try fm.removeItem(at: item)
        }
        for item in try fm.contentsOfDirectory(at: snapshot, includingPropertiesForKeys: nil) {
            try fm.copyItem(at: item, to: directory.appendingPathComponent(item.lastPathComponent))
        }
        try? fm.removeItem(at: snapshot)
        addTeardownBlock { try? fm.removeItem(at: directory) }
        return CrashMarker(url: url, id: id)
    }
}
