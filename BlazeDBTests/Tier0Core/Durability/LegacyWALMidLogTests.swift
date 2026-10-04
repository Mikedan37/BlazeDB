import Foundation
import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import BlazeDBCore

/// A CRC failure with valid entries after it is mid-log corruption, not a torn tail.
/// Replay must fail closed and PageStore must not truncate the unread WAL.
final class LegacyWALMidLogTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-wal-midlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

    func testReplayThrowsWhenCRCFailureHasBytesAfterIt() throws {
        let walURL = tempDir.appendingPathComponent("mid-crc.wal")
        let payloads = [
            Data(repeating: 0x11, count: 32),
            Data(repeating: 0x22, count: 32),
            Data(repeating: 0x33, count: 32)
        ]
        try writeEntries(payloads, to: walURL)
        // Each append is a page record plus a commit record. Flip the second page payload.
        let stride = 16 + 32 + WriteAheadLog.commitRecordSize
        try flipByte(at: stride + 16, in: walURL)

        let wal = try WriteAheadLog(logURL: walURL)
        defer { wal.close() }
        XCTAssertThrowsError(try wal.replay()) { error in
            guard case WALError.midLogCorruption = error else {
                XCTFail("Expected midLogCorruption, got: \(error)")
                return
            }
        }
    }

    func testReplayStopsOnFinalCRCFailureWithoutATail() throws {
        let walURL = tempDir.appendingPathComponent("tail-crc.wal")
        try writeEntries([
            Data(repeating: 0x11, count: 16),
            Data(repeating: 0x22, count: 16)
        ], to: walURL)
        let size = try fileSize(walURL)
        try flipByte(at: size - 1, in: walURL)

        let wal = try WriteAheadLog(logURL: walURL)
        defer { wal.close() }
        let entries = try wal.replay()
        XCTAssertEqual(entries.count, 1, "A bad final entry is a stop, not mid-log corruption")
        XCTAssertEqual(entries[0].pageIndex, 0)
    }

    func testPageStoreDoesNotClearWALWhenMidLogCRCHasAValidTail() throws {
        let storeURL = tempDir.appendingPathComponent("mid-crc.blazedb")
        let walURL = storeURL.deletingPathExtension().appendingPathExtension("wal")
        let page = 4096
        try writeEntries([
            Data(repeating: 0xA1, count: page),
            Data(repeating: 0xA2, count: page),
            Data(repeating: 0xA3, count: page)
        ], to: walURL)
        let stride = 16 + page + WriteAheadLog.commitRecordSize
        try flipByte(at: stride + 16, in: walURL)

        let sizeBefore = try fileSize(walURL)
        let tailByteBefore = try byte(at: (2 * stride) + 16, in: walURL)
        XCTAssertEqual(tailByteBefore, 0xA3)

        let wal = try WriteAheadLog(logURL: walURL)
        XCTAssertThrowsError(try wal.replay())
        wal.close()

        XCTAssertThrowsError(
            try PageStore(fileURL: storeURL, key: SymmetricKey(size: .bits256))
        )

        XCTAssertEqual(try fileSize(walURL), sizeBefore, "WAL must not be cleared after a mid-log CRC failure")
        XCTAssertEqual(try byte(at: (2 * stride) + 16, in: walURL), 0xA3, "Valid tail entry must still be on disk")
    }

    private func writeEntries(_ payloads: [Data], to walURL: URL) throws {
        let wal = try WriteAheadLog(logURL: walURL)
        for (index, payload) in payloads.enumerated() {
            try wal.append(pageIndex: index, data: payload)
        }
        wal.close()
    }

    private func flipByte(at offset: Int, in url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        try handle.seek(toOffset: UInt64(offset))
        let original = try handle.read(upToCount: 1) ?? Data()
        XCTAssertEqual(original.count, 1)
        try handle.seek(toOffset: UInt64(offset))
        var flipped = original
        flipped[0] ^= 0xFF
        try handle.write(contentsOf: flipped)
        try handle.close()
    }

    private func fileSize(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.intValue ?? 0
    }

    private func byte(at offset: Int, in url: URL) throws -> UInt8 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: 1) ?? Data()
        return data.first ?? 0
    }
}
