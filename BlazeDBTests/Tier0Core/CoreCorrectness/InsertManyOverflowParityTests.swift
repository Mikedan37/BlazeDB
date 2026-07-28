//
//  InsertManyOverflowParityTests.swift
//  BlazeDB_Tier0 — insertMany must accept overflow-sized records that insert() accepts.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class InsertManyOverflowParityTests: XCTestCase {
    private var dbURL: URL!
    private var password: String { "OverflowParity-Pass_123!" }

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InsertManyOverflow-\(UUID().uuidString).blazedb")
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
        try BlazeDBClient(name: "overflow_parity", fileURL: dbURL, password: password)
    }

    private func record(index: Int, payloadBytes: Int, filler: Character = "x") -> BlazeDataRecord {
        BlazeDataRecord([
            "index": .int(index),
            "payload": .string(String(repeating: filler, count: payloadBytes)),
        ])
    }

    func testInsertMany_singleRecordOver4KiB_roundTripsAndSurvivesReopen() throws {
        let payloadBytes = 5_000
        var db = try openDB()
        let ids = try db.insertMany([record(index: 0, payloadBytes: payloadBytes)])
        XCTAssertEqual(ids.count, 1)
        try db.persist()

        let fetched = try XCTUnwrap(db.fetch(id: ids[0]))
        XCTAssertEqual(fetched.storage["payload"]?.stringValue?.count, payloadBytes)
        try db.close()

        db = try openDB()
        let again = try XCTUnwrap(db.fetch(id: ids[0]))
        XCTAssertEqual(again.storage["payload"]?.stringValue?.count, payloadBytes)
        XCTAssertEqual(again.storage["index"]?.intValue, 0)
        try db.close()
    }

    func testInsertMany_oneMegabyte_matchesInsertParityAndReopen() throws {
        let payloadBytes = 1_048_576
        var db = try openDB()

        let insertID = try db.insert(record(index: 1, payloadBytes: payloadBytes, filler: "a"))
        let manyIDs = try db.insertMany([record(index: 2, payloadBytes: payloadBytes, filler: "b")])
        XCTAssertEqual(manyIDs.count, 1)
        try db.persist()
        try db.close()

        db = try openDB()
        let viaInsert = try XCTUnwrap(db.fetch(id: insertID))
        let viaMany = try XCTUnwrap(db.fetch(id: manyIDs[0]))
        XCTAssertEqual(viaInsert.storage["payload"]?.stringValue?.count, payloadBytes)
        XCTAssertEqual(viaMany.storage["payload"]?.stringValue?.count, payloadBytes)
        XCTAssertEqual(viaInsert.storage["payload"]?.stringValue?.first, "a")
        XCTAssertEqual(viaMany.storage["payload"]?.stringValue?.first, "b")
        try db.close()
    }

    func testInsertMany_mixedSmallAndOverflow_roundTripsAfterReopen() throws {
        var db = try openDB()
        let records = [
            record(index: 0, payloadBytes: 64, filler: "s"),
            record(index: 1, payloadBytes: 8_192, filler: "m"),
            record(index: 2, payloadBytes: 128, filler: "t"),
            record(index: 3, payloadBytes: 65_536, filler: "L"),
        ]
        let ids = try db.insertMany(records)
        XCTAssertEqual(ids.count, 4)
        try db.persist()
        try db.close()

        db = try openDB()
        for (i, id) in ids.enumerated() {
            let fetched = try XCTUnwrap(db.fetch(id: id))
            XCTAssertEqual(fetched.storage["index"]?.intValue, i)
            XCTAssertEqual(
                fetched.storage["payload"]?.stringValue?.count,
                records[i].storage["payload"]?.stringValue?.count
            )
        }
        try db.close()
    }

    func testInsertMany_overflowRecord_canUpdateAndDeleteAfterReopen() throws {
        let payloadBytes = 12_000
        var db = try openDB()
        let ids = try db.insertMany([record(index: 7, payloadBytes: payloadBytes, filler: "u")])
        let id = try XCTUnwrap(ids.first)
        try db.persist()
        try db.close()

        db = try openDB()
        try db.update(
            id: id,
            with: BlazeDataRecord([
                "index": .int(7),
                "payload": .string(String(repeating: "v", count: payloadBytes)),
                "status": .string("closed"),
            ])
        )
        try db.persist()
        try db.close()

        db = try openDB()
        let updated = try XCTUnwrap(db.fetch(id: id))
        XCTAssertEqual(updated.storage["status"]?.stringValue, "closed")
        XCTAssertEqual(updated.storage["payload"]?.stringValue?.first, "v")

        try db.delete(id: id)
        try db.persist()
        try db.close()

        db = try openDB()
        XCTAssertNil(try db.fetch(id: id))
        try db.close()
    }

    func testInsertMany_failureMidBatch_doesNotLeaveHalfVisibleOverflowChain() throws {
        // First record is valid overflow-sized; second uses a duplicate id to force abort
        // after the first page write path has run — index must not publish the failed batch.
        var db = try openDB()
        let shared = UUID()
        let first = BlazeDataRecord([
            "id": .uuid(shared),
            "index": .int(0),
            "payload": .string(String(repeating: "x", count: 6_000)),
        ])
        let duplicate = BlazeDataRecord([
            "id": .uuid(shared),
            "index": .int(1),
            "payload": .string(String(repeating: "y", count: 6_000)),
        ])

        XCTAssertThrowsError(try db.insertMany([first, duplicate]))
        try? db.persist()
        try db.close()

        db = try openDB()
        XCTAssertNil(try db.fetch(id: shared), "failed batch must not leave a visible overflow record")
        try db.close()
    }
}
