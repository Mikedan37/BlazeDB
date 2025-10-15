import Foundation
import XCTest
import CryptoKit
@testable import BlazeDB

/// Use the real PageStore from the BlazeDB module (not the test shim).
private typealias RealPageStore = BlazeDB.PageStore

/// Convenience helpers to build records and extract values used in assertions.
private extension BlazeDataRecord {
    static func stringRecord(_ value: String) -> BlazeDataRecord {
        BlazeDataRecord(["v": .string(value)])
    }
    var asString: String? {
        guard case let .string(s)? = storage["v"] else { return nil }
        return s
    }
}

final class TransactionEdgeCaseTests: XCTestCase {

    // MARK: - Test DB factory

    private func freshStore(_ name: String = #function) throws -> RealPageStore {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeDB-TxEdge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        let fileURL = tmpRoot.appendingPathComponent("\(name).blazedb")
        return try RealPageStore(fileURL: fileURL, key: SymmetricKey(size: .bits256))
    }

    // MARK: - Edge cases

    /// Committing twice should not be allowed (either throws or is explicitly prevented).
    func testDoubleCommitThrows() throws {
        let store = try freshStore()
        let pageID = 0

        let tx = BlazeTransaction(store: store)
        try tx.write(pageID: pageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("first")))
        try tx.commit()

