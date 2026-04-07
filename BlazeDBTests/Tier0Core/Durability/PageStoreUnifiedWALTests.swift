import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import BlazeDBCore

/// Tests for PageStore with walMode: .unified (DurabilityManager-backed WAL).
/// These mirror the existing legacy WAL tests to confirm behavioral parity.
final class PageStoreUnifiedWALTests: XCTestCase {

    var tempDir: URL!
    let testKey = SymmetricKey(size: .bits256)

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-unified-wal-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Basic write/read

    func testWriteAndReadBackUnifiedMode() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let store = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)

        let plaintext = Data(repeating: 0xAA, count: 100)
        try store.writePage(index: 0, plaintext: plaintext)

        let readBack = try store.readPage(index: 0)
        XCTAssertEqual(readBack, plaintext)

        store.close()
    }

    // MARK: - WAL entries are produced

    func testUnifiedModeProducesWALEntries() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")
        let store = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)

        let plaintext = Data(repeating: 0xBB, count: 100)
        try store.writePage(index: 3, plaintext: plaintext)

        // WAL should contain begin + write + commit (auto-transaction)
        let entries = try DurabilityManager.scanEntries(from: walURL)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].operation, .begin)
        XCTAssertEqual(entries[1].operation, .write)
        XCTAssertEqual(entries[1].pageIndex, 3)
        XCTAssertEqual(entries[2].operation, .commit)

        store.close()
    }

    // MARK: - Recovery after crash

    func testUnifiedModeRecoveryAfterCrash() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

        // Write a page and close normally
        let store1 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let plaintext = Data(repeating: 0xCC, count: 100)
        try store1.writePage(index: 2, plaintext: plaintext)
        store1.close()

        // WAL should be cleared after clean close (checkpoint)
        let entriesAfterClose = try DurabilityManager.scanEntries(from: walURL)
        XCTAssertEqual(entriesAfterClose.count, 0)

        // Reopen — data should still be readable
        let store2 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let readBack = try store2.readPage(index: 2)
        XCTAssertEqual(readBack, plaintext)
        store2.close()
    }

    func testUnifiedModeRecoveryWithDirtyWAL() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

        // Write a page using unified mode
        let store1 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let plaintext = Data(repeating: 0xDD, count: 100)
        try store1.writePage(index: 1, plaintext: plaintext)

        // Simulate crash: WAL has entries but main file might not be fsynced.
        // Read the WAL entries before "crash"
        let walEntries = try DurabilityManager.scanEntries(from: walURL)
        XCTAssertGreaterThan(walEntries.count, 0, "WAL should have entries before crash")

        // Corrupt the main file page to simulate unflushed write
        // (zero out the page in the main file)
        let mainFH = try FileHandle(forUpdating: dbURL)
        let pageOffset = UInt64(1 * 4096)
        mainFH.seek(toFileOffset: pageOffset)
        mainFH.write(Data(repeating: 0x00, count: 4096))
        try mainFH.synchronize()
        try mainFH.close()

        // Force-close without checkpoint (simulating crash — bypass normal close)
        // We can't easily do this with the current API, so we just close normally
        // and then manually re-write the WAL entries to simulate a dirty state.
        store1.close()

        // Write WAL entries back (simulating that checkpoint didn't happen)
        let dm = try DurabilityManager(walURL: walURL)
        let autoTxID = UUID()
        try dm.appendBegin(transactionID: autoTxID)
        // Use the encrypted page buffer from the original WAL entry
        let writeEntry = walEntries.first(where: { $0.operation == .write })!
        try dm.appendWrite(transactionID: autoTxID, pageIndex: writeEntry.pageIndex, data: writeEntry.payload)
        try dm.appendCommit(transactionID: autoTxID)
        try dm.close()

        // Reopen — recovery should replay the WAL and restore the page
        let store2 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let readBack = try store2.readPage(index: 1)
        XCTAssertEqual(readBack, plaintext)
        store2.close()
    }

    func testUnifiedRecoveryReplaysCommittedDeleteAsZeroedPage() throws {
        let dbURL = tempDir.appendingPathComponent("test-delete.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

        let store1 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        try store1.writePage(index: 4, plaintext: Data(repeating: 0xAB, count: 100))
        store1.close()

        let dm = try DurabilityManager(walURL: walURL)
        let txID = UUID()
        try dm.appendBegin(transactionID: txID)
        try dm.appendDelete(transactionID: txID, pageIndex: 4)
        try dm.appendCommit(transactionID: txID)
        try dm.close()

        let store2 = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        let readBack = try store2.readPage(index: 4)
        XCTAssertNil(readBack, "Recovered delete should zero page and read as nil")
        store2.close()
    }

    // MARK: - Multiple writes

    func testMultipleWritesUnifiedMode() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let store = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)

        for i in 0..<5 {
            let plaintext = Data(repeating: UInt8(i), count: 100)
            try store.writePage(index: i, plaintext: plaintext)
        }

        // Read them all back
        for i in 0..<5 {
            let expected = Data(repeating: UInt8(i), count: 100)
            let readBack = try store.readPage(index: i)
            XCTAssertEqual(readBack, expected, "Page \(i) mismatch")
        }

        store.close()
    }

    // MARK: - Checkpoint

    func testCheckpointClearsWALUnifiedMode() throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")
        let store = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)

        let plaintext = Data(repeating: 0xEE, count: 100)
        try store.writePage(index: 0, plaintext: plaintext)

        // WAL should have entries
        var entries = try DurabilityManager.scanEntries(from: walURL)
        XCTAssertGreaterThan(entries.count, 0)

        // Checkpoint should clear WAL
        try store.checkpoint()
        entries = try DurabilityManager.scanEntries(from: walURL)
        XCTAssertEqual(entries.count, 0)

        // Data should still be readable
        let readBack = try store.readPage(index: 0)
        XCTAssertEqual(readBack, plaintext)

        store.close()
    }

    // MARK: - Legacy mode still works

    func testLegacyModeUnaffected() throws {
        let dbURL = tempDir.appendingPathComponent("test-legacy.db")
        let store = try PageStore(fileURL: dbURL, key: testKey, walMode: .legacy)

        let plaintext = Data(repeating: 0xFF, count: 100)
        try store.writePage(index: 0, plaintext: plaintext)

        let readBack = try store.readPage(index: 0)
        XCTAssertEqual(readBack, plaintext)

        store.close()
    }

    func testNextAvailablePageIndexThrowsOnStatFailure() throws {
        let dbURL = tempDir.appendingPathComponent("test-next-index-failure.db")
        let store = try PageStore(fileURL: dbURL, key: testKey, walMode: .unified)
        try store.writePage(index: 0, plaintext: Data(repeating: 0x11, count: 64))

        // Closing invalidates the backing file descriptor; nextAvailablePageIndex
        // must surface the failure instead of returning page index 0.
        store.close()

        XCTAssertThrowsError(try store.nextAvailablePageIndex())
    }
}
