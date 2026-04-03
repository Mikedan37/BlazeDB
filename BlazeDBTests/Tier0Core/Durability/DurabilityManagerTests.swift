import XCTest
@testable import BlazeDBCore

final class DurabilityManagerTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-dm-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testAppendAndReadBack() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        let lsn1 = try dm.appendBegin(transactionID: txID)
        let lsn2 = try dm.appendWrite(transactionID: txID, pageIndex: 5, data: Data([0xAA, 0xBB]))
        let lsn3 = try dm.appendCommit(transactionID: txID)

        XCTAssertEqual(lsn1, 1)
        XCTAssertEqual(lsn2, 2)
        XCTAssertEqual(lsn3, 3)
        XCTAssertEqual(dm.currentLSN, 3)

        let entries = try dm.readAllEntries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].operation, .begin)
        XCTAssertEqual(entries[1].operation, .write)
        XCTAssertEqual(entries[1].pageIndex, 5)
        XCTAssertEqual(entries[2].operation, .commit)

        try dm.close()
    }

    func testLSNMonotonicallyIncreases() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        var lastLSN: UInt64 = 0
        for _ in 0..<100 {
            let lsn = try dm.appendWrite(transactionID: txID, pageIndex: 0, data: Data([0x01]))
            XCTAssertGreaterThan(lsn, lastLSN)
            lastLSN = lsn
        }
        try dm.close()
    }

    func testAbortWritesAbortRecord() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendWrite(transactionID: txID, pageIndex: 0, data: Data([0x01]))
        _ = try dm.appendAbort(transactionID: txID)

        let entries = try dm.readAllEntries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[2].operation, .abort)
        try dm.close()
    }

    func testCheckpointTruncatesWAL() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendWrite(transactionID: txID, pageIndex: 0, data: Data([0x01]))
        _ = try dm.appendCommit(transactionID: txID)

        XCTAssertEqual(dm.currentLSN, 3)

        try dm.checkpoint()

        // WAL should be empty after checkpoint
        let entries = try dm.readAllEntries()
        XCTAssertEqual(entries.count, 0)

        // But LSN should still be 3 (not reset)
        XCTAssertEqual(dm.currentLSN, 3)
        XCTAssertEqual(dm.lastCheckpointLSN, 3)

        try dm.close()
    }

    func testLSNRecoveredOnReopen() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")

        // Write some entries and close
        let dm1 = try DurabilityManager(walURL: walURL)
        let txID = UUID()
        _ = try dm1.appendBegin(transactionID: txID)
        _ = try dm1.appendWrite(transactionID: txID, pageIndex: 0, data: Data([0x01]))
        _ = try dm1.appendCommit(transactionID: txID)
        try dm1.close()

        // Reopen — LSN should continue from where it left off
        let dm2 = try DurabilityManager(walURL: walURL)
        XCTAssertEqual(dm2.currentLSN, 3)

        let txID2 = UUID()
        let lsn4 = try dm2.appendBegin(transactionID: txID2)
        XCTAssertEqual(lsn4, 4) // Continues from 3
        try dm2.close()
    }

    func testCheckpointLSNRecoveredOnReopen() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")

        let dm1 = try DurabilityManager(walURL: walURL)
        let txID = UUID()
        _ = try dm1.appendBegin(transactionID: txID)
        _ = try dm1.appendCommit(transactionID: txID)
        try dm1.checkpoint()
        try dm1.close()

        // Reopen — checkpoint LSN should be recovered from .wal-meta file
        let dm2 = try DurabilityManager(walURL: walURL)
        XCTAssertEqual(dm2.lastCheckpointLSN, 2)
        try dm2.close()
    }

    func testScanDetectsMidLogCorruption() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        // Write two committed transactions
        let tx1 = UUID()
        _ = try dm.appendBegin(transactionID: tx1)
        _ = try dm.appendWrite(transactionID: tx1, pageIndex: 1, data: Data(repeating: 0x01, count: 64))
        _ = try dm.appendCommit(transactionID: tx1)

        let tx2 = UUID()
        _ = try dm.appendBegin(transactionID: tx2)
        _ = try dm.appendWrite(transactionID: tx2, pageIndex: 2, data: Data(repeating: 0x02, count: 64))
        _ = try dm.appendCommit(transactionID: tx2)
        try dm.close()

        // Corrupt bytes in the MIDDLE (between tx1 and tx2)
        var walData = try Data(contentsOf: walURL)
        let entries = try DurabilityManager.scanEntries(from: walURL)
        var offset = 0
        for i in 0..<3 { offset += entries[i].serializedSize }
        // Zero out magic of 4th entry
        walData[offset] = 0x00
        walData[offset + 1] = 0x00
        try walData.write(to: walURL)

        // Should fail loudly — not silently ignore
        XCTAssertThrowsError(try DurabilityManager.scanEntries(from: walURL)) { error in
            guard case WALError.midLogCorruption = error else {
                XCTFail("Expected midLogCorruption, got: \(error)")
                return
            }
        }
    }

    func testScanToleratesTornTail() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendCommit(transactionID: txID)
        try dm.close()

        // Append a few garbage bytes (torn trailing write)
        var walData = try Data(contentsOf: walURL)
        walData.append(Data([0x57, 0x41, 0x4C, 0x56, 0x00, 0x00]))
        try walData.write(to: walURL)

        // Should succeed — torn tail is ignored
        let entries = try DurabilityManager.scanEntries(from: walURL)
        XCTAssertEqual(entries.count, 2)
    }
}