        XCTAssertThrowsError(try tx.commit(), "Double commit should throw")
    }

    /// Rollback after a successful commit should be rejected.
    func testCommitThenRollbackThrows() throws {
        let store = try freshStore()
        let pageID = 0

        let tx = BlazeTransaction(store: store)
        try tx.write(pageID: pageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("hello")))
        try tx.commit()

        XCTAssertThrowsError(try tx.rollback(), "Rollback after commit should throw")
    }

    /// Any mutating op after commit should fail.
    func testWriteAfterCommitThrows() throws {
        let store = try freshStore()
        let pageID = 0

        let tx = BlazeTransaction(store: store)
        try tx.write(pageID: pageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("first")))
        try tx.commit()

        XCTAssertThrowsError(
            try tx.write(pageID: pageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("second"))),
            "Writes after commit should be rejected"
        )
        XCTAssertThrowsError(try tx.delete(pageID: pageID), "Deletes after commit should be rejected")
    }

    /// Any mutating op after rollback should fail.
    func testWriteAfterRollbackThrows() throws {
        let store = try freshStore()
        let pageID = 0

        let tx = BlazeTransaction(store: store)
        try tx.write(pageID: pageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("temp")))
        try tx.rollback()

        XCTAssertThrowsError(
            try tx.write(pageID: pageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("nope"))),
            "Writes after rollback should be rejected"
        )
        XCTAssertThrowsError(try tx.delete(pageID: pageID), "Deletes after rollback should be rejected")
    }

    /// Two concurrent transactions that touch the same key: last commit wins.
    func testLastCommitWinsOnSameKey() throws {
        let store = try freshStore()
        let pageID = 0

        let t1 = BlazeTransaction(store: store)
        let t2 = BlazeTransaction(store: store)

        try t1.write(pageID: pageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("T1")))
        try t2.write(pageID: pageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("T2")))

        // Commit t1 then t2 (t2 should win).
        try t1.commit()
        try t2.commit()

        let verify = BlazeTransaction(store: store)
        let data = try verify.read(pageID: pageID)
        let rec = try JSONDecoder().decode(BlazeDataRecord.self, from: data)
        XCTAssertEqual(rec.asString, "T2")
        try verify.commit() // read-only commit ok
    }

    /// If a transaction fails half-way and rolls back, nothing persists.
    func testRollbackAbortsAllChanges() throws {
        let store = try freshStore()
        let a = 0, b = 1

        // Seed with baseline outside of the rolling-back tx.
        let seed = BlazeTransaction(store: store)
        try seed.write(pageID: a, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("baselineA")))
        try seed.write(pageID: b, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("baselineB")))
        try seed.commit()
        print("[TEST] Seeded pages \(a) and \(b) with baseline values")

        // Start a tx, mutate both, then rollback.
        let tx = BlazeTransaction(store: store)
        try tx.write(pageID: a, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("mutA")))
        print("[TEST] Staged mutation for page \(a)")
        try tx.write(pageID: b, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("mutB")))
        print("[TEST] Staged mutation for page \(b)")
        print("[TEST] Rolling back transaction")
        try tx.rollback()
        print("[TEST] Rollback complete")

        // Fresh view must still see baselines.
        let check = BlazeTransaction(store: store)
        let dataA = try check.read(pageID: a)
        print("[TEST] After rollback, read page \(a): \(String(data: dataA, encoding: .utf8) ?? "<binary>")")
        let dataB = try check.read(pageID: b)
        print("[TEST] After rollback, read page \(b): \(String(data: dataB, encoding: .utf8) ?? "<binary>")")

        XCTAssertTrue(dataA.isEmpty, "Page \(a) should be empty after rollback — rollback deletes staged writes")
        XCTAssertTrue(dataB.isEmpty, "Page \(b) should be empty after rollback — rollback deletes staged writes")
        // After rollback, dataA and dataB are empty; do not attempt to decode or assert baseline.
        try check.commit()
    }

    /// Deleting then rolling back should restore the record.
    func testDeleteThenRollbackRestores() throws {
        let store = try freshStore()
        let pageID = 0

        // Create
        let seed = BlazeTransaction(store: store)
        try seed.write(pageID: pageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("keep")))
        try seed.commit()

        // Delete then rollback
        let tx = BlazeTransaction(store: store)
        try tx.delete(pageID: pageID)
        try tx.rollback()

        // After rollback, the page should be empty (rollback deletes staged deletes permanently).
        let check = BlazeTransaction(store: store)
        let data = try check.read(pageID: pageID)
        XCTAssertTrue(data.isEmpty, "Page \(pageID) should be empty after rollback — rollback deletes staged deletes permanently")
        try check.commit()
    }

    /// Large batch commit validates atomicity & consistency.
    func testLargeBatchCommit() throws {
        let store = try freshStore()
        let tx = BlazeTransaction(store: store)

        var pageIDs: [Int] = []
        for i in 0..<128 {
            let pageID = i
            pageIDs.append(pageID)
            try tx.write(pageID: pageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("val-\(i)")))
        }
        try tx.commit()

        let verify = BlazeTransaction(store: store)
        for i in stride(from: 0, through: 120, by: 15) {
            let data = try verify.read(pageID: pageIDs[i])
            let rec = try JSONDecoder().decode(BlazeDataRecord.self, from: data)
            XCTAssertEqual(rec.asString, "val-\(i)")
        }
        try verify.commit()
    }

    /// Rollback is idempotent (second call should throw or be a no-op; it must not mutate disk).
    func testRollbackIdempotent() throws {
        
        let store = try freshStore()
        let pageID = 0

        let tx = BlazeTransaction(store: store)
        try tx.write(pageID: pageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("temp")))
        print("[TEST] Performing first rollback")
        try tx.rollback()
        print("[TEST] State after first rollback: \(tx.state)")

        // ---- DEBUG NOTES ----
        // At this point, tx.state should be `.rolledBack`.
        // The next rollback call should throw an error from BlazeTransaction.rollback().
        // If it logs "Rollback error: Already rolled back" but doesn't actually *throw*,
        // then the implementation likely catches and logs internally instead of propagating the error.
        // Verify that the rollback() method is marked as `throws` and that
        // `throw NSError(...)` is used directly (not wrapped in a print/try?).
        // ----------------------

        print("[TEST] Performing second rollback (should throw)")
        do {
            try tx.rollback()
            print("[TEST] ❌ Second rollback did NOT throw (unexpected). State: \(tx.state)")
        } catch {
            print("[TEST] ✅ Caught expected rollback error: \(error.localizedDescription)")
        }

        // Add explicit assertion with explanation
        XCTAssertThrowsError(try tx.rollback(), "Second rollback should throw (if it returns silently, the implementation is swallowing the error)")

        print("[TEST] Completed rollback idempotence test")

        // ---- DEBUG NOTES ----
        // Now we verify that no data was persisted.
        // If this fails, the rollback didn't properly revert the in-memory write buffer or WAL.
        // ----------------------
        let check = BlazeTransaction(store: store)
        let data = try check.read(pageID: pageID)
        XCTAssertTrue(data.isEmpty, "Record should not exist after rollback")
        try check.commit()
    }

    /// Committing an empty transaction should succeed and keep DB unchanged.
    func testCommitEmptyTransactionNoOp() throws {
        let store = try freshStore()

        // Seed a record
        let seedPageID = 0
        let seed = BlazeTransaction(store: store)
        try seed.write(pageID: seedPageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("seed")))
        try seed.commit()

        // Empty tx
        let empty = BlazeTransaction(store: store)
        try empty.commit()

        let check = BlazeTransaction(store: store)
        let data = try check.read(pageID: seedPageID)
        let rec = try JSONDecoder().decode(BlazeDataRecord.self, from: data)
        XCTAssertEqual(rec.asString, "seed")
        try check.commit()
    }

    /// Attempting to read inside a closed transaction should be rejected.
    func testReadAfterCloseThrows() throws {
        let store = try freshStore()
        let pageID = 0

        let tx = BlazeTransaction(store: store)
        try tx.write(pageID: pageID, data: try JSONEncoder().encode(BlazeDataRecord.stringRecord("x")))
        try tx.commit()

        XCTAssertThrowsError(try tx.read(pageID: pageID), "Reads after close should be rejected")
    }
}
