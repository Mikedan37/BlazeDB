//
//  RecordCacheLifecycleTests.swift
//  BlazeDBTests — #307: evict per-database record caches at teardown
//

import XCTest
import Foundation
@testable import BlazeDBCore

final class RecordCacheLifecycleTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordCacheLifecycle-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// #307: a fresh database recreated at the same path must not inherit a
    /// decoded record cached by the previous session.
    func testCloseAndRecreateSamePathDoesNotReturnStaleCachedPayload() throws {
        let databaseURL = tempDir.appendingPathComponent("record-cache.blazedb")
        let password = "RecordCacheLifecycle-Pass_123!"
        let recordID = UUID()

        let firstSession = try BlazeDBClient(
            name: "record-cache-first",
            fileURL: databaseURL,
            password: password
        )
        try firstSession.insert(
            BlazeDataRecord(["payload": .string("first-session")]),
            id: recordID
        )
        let firstPayload = try firstSession.fetch(id: recordID)?.storage["payload"]?.stringValue
        XCTAssertEqual(firstPayload, "first-session")
        try firstSession.close()

        let databaseBaseURL = databaseURL.deletingPathExtension()
        for extensionName in ["blazedb", "meta", "wal", "salt", "indexes"] {
            try? FileManager.default.removeItem(
                at: databaseBaseURL.appendingPathExtension(extensionName)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))

        let secondSession = try BlazeDBClient(
            name: "record-cache-second",
            fileURL: databaseURL,
            password: password
        )
        try secondSession.insert(
            BlazeDataRecord(["payload": .string("second-session")]),
            id: recordID
        )
        let secondPayload = try secondSession.fetch(id: recordID)?.storage["payload"]?.stringValue
        XCTAssertEqual(secondPayload, "second-session")
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
        try secondSession.close()
    }
}
