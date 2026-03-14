import XCTest
import CryptoKit
@testable import BlazeDBCore

/// Tests for BlazeTransaction with unified WAL mode.
/// These verify that transaction commit/rollback produce correct WAL records
/// and that recovery replays only committed transactions.
final class BlazeTransactionUnifiedWALTests: XCTestCase {

    var tempDir: URL!
    let testKey = SymmetricKey(size: .bits256)

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-tx-unified-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - The two critical invariants

    /// Committed transaction is replayed on recovery.
    func testTransactionCommitReplaysOnRecovery() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

        // Write via transaction and close
        let store1 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let tx = BlazeTransaction(store: store1)
        try tx.write(pageID: 0, data: Data(repeating: 0xAA, count: 100))
        try tx.write(pageID: 1, data: Data(repeating: 0xBB, count: 100))
        try tx.commit()
        store1.close()

        // Verify WAL has real transaction structure (not auto-transactions)
        // After close, WAL should be checkpointed (empty), but let's verify
        // that data survived by reopening
        let store2 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let page0 = try store2.readPage(index: 0)
        let page1 = try store2.readPage(index: 1)
        XCTAssertEqual(page0, Data(repeating: 0xAA, count: 100))
        XCTAssertEqual(page1, Data(repeating: 0xBB, count: 100))
        store2.close()
    }

    /// Aborted transaction does NOT replay on recovery.
    func testTransactionAbortDoesNotReplay() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")

        // Write page 0 first (committed baseline)
        let store1 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        try store1.writePage(index: 0, plaintext: Data(repeating: 0x11, count: 100))
        store1.close()

        // Start a transaction that modifies page 0, then rollback
        let store2 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let tx = BlazeTransaction(store: store2)
        try tx.write(pageID: 0, data: Data(repeating: 0xFF, count: 100))
        try tx.rollback()
        store2.close()

        // Reopen — page 0 should have the original data, not the rolled-back data
        let store3 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let page0 = try store3.readPage(index: 0)
        XCTAssertEqual(page0, Data(repeating: 0x11, count: 100))
        store3.close()
    }

    // MARK: - WAL structure verification

    /// Unified-mode transaction commit produces begin/write/commit WAL records.
    func testTransactionCommitProducesCorrectWALStructure() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

        let store = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let tx = BlazeTransaction(store: store)
        try tx.write(pageID: 5, data: Data(repeating: 0xCC, count: 100))
        try tx.commit()

        // Read WAL before close/checkpoint
        let entries = try DurabilityManager.scanEntries(from: walURL)
        let ops = entries.map { $0.operation }

        // Should have exactly one transaction: begin, write(s), commit
        // (Not multiple auto-transactions per page)
        XCTAssertEqual(ops.filter { $0 == .begin }.count, 1)
        XCTAssertEqual(ops.filter { $0 == .commit }.count, 1)
        XCTAssertEqual(ops.filter { $0 == .write }.count, 1)

        // All entries should share the same transactionID
        let txIDs = Set(entries.map { $0.transactionID })
        XCTAssertEqual(txIDs.count, 1, "All WAL entries should belong to one transaction")

        store.close()
    }

    /// Transaction rollback produces abort record, no page writes in WAL.
    func testTransactionRollbackProducesAbortRecord() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

        let store = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let tx = BlazeTransaction(store: store)
        try tx.write(pageID: 5, data: Data(repeating: 0xDD, count: 100))
        try tx.rollback()

        // WAL should have abort record
        let entries = try DurabilityManager.scanEntries(from: walURL)
        let ops = entries.map { $0.operation }

        XCTAssertTrue(ops.contains(.abort), "Rollback should produce abort record")
        XCTAssertFalse(ops.contains(.commit), "Rollback should not have commit record")
        // Should NOT have page write entries (pages were never written)
        XCTAssertEqual(ops.filter { $0 == .write }.count, 0,
            "Rolled-back transaction should not have WAL write entries")

        store.close()
    }

    // MARK: - Multi-page transaction

    /// Multiple page writes within a single transaction share one begin/commit.
    func testMultiPageTransactionSingleBeginCommit() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

        let store = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let tx = BlazeTransaction(store: store)
        for i in 0..<5 {
            try tx.write(pageID: i, data: Data(repeating: UInt8(i), count: 100))
        }
        try tx.commit()

        let entries = try DurabilityManager.scanEntries(from: walURL)
        let ops = entries.map { $0.operation }

        // One begin, five writes, one commit
        XCTAssertEqual(ops.filter { $0 == .begin }.count, 1)
        XCTAssertEqual(ops.filter { $0 == .write }.count, 5)
        XCTAssertEqual(ops.filter { $0 == .commit }.count, 1)

        // Verify all pages readable
        for i in 0..<5 {
            let data = try store.readPage(index: i)
            XCTAssertEqual(data, Data(repeating: UInt8(i), count: 100))
        }

        store.close()
    }

    // MARK: - Read-your-own-writes

    /// Transaction can read its own staged writes before commit.
    func testReadYourOwnWritesBeforeCommit() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let store = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let tx = BlazeTransaction(store: store)

        let testData = Data(repeating: 0xEE, count: 100)
        try tx.write(pageID: 7, data: testData)

        let readBack = try tx.read(pageID: 7)
        XCTAssertEqual(readBack, testData)

        try tx.rollback()
        store.close()
    }

    // MARK: - Legacy mode unaffected

    /// Legacy mode transactions still work (no regression).
    func testLegacyModeTransactionsUnaffected() throws {
        let dbURL = tempDir.appendingPathComponent("test-legacy.db")
        let store = try PageStore(fileURL: dbURL, key: testKey, walMode: .legacy)
        let tx = BlazeTransaction(store: store)

        try tx.write(pageID: 0, data: Data(repeating: 0x77, count: 100))
        try tx.commit()

        let readBack = try store.readPage(index: 0)
        XCTAssertEqual(readBack, Data(repeating: 0x77, count: 100))

        store.close()
    }
}
