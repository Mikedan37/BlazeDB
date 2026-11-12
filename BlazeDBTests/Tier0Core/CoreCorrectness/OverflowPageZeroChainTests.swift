//
//  OverflowPageZeroChainTests.swift
//  BlazeDB_Tier0 — overflow chains must survive when page 0 is the next free page.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class OverflowPageZeroChainTests: XCTestCase {
    private var dbURL: URL!
    private var password: String { "OverflowPageZero-Pass_123!" }

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverflowPageZero-\(UUID().uuidString).blazedb")
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
        try BlazeDBClient(name: "overflow_page_zero", fileURL: dbURL, password: password)
    }

    /// Delete every other row first, then the row stored on page 0, so page 0 is the
    /// last free page. The next large insert takes a non-zero main page and then
    /// has to place an overflow page at index 0.
    func testLargeInsertRoundTripsWhenPageZeroIsLastFreePage() throws {
        var db = try openDB()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        var ids: [UUID] = []
        for index in 0..<3 {
            let id = try db.insert(BlazeDataRecord([
                "n": .int(index),
                "createdAt": .date(createdAt),
            ]))
            ids.append(id)
        }
        // Checkpoint before reuse so earlier page images are not still in the WAL.
        try db.persist()

        let pagesByID = db.collection.queue.sync { db.collection.indexMap }
        let pageZeroID = try XCTUnwrap(pagesByID.first(where: { $0.value.first == 0 })?.key)
        for id in ids where id != pageZeroID {
            try db.delete(id: id)
        }
        try db.delete(id: pageZeroID)

        let freePages = db.collection.queue.sync { db.collection.cachedDeletedPages }
        XCTAssertGreaterThanOrEqual(freePages.count, 2)
        XCTAssertNotEqual(freePages.first, 0)
        XCTAssertEqual(freePages.last, 0)

        // Main page capacity is 4014 bytes and each overflow page holds 4052.
        // 10_000 encoded bytes need two overflow pages, so the second one is page 0
        // when the free list ends in 0.
        let payload = "HEAD" + String(repeating: "z", count: 10_000) + "TAIL"
        let recordID = try db.insert(BlazeDataRecord([
            "payload": .string(payload),
            "createdAt": .date(createdAt),
        ]))
        let chain = db.collection.queue.sync { db.collection.indexMap[recordID] ?? [] }
        XCTAssertGreaterThan(chain.count, 1)
        XCTAssertFalse(chain.contains(0), "page 0 cannot be an overflow page, chain \(chain)")
        let fetched = try XCTUnwrap(db.fetch(id: recordID))
        XCTAssertEqual(fetched.storage["payload"]?.stringValue, payload)
        try db.persist()
        try db.close()

        db = try openDB()
        let reopened = try XCTUnwrap(db.fetch(id: recordID))
        XCTAssertEqual(reopened.storage["payload"]?.stringValue, payload)
        try db.close()
    }

    /// Reused pages are not allocated in numeric order. The catalog must keep
    /// that order: the first page is the record head, and later pages are the
    /// overflow chain.
    func testReopenKeepsOverflowChainWhenPageNumbersAreOutOfOrder() throws {
        var db = try openDB()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<3 {
            _ = try db.insert(BlazeDataRecord([
                "n": .int(index),
                "createdAt": .date(createdAt),
            ]))
        }
        try db.persist()

        let pagesByID = db.collection.queue.sync { db.collection.indexMap }
        let highestFirst = pagesByID.sorted { ($0.value.first ?? -1) > ($1.value.first ?? -1) }
        XCTAssertGreaterThanOrEqual(highestFirst.count, 3)
        try db.delete(id: highestFirst[0].key)
        try db.delete(id: highestFirst[1].key)

        let payload = "HEAD" + String(repeating: "q", count: 5_000) + "TAIL"
        let recordID = try db.insert(BlazeDataRecord([
            "payload": .string(payload),
            "createdAt": .date(createdAt),
        ]))
        let chain = db.collection.queue.sync { db.collection.indexMap[recordID] ?? [] }
        XCTAssertGreaterThanOrEqual(chain.count, 2)
        XCTAssertGreaterThan(chain[0], chain[1], "head page should outrank the reused overflow page, chain \(chain)")

        let fetched = try XCTUnwrap(db.fetch(id: recordID))
        XCTAssertEqual(fetched.storage["payload"]?.stringValue, payload)
        try db.persist()
        try db.close()

        db = try openDB()
        let reopened = try XCTUnwrap(db.fetch(id: recordID))
        XCTAssertEqual(reopened.storage["payload"]?.stringValue, payload)
        XCTAssertNotNil(try db.fetch(id: highestFirst[2].key))
        try db.close()
    }
}
