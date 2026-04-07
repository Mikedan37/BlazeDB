import Foundation
import XCTest
@testable import BlazeDBCore

final class WriteAheadLogBoundsTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wal-bounds-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

    func testAppendRejectsNegativePageIndex() throws {
        let walURL = tempDir.appendingPathComponent("negative-index.wal")
        let wal = try WriteAheadLog(logURL: walURL)
        defer { wal.close() }

        XCTAssertThrowsError(try wal.append(pageIndex: -1, data: Data(repeating: 0xAA, count: 16)))
    }

    func testAppendRejectsPageIndexAboveUInt32Max() throws {
        let walURL = tempDir.appendingPathComponent("large-index.wal")
        let wal = try WriteAheadLog(logURL: walURL)
        defer { wal.close() }

        let tooLarge = Int(UInt32.max) + 1
        XCTAssertThrowsError(try wal.append(pageIndex: tooLarge, data: Data(repeating: 0xBB, count: 16)))
    }
}
