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
}
