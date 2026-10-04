import CryptoKit
import Foundation
import XCTest
@testable import BlazeDBCore

/// Commit is durable when the WAL is synced. The main database file is updated
/// at checkpoint, close, or recovery — not on the commit path.
final class WALCommitBoundaryTests: XCTestCase {
    private var tempDir: URL!
    private let password = "WALCommitBoundary-2026!"

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wal-commit-boundary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        PageStore._setCheckpointFsyncFailureForTests(false)
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInsertCommitCloseReopen() throws {
        let url = tempDir.appendingPathComponent("insert.blazedb")
        let db = try openMVCC(url)
        let id = try db.insert(BlazeDataRecord(["title": .string("saved")]))
        try db.persist()
        try db.close()

        let reopened = try openMVCC(url)
        defer { try? reopened.close() }
        XCTAssertEqual(try reopened.fetch(id: id)?.storage["title"]?.stringValue, "saved")
    }

    func testUpdateCommitCloseReopen() throws {
        let url = tempDir.appendingPathComponent("update.blazedb")
        let db = try openMVCC(url)
        let id = try db.insert(BlazeDataRecord(["title": .string("first")]))
        try db.update(id: id, with: BlazeDataRecord(["title": .string("second")]))
        try db.persist()
        try db.close()

        let reopened = try openMVCC(url)
        defer { try? reopened.close() }
        XCTAssertEqual(try reopened.fetch(id: id)?.storage["title"]?.stringValue, "second")
    }

    func testSeveralCommitsStayInWALUntilCheckpoint() throws {
        let url = tempDir.appendingPathComponent("staged.blazedb")
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key)
        let payloads = ["one", "two", "three"]
        for (index, text) in payloads.enumerated() {
            try store.writePageUnsynchronized(index: index, plaintext: Data(text.utf8))
            try store.synchronize()
        }

        XCTAssertEqual(fileSize(url), 0, "Commit must not write the main database file")
        XCTAssertGreaterThan(fileSize(walURL(url)), 0)
        for (index, text) in payloads.enumerated() {
            XCTAssertEqual(try store.readPage(index: index), Data(text.utf8))
        }

        store.simulateCrashForTests()
        let recovered = try PageStore(fileURL: url, key: key)
        defer { recovered.close() }
        for (index, text) in payloads.enumerated() {
            XCTAssertEqual(try recovered.readPage(index: index), Data(text.utf8))
        }
        XCTAssertGreaterThan(fileSize(url), 0, "Recovery must apply the WAL onto the database file")
        XCTAssertEqual(fileSize(walURL(url)), 0, "Recovery clears the WAL only after the database file is synced")
    }

    func testCheckpointThenReopen() throws {
        let url = tempDir.appendingPathComponent("checkpoint.blazedb")
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key)
        try store.writePageUnsynchronized(index: 0, plaintext: Data("checkpointed".utf8))
        try store.synchronize()
        XCTAssertEqual(fileSize(url), 0)

        try store.checkpoint()
        XCTAssertEqual(fileSize(walURL(url)), 0, "WAL is discarded only after the database file is durable")
        XCTAssertGreaterThan(fileSize(url), 0)
        XCTAssertEqual(try store.readPage(index: 0), Data("checkpointed".utf8))
        store.simulateCrashForTests()

        let reopened = try PageStore(fileURL: url, key: key)
        defer { reopened.close() }
        XCTAssertEqual(try reopened.readPage(index: 0), Data("checkpointed".utf8))
    }

    func testCheckpointFsyncFailureDoesNotDiscardWAL() throws {
        let url = tempDir.appendingPathComponent("checkpoint-fail.blazedb")
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key)
        try store.writePageUnsynchronized(index: 0, plaintext: Data("keep-wal".utf8))
        try store.synchronize()

        PageStore._setCheckpointFsyncFailureForTests(true)
        XCTAssertThrowsError(try store.checkpoint())
        PageStore._setCheckpointFsyncFailureForTests(false)
        XCTAssertGreaterThan(fileSize(walURL(url)), 0, "WAL must survive a failed database-file sync")

        store.simulateCrashForTests()
        let recovered = try PageStore(fileURL: url, key: key)
        defer { recovered.close() }
        XCTAssertEqual(try recovered.readPage(index: 0), Data("keep-wal".utf8))
    }

    func testTornWALTailIsNotRecoveredAsACommittedPage() throws {
        let url = tempDir.appendingPathComponent("torn.blazedb")
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key)
        try store.writePageUnsynchronized(index: 0, plaintext: Data("complete".utf8))
        try store.synchronize()
        store.simulateCrashForTests()

        let handle = try FileHandle(forWritingTo: walURL(url))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("PARTIAL".utf8))
        try handle.close()

        let recovered = try PageStore(fileURL: url, key: key)
        defer { recovered.close() }
        XCTAssertEqual(try recovered.readPage(index: 0), Data("complete".utf8))
        XCTAssertNil(try recovered.readPage(index: 1))
    }

    private func openMVCC(_ url: URL) throws -> BlazeDBClient {
        let db = try BlazeDBClient(name: "wal-boundary", fileURL: url, password: password)
        db.setMVCCEnabled(true)
        return db
    }

    private func walURL(_ url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("wal")
    }

    private func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }
}
