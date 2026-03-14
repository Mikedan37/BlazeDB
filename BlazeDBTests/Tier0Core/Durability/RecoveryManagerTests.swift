import XCTest
@testable import BlazeDBCore

final class RecoveryManagerTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-recovery-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // begin → write → commit → close → recovery replays committed write
    func testCommittedTransactionIsReplayed() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendWrite(transactionID: txID, pageIndex: 5, data: Data([0xDE, 0xAD]))
        _ = try dm.appendCommit(transactionID: txID)
        try dm.close()

        let result = try RecoveryManager.recover(walURL: walURL)

        XCTAssertEqual(result.committedWrites.count, 1)
        XCTAssertEqual(result.committedWrites[0].pageIndex, 5)
        XCTAssertEqual(result.committedWrites[0].payload, Data([0xDE, 0xAD]))
        XCTAssertEqual(result.uncommittedTransactions, 0)
    }

    // begin → write → close (no commit) → recovery discards
    func testUncommittedTransactionIsDiscarded() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendWrite(transactionID: txID, pageIndex: 5, data: Data([0xDE, 0xAD]))
        try dm.close()

        let result = try RecoveryManager.recover(walURL: walURL)

        XCTAssertEqual(result.committedWrites.count, 0)
        XCTAssertEqual(result.uncommittedTransactions, 1)
    }

    // Torn trailing entry after valid committed transaction → recovered
    func testTornTrailingEntryIgnored() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendWrite(transactionID: txID, pageIndex: 5, data: Data([0xDE, 0xAD]))
        _ = try dm.appendCommit(transactionID: txID)
        try dm.close()

        // Append garbage to simulate torn write of next entry
        var walData = try Data(contentsOf: walURL)
        walData.append(Data([0x57, 0x41, 0x4C, 0x56, 0x00, 0x00]))
        try walData.write(to: walURL)

        let result = try RecoveryManager.recover(walURL: walURL)

        XCTAssertEqual(result.committedWrites.count, 1)
        XCTAssertEqual(result.committedWrites[0].pageIndex, 5)
    }

    // Aborted transaction is discarded
    func testAbortedTransactionIsDiscarded() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendWrite(transactionID: txID, pageIndex: 5, data: Data([0xDE, 0xAD]))
        _ = try dm.appendAbort(transactionID: txID)
        try dm.close()

        let result = try RecoveryManager.recover(walURL: walURL)

        XCTAssertEqual(result.committedWrites.count, 0)
    }

    // Mid-log corruption → fails loudly
    func testMidLogCorruptionFailsLoudly() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let tx1 = UUID()
        _ = try dm.appendBegin(transactionID: tx1)
        _ = try dm.appendWrite(transactionID: tx1, pageIndex: 1, data: Data(repeating: 0x01, count: 64))
        _ = try dm.appendCommit(transactionID: tx1)

        let tx2 = UUID()
        _ = try dm.appendBegin(transactionID: tx2)
        _ = try dm.appendWrite(transactionID: tx2, pageIndex: 2, data: Data(repeating: 0x02, count: 64))
        _ = try dm.appendCommit(transactionID: tx2)
        try dm.close()

        // Corrupt middle of WAL (between tx1 and tx2)
        var walData = try Data(contentsOf: walURL)
        let entries = try DurabilityManager.scanEntries(from: walURL)
        var offset = 0
        for i in 0..<3 { offset += entries[i].serializedSize }
        walData[offset] = 0x00
        walData[offset + 1] = 0x00
        try walData.write(to: walURL)

        XCTAssertThrowsError(try RecoveryManager.recover(walURL: walURL))
    }

    // Mixed committed + uncommitted → only committed replayed, in LSN order
    func testMixedCommittedAndUncommitted() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        // TX1: committed
        let tx1 = UUID()
        _ = try dm.appendBegin(transactionID: tx1)
        _ = try dm.appendWrite(transactionID: tx1, pageIndex: 1, data: Data([0x01]))
        _ = try dm.appendCommit(transactionID: tx1)

        // TX2: uncommitted
        let tx2 = UUID()
        _ = try dm.appendBegin(transactionID: tx2)
        _ = try dm.appendWrite(transactionID: tx2, pageIndex: 2, data: Data([0x02]))

        // TX3: committed
        let tx3 = UUID()
        _ = try dm.appendBegin(transactionID: tx3)
        _ = try dm.appendWrite(transactionID: tx3, pageIndex: 3, data: Data([0x03]))
        _ = try dm.appendCommit(transactionID: tx3)

        try dm.close()

        let result = try RecoveryManager.recover(walURL: walURL)

        XCTAssertEqual(result.committedWrites.count, 2)
        XCTAssertEqual(result.uncommittedTransactions, 1)
        XCTAssertEqual(result.committedWrites[0].pageIndex, 1)
        XCTAssertEqual(result.committedWrites[1].pageIndex, 3)
    }

    // begin → delete → commit should be replayed as committed delete
    func testCommittedDeleteIsRecovered() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendDelete(transactionID: txID, pageIndex: 9)
        _ = try dm.appendCommit(transactionID: txID)
        try dm.close()

        let result = try RecoveryManager.recover(walURL: walURL)
        XCTAssertEqual(result.committedWrites.count, 1)
        XCTAssertEqual(result.committedWrites[0].operation, .delete)
        XCTAssertEqual(result.committedWrites[0].pageIndex, 9)
        XCTAssertTrue(result.committedWrites[0].payload.isEmpty)
    }

    // Empty WAL → no-op recovery
    func testEmptyWALRecovery() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        FileManager.default.createFile(atPath: walURL.path, contents: nil)

        let result = try RecoveryManager.recover(walURL: walURL)

        XCTAssertEqual(result.committedWrites.count, 0)
        XCTAssertEqual(result.uncommittedTransactions, 0)
        XCTAssertEqual(result.highestLSN, 0)
    }
}
