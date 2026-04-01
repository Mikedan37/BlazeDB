import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
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

    // MARK: - Crash recovery scenarios (pre-Chunk 4 verification)

    /// Crash after WAL commit but before page fsync → recovery replays all pages.
    /// Simulates: WAL has committed tx, main file pages are stale/zeroed.
    func testCrashAfterWALCommitBeforePageFsync() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

        // Write a committed transaction
        let store1 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let tx = BlazeTransaction(store: store1)
        try tx.write(pageID: 0, data: Data(repeating: 0xAA, count: 100))
        try tx.write(pageID: 1, data: Data(repeating: 0xBB, count: 100))
        try tx.commit()

        // Capture WAL entries before close
        let walEntries = try DurabilityManager.scanEntries(from: walURL)
        let writeEntries = walEntries.filter { $0.operation == .write }
        XCTAssertEqual(writeEntries.count, 2)

        store1.close()

        // Simulate crash: corrupt main file pages, then re-inject WAL entries
        let mainFH = try FileHandle(forUpdating: dbURL)
        for i in 0..<2 {
            mainFH.seek(toFileOffset: UInt64(i * 4096))
            mainFH.write(Data(repeating: 0x00, count: 4096))
        }
        try mainFH.synchronize()
        try mainFH.close()

        // Re-inject committed WAL entries (simulating WAL survived but pages didn't)
        let dm = try DurabilityManager(walURL: walURL)
        let fakeTxID = UUID()
        try dm.appendBegin(transactionID: fakeTxID)
        for entry in writeEntries {
            try dm.appendWrite(transactionID: fakeTxID, pageIndex: entry.pageIndex, data: entry.payload)
        }
        try dm.appendCommit(transactionID: fakeTxID)
        try dm.close()

        // Reopen — recovery should replay WAL and restore both pages
        let store2 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let page0 = try store2.readPage(index: 0)
        let page1 = try store2.readPage(index: 1)
        XCTAssertEqual(page0, Data(repeating: 0xAA, count: 100))
        XCTAssertEqual(page1, Data(repeating: 0xBB, count: 100))
        store2.close()
    }

    /// Crash before commit record → staged writes are invisible on recovery.
    func testCrashBeforeCommitRecordDoesNotReplay() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

        // Write baseline page 0
        let store1 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        try store1.writePage(index: 0, plaintext: Data(repeating: 0x11, count: 100))
        store1.close()

        // Manually write an incomplete transaction to WAL (begin + write, NO commit)
        let dm = try DurabilityManager(walURL: walURL)
        let incompleteTxID = UUID()
        try dm.appendBegin(transactionID: incompleteTxID)
        // Encrypt a fake page buffer
        let fakeStore = try PageStore(fileURL: tempDir.appendingPathComponent("helper.db"), key: testKey, walMode: .unified)
        let encryptedBuffer = try fakeStore._encryptPageBuffer(plaintext: Data(repeating: 0xFF, count: 100))
        fakeStore.close()
        try dm.appendWrite(transactionID: incompleteTxID, pageIndex: 0, data: encryptedBuffer)
        // NO commit — simulating crash mid-transaction
        try dm.close()

        // Reopen — the incomplete transaction should be discarded
        let store2 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let page0 = try store2.readPage(index: 0)
        XCTAssertEqual(page0, Data(repeating: 0x11, count: 100),
            "Page should have original data — incomplete tx must not replay")
        store2.close()
    }

    /// Multi-page committed transaction: recovery replays ALL pages, not just first/last.
    func testMultiPageTransactionRecoveryReplaysAllPages() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

        // Write 5 pages in a single transaction
        let store1 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let tx = BlazeTransaction(store: store1)
        for i in 0..<5 {
            try tx.write(pageID: i, data: Data(repeating: UInt8(0x10 + i), count: 100))
        }
        try tx.commit()

        // Capture WAL before close
        let walEntries = try DurabilityManager.scanEntries(from: walURL)
        let writeEntries = walEntries.filter { $0.operation == .write }
        XCTAssertEqual(writeEntries.count, 5)
        store1.close()

        // Zero out ALL main file pages and re-inject the WAL
        let mainFH = try FileHandle(forUpdating: dbURL)
        for i in 0..<5 {
            mainFH.seek(toFileOffset: UInt64(i * 4096))
            mainFH.write(Data(repeating: 0x00, count: 4096))
        }
        try mainFH.synchronize()
        try mainFH.close()

        let dm = try DurabilityManager(walURL: walURL)
        let fakeTxID = UUID()
        try dm.appendBegin(transactionID: fakeTxID)
        for entry in writeEntries {
            try dm.appendWrite(transactionID: fakeTxID, pageIndex: entry.pageIndex, data: entry.payload)
        }
        try dm.appendCommit(transactionID: fakeTxID)
        try dm.close()

        // Recovery should restore ALL 5 pages
        let store2 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        for i in 0..<5 {
            let page = try store2.readPage(index: i)
            XCTAssertEqual(page, Data(repeating: UInt8(0x10 + i), count: 100),
                "Page \(i) should be recovered from WAL")
        }
        store2.close()
    }

    /// Transaction-level torn tail: committed tx + partial next tx in WAL.
    /// Recovery should replay the committed tx and ignore the partial one.
    func testTransactionLevelTornTail() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

        // Write a committed transaction
        let store1 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let tx1 = BlazeTransaction(store: store1)
        try tx1.write(pageID: 0, data: Data(repeating: 0xAA, count: 100))
        try tx1.commit()

        // Capture the committed WAL entries
        let committedEntries = try DurabilityManager.scanEntries(from: walURL)
        store1.close()

        // Zero page 0 in main file
        let mainFH = try FileHandle(forUpdating: dbURL)
        mainFH.seek(toFileOffset: 0)
        mainFH.write(Data(repeating: 0x00, count: 4096))
        try mainFH.synchronize()
        try mainFH.close()

        // Re-inject committed tx + add a partial (uncommitted) second tx
        let dm = try DurabilityManager(walURL: walURL)
        let tx1ID = UUID()
        try dm.appendBegin(transactionID: tx1ID)
        for entry in committedEntries.filter({ $0.operation == .write }) {
            try dm.appendWrite(transactionID: tx1ID, pageIndex: entry.pageIndex, data: entry.payload)
        }
        try dm.appendCommit(transactionID: tx1ID)

        // Partial second tx — begin + write, NO commit (simulates crash)
        let tx2ID = UUID()
        try dm.appendBegin(transactionID: tx2ID)
        let fakeBuffer = try PageStore(
            fileURL: tempDir.appendingPathComponent("helper2.db"), key: testKey, walMode: .unified
        )._encryptPageBuffer(plaintext: Data(repeating: 0xFF, count: 100))
        try dm.appendWrite(transactionID: tx2ID, pageIndex: 0, data: fakeBuffer)
        try dm.close()

        // Recovery: tx1 committed (replay), tx2 incomplete (discard)
        let store2 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let page0 = try store2.readPage(index: 0)
        XCTAssertEqual(page0, Data(repeating: 0xAA, count: 100),
            "Should recover committed tx, not the incomplete one")
        store2.close()
    }

    /// Checkpoint then reopen: data survives, WAL is clean.
    func testCheckpointThenReopenPreservesData() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

        let store1 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let tx = BlazeTransaction(store: store1)
        try tx.write(pageID: 0, data: Data(repeating: 0xAA, count: 100))
        try tx.write(pageID: 1, data: Data(repeating: 0xBB, count: 100))
        try tx.commit()

        // Explicit checkpoint
        try store1.checkpoint()

        // WAL should be empty after checkpoint
        let entries = try DurabilityManager.scanEntries(from: walURL)
        XCTAssertEqual(entries.count, 0, "WAL should be empty after checkpoint")

        store1.close()

        // Reopen — data should persist from main file (not WAL replay)
        let store2 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        XCTAssertEqual(try store2.readPage(index: 0), Data(repeating: 0xAA, count: 100))
        XCTAssertEqual(try store2.readPage(index: 1), Data(repeating: 0xBB, count: 100))
        store2.close()
    }
}
