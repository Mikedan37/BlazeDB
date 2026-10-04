import Foundation
import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import BlazeDBCore

/// A complete page record is not a committed transaction. Recovery applies a
/// group only when its commit record is intact and matches those pages.
final class WALTransactionAtomicityTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wal-atomicity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        PageStore._setCheckpointFsyncFailureForTests(false)
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCompletePageWithoutCommitIsNotRecovered() throws {
        let url = tempDir.appendingPathComponent("page-only.blazedb")
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key)
        try store.writePageUnsynchronized(index: 0, plaintext: Data("uncommitted".utf8))
        store.simulateCrashForTests()

        let recovered = try PageStore(fileURL: url, key: key)
        defer { recovered.close() }
        XCTAssertNil(try recovered.readPage(index: 0))
        XCTAssertGreaterThan(fileSize(walURL(url)), 0, "The complete page record can be on disk")
    }

    func testTornCommitMarkerIsNotRecovered() throws {
        let url = tempDir.appendingPathComponent("torn-commit.blazedb")
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key)
        try store.writePageUnsynchronized(index: 0, plaintext: Data("needs-commit".utf8))
        try store.synchronize()
        store.simulateCrashForTests()
        try truncateTail(bytes: 4, of: walURL(url))

        let recovered = try PageStore(fileURL: url, key: key)
        defer { recovered.close() }
        XCTAssertNil(try recovered.readPage(index: 0))
    }

    func testTwoPageTransactionWithOnlyFirstPageCompleteIsDiscarded() throws {
        let url = tempDir.appendingPathComponent("partial-group.blazedb")
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key)
        try store.writePageUnsynchronized(index: 0, plaintext: Data("first".utf8))
        try store.writePageUnsynchronized(index: 1, plaintext: Data("second".utf8))
        store.simulateCrashForTests()
        try truncateTail(bytes: 100, of: walURL(url))

        let recovered = try PageStore(fileURL: url, key: key)
        defer { recovered.close() }
        XCTAssertNil(try recovered.readPage(index: 0))
        XCTAssertNil(try recovered.readPage(index: 1))
    }

    func testTwoCompletePagesWithoutCommitAreDiscarded() throws {
        let url = tempDir.appendingPathComponent("no-commit.blazedb")
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key)
        try store.writePageUnsynchronized(index: 0, plaintext: Data("first".utf8))
        try store.writePageUnsynchronized(index: 1, plaintext: Data("second".utf8))
        store.simulateCrashForTests()

        let recovered = try PageStore(fileURL: url, key: key)
        defer { recovered.close() }
        XCTAssertNil(try recovered.readPage(index: 0))
        XCTAssertNil(try recovered.readPage(index: 1))
    }

    func testCommittedTwoPageTransactionRecoversBothPages() throws {
        let url = tempDir.appendingPathComponent("both.blazedb")
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key)
        try store.writePageUnsynchronized(index: 0, plaintext: Data("first".utf8))
        try store.writePageUnsynchronized(index: 1, plaintext: Data("second".utf8))
        try store.synchronize()
        store.simulateCrashForTests()

        let recovered = try PageStore(fileURL: url, key: key)
        defer { recovered.close() }
        XCTAssertEqual(try recovered.readPage(index: 0), Data("first".utf8))
        XCTAssertEqual(try recovered.readPage(index: 1), Data("second".utf8))
    }

    func testIncompleteTransactionAfterCommitIsNotRecovered() throws {
        let url = tempDir.appendingPathComponent("prefix.blazedb")
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key)
        try store.writePageUnsynchronized(index: 0, plaintext: Data("committed".utf8))
        try store.synchronize()
        try store.writePageUnsynchronized(index: 1, plaintext: Data("open".utf8))
        store.simulateCrashForTests()

        let recovered = try PageStore(fileURL: url, key: key)
        defer { recovered.close() }
        XCTAssertEqual(try recovered.readPage(index: 0), Data("committed".utf8))
        XCTAssertNil(try recovered.readPage(index: 1))
    }

    func testRolledBackPageIsNotCommittedByTheNextTransaction() throws {
        let url = tempDir.appendingPathComponent("rollback.blazedb")
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key)
        try store.writePageUnsynchronized(index: 0, plaintext: Data("aborted".utf8))
        store.abortUncommittedWALGroup()
        try store.writePageUnsynchronized(index: 1, plaintext: Data("kept".utf8))
        try store.synchronize()
        store.simulateCrashForTests()

        let recovered = try PageStore(fileURL: url, key: key)
        defer { recovered.close() }
        XCTAssertNil(try recovered.readPage(index: 0))
        XCTAssertEqual(try recovered.readPage(index: 1), Data("kept".utf8))
    }

    func testCheckpointFsyncFailureKeepsCommittedWALGroup() throws {
        let url = tempDir.appendingPathComponent("checkpoint.blazedb")
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key)
        try store.writePageUnsynchronized(index: 0, plaintext: Data("one".utf8))
        try store.writePageUnsynchronized(index: 1, plaintext: Data("two".utf8))
        try store.synchronize()

        PageStore._setCheckpointFsyncFailureForTests(true)
        XCTAssertThrowsError(try store.checkpoint())
        PageStore._setCheckpointFsyncFailureForTests(false)
        XCTAssertGreaterThan(fileSize(walURL(url)), 0)
        store.simulateCrashForTests()

        let recovered = try PageStore(fileURL: url, key: key)
        defer { recovered.close() }
        XCTAssertEqual(try recovered.readPage(index: 0), Data("one".utf8))
        XCTAssertEqual(try recovered.readPage(index: 1), Data("two".utf8))
    }

    private func walURL(_ url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("wal")
    }

    private func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    private func truncateTail(bytes: Int, of url: URL) throws {
        let size = fileSize(url)
        let handle = try FileHandle(forUpdating: url)
        try handle.truncate(atOffset: UInt64(size - bytes))
        try handle.close()
    }
}
