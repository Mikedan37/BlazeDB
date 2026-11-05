//
//  UpdateOverflowPageReuseTests.swift
//  BlazeDB_Tier0 — legacy updates must return retired overflow pages to the free list.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class UpdateOverflowPageReuseTests: XCTestCase {
    private var dbURL: URL!
    private var password: String { "OverflowReuse-Pass_123!" }

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpdateOverflowReuse-\(UUID().uuidString).blazedb")
        try? FileManager.default.removeItem(at: dbURL)
    }

    override func tearDownWithError() throws {
        if let dbURL {
            let base = dbURL.deletingPathExtension()
            for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
                try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
            }
            try? FileManager.default.removeItem(at: dbURL)
        }
        try super.tearDownWithError()
    }

    private func openDB() throws -> BlazeDBClient {
        try BlazeDBClient(name: "overflow_reuse", fileURL: dbURL, password: password)
    }

    private func record(payloadBytes: Int, filler: Character) -> BlazeDataRecord {
        BlazeDataRecord([
            "payload": .string(String(repeating: filler, count: payloadBytes)),
        ])
    }

    func testUpdateOfOverflowRecordReusesRetiredPages() throws {
        var db = try openDB()
        let id = try db.insert(record(payloadBytes: 8_000, filler: "a"))
        let originalChain = try XCTUnwrap(db.collection.indexMap[id])
        XCTAssertGreaterThan(originalChain.count, 1, "payload should span an overflow chain")

        var updated = try XCTUnwrap(db.fetch(id: id))
        let rewritten = String(repeating: "b", count: 8_000)
        updated.storage["payload"] = .string(rewritten)
        try db.update(id: id, with: updated)

        let newChain = try XCTUnwrap(db.collection.indexMap[id])
        let retired = Set(originalChain.dropFirst()).subtracting(newChain)
        XCTAssertFalse(retired.isEmpty, "the previous overflow chain should be retired")
        XCTAssertTrue(retired.isSubset(of: Set(db.collection.cachedDeletedPages)))

        let follower = try db.insert(record(payloadBytes: 32, filler: "c"))
        let followerPages = try XCTUnwrap(db.collection.indexMap[follower])
        XCTAssertTrue(
            retired.contains(followerPages[0]),
            "next insert should reuse a retired overflow page, got \(followerPages)"
        )

        let again = try XCTUnwrap(db.fetch(id: id))
        XCTAssertEqual(again.storage["payload"]?.stringValue, rewritten)

        try db.persist()
        try db.close()

        db = try openDB()
        let reopened = try XCTUnwrap(db.fetch(id: id))
        XCTAssertEqual(reopened.storage["payload"]?.stringValue, rewritten)
        let followerAgain = try XCTUnwrap(db.fetch(id: follower))
        XCTAssertEqual(followerAgain.storage["payload"]?.stringValue, String(repeating: "c", count: 32))
        try db.close()
    }

    func testShrinkingOverflowRecordFreesUnusedPagesAndKeepsPayload() throws {
        var db = try openDB()
        let id = try db.insert(record(payloadBytes: 8_000, filler: "a"))
        let originalChain = try XCTUnwrap(db.collection.indexMap[id])
        XCTAssertGreaterThan(originalChain.count, 1)

        var updated = try XCTUnwrap(db.fetch(id: id))
        updated.storage["payload"] = .string("short")
        try db.update(id: id, with: updated)

        let newChain = try XCTUnwrap(db.collection.indexMap[id])
        XCTAssertEqual(newChain.count, 1)
        let retired = Set(originalChain.dropFirst())
        XCTAssertFalse(retired.isEmpty)
        XCTAssertTrue(retired.isSubset(of: Set(db.collection.cachedDeletedPages)))

        let fetched = try XCTUnwrap(db.fetch(id: id))
        XCTAssertEqual(fetched.storage["payload"]?.stringValue, "short")
        try db.persist()
        try db.close()

        db = try openDB()
        let reopened = try XCTUnwrap(db.fetch(id: id))
        XCTAssertEqual(reopened.storage["payload"]?.stringValue, "short")
        try db.close()
    }
}
