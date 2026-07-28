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
            XCTAssertEqual(
                fetched.storage["payload"]?.stringValue?.first,
                records[i].storage["payload"]?.stringValue?.first
            )
        }
        try db.close()
    }

    func testInsertMany_multipleOverflowRecords_roundTripAfterReopen() throws {
        // Regression: one batch with several overflow-sized values (not a single oversized row).
        let specs: [(Int, Int, Character)] = [
            (0, 5_000, "A"),
            (1, 12_000, "B"),
            (2, 40_000, "C"),
            (3, 8_192, "D"),
        ]
        var db = try openDB()
        let records = specs.map { record(index: $0.0, payloadBytes: $0.1, filler: $0.2) }
        let ids = try db.insertMany(records)
        XCTAssertEqual(ids.count, specs.count)
        try db.persist()
        try db.close()

        db = try openDB()
        for (i, id) in ids.enumerated() {
            let fetched = try XCTUnwrap(db.fetch(id: id), "missing overflow record \(i) after reopen")
            XCTAssertEqual(fetched.storage["index"]?.intValue, specs[i].0)
            XCTAssertEqual(fetched.storage["payload"]?.stringValue?.count, specs[i].1)
            XCTAssertEqual(fetched.storage["payload"]?.stringValue?.first, specs[i].2)
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

    func testInsertMany_synchronizeFailure_doesNotPublishOverflowChainsIntoIndexMap() throws {
        // Crash-ordering: pages may be staged, but indexMap must stay unpublished if synchronize() fails.
        #if DEBUG
        var db = try openDB()
        let records = [
            record(index: 0, payloadBytes: 6_000, filler: "p"),
            record(index: 1, payloadBytes: 9_000, filler: "q"),
        ]

        PageStore._setSynchronizeFailureForTests(true)
        defer { PageStore._setSynchronizeFailureForTests(false) }

        XCTAssertThrowsError(try db.insertMany(records))
        try? db.persist()
        try db.close()

        db = try openDB()
        let surviving = try db.fetchAll()
        XCTAssertTrue(
            surviving.isEmpty,
            "failed synchronize must not publish overflow page chains into indexMap; found \(surviving.count)"
        )
        try db.close()
        #else
        throw XCTSkip("synchronize fault injection is DEBUG-only")
        #endif
    }

    func testInsertMany_overflowCommittedPageConflict_failsWithoutDeletingExisting() throws {
        // Allocator invariant: colliding with a committed indexMap page must fail the batch,
        // not silently remove the existing record's index entry.
        #if DEBUG
        var db = try openDB()
        let existingPayload = String(repeating: "z", count: 64)
        let existingID = try db.insert(
            BlazeDataRecord([
                "index": .int(0),
                "payload": .string(existingPayload),
                "marker": .string("seed-committed"),
            ])
        )
        try db.persist()

        let committedPages = try XCTUnwrap(db.collection.indexMap[existingID])
        let victimPage = try XCTUnwrap(committedPages.first)
        let rejectedPayload = String(repeating: "x", count: 6_000)

        // Skip the head-page allocatePage for the batch record; force the overflow allocate to the victim.
        DynamicCollection._forceAllocatedPageAfterSkippingForTests(skips: 1, page: victimPage)
        defer { DynamicCollection._clearForcedAllocatedPageForTests() }

        XCTAssertThrowsError(
            try db.insertMany([
                BlazeDataRecord([
                    "index": .int(1),
                    "payload": .string(rejectedPayload),
                    "marker": .string("should-not-commit"),
                ])
            ])
        ) { error in
            guard case BlazeDBError.corruptedData(let location, let reason) = error else {
                return XCTFail("expected pageAllocationConflict (corruptedData), got \(error)")
            }
            XCTAssertEqual(location, "page \(victimPage)")
            XCTAssertTrue(reason.contains("refusing to delete"), reason)
        }

        // Before reopen: committed seed remains fetchable; rejected overflow batch is absent.
        let beforeReopen = try XCTUnwrap(db.fetch(id: existingID), "committed record must remain fetchable before reopen")
        XCTAssertEqual(beforeReopen.storage["payload"]?.stringValue, existingPayload)
        XCTAssertEqual(beforeReopen.storage["marker"]?.stringValue, "seed-committed")
        XCTAssertEqual(try db.fetchAll().count, 1)
        XCTAssertTrue(
            try db.fetchAll().allSatisfy { $0.storage["marker"]?.stringValue != "should-not-commit" },
            "rejected batch overflow record must be absent before reopen"
        )

        try? db.persist()
        try db.close()

        db = try openDB()
        let afterReopen = try XCTUnwrap(db.fetch(id: existingID), "committed record must survive reopen")
        XCTAssertEqual(afterReopen.storage["payload"]?.stringValue, existingPayload)
        XCTAssertEqual(afterReopen.storage["marker"]?.stringValue, "seed-committed")
        XCTAssertEqual(try db.fetchAll().count, 1)
        XCTAssertNil(
            try db.fetchAll().first(where: { $0.storage["marker"]?.stringValue == "should-not-commit" }),
            "rejected batch overflow record must remain absent after reopen"
        )
        try db.close()
        #else
        throw XCTSkip("allocatePage fault injection is DEBUG-only")
        #endif
    }
}
