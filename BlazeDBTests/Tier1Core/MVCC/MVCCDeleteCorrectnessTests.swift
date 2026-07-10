//
//  MVCCDeleteCorrectnessTests.swift
//  BlazeDBTests
//
//  Regression coverage for MVCC delete visibility and page-reuse safety.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class MVCCDeleteCorrectnessTests: XCTestCase {
    private var tempURL: URL?
    private var db: BlazeDBClient?

    override func setUp() async throws {
        try await super.setUp()

        BlazeDBClient.clearCachedKey()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MVCCDeleteCorrectness-\(UUID().uuidString).blazedb")
        tempURL = url

        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("salt"))

        db = try BlazeDBClient(name: "mvcc_delete_correctness", fileURL: url, password: "SecureTestDB-456!")
        try requireFixture(db).setMVCCEnabled(true)
    }

    override func tearDown() {
        if let url = tempURL {
            cleanupBlazeDB(&db, at: url)
        }
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }

    func testDeleteAfterUpdateDoesNotResurfaceOlderVersion() throws {
        let client = try requireFixture(db)

        let id = try client.insert(BlazeDataRecord(["value": .string("original")]))
        try client.update(id: id, with: BlazeDataRecord(["value": .string("updated")]))
        XCTAssertEqual(try client.fetch(id: id)?["value"]?.stringValue, "updated")

        try client.delete(id: id)

        XCTAssertNil(try client.fetch(id: id), "Deleting an updated MVCC record must not expose an older version")
        XCTAssertEqual(try client.count(), 0)
    }

    func testDeleteManyUsesMVCCTombstones() throws {
        let client = try requireFixture(db)

        let ids = try (0..<4).map { i in
            try client.insert(BlazeDataRecord(["value": .int(i)]))
        }

        let deleted = try client.deleteMany(ids: Array(ids.prefix(3)))

        XCTAssertEqual(deleted, 3)
        for id in ids.prefix(3) {
            XCTAssertNil(try client.fetch(id: id), "deleteMany must remove MVCC-visible versions")
        }
        XCTAssertNotNil(try client.fetch(id: ids[3]))
        XCTAssertEqual(try client.count(), 1)
    }

    func testDeleteDoesNotReusePageNeededByActiveSnapshot() throws {
        let client = try requireFixture(db)
        let collection = client.collection

        let oldID = try client.insert(BlazeDataRecord(["value": .string("old")]))
        let snapshot = MVCCTransaction(versionManager: collection.versionManager, pageStore: collection.store)
        XCTAssertEqual(try snapshot.read(recordID: oldID)?["value"]?.stringValue, "old")

        try client.delete(id: oldID)
        _ = try client.insert(BlazeDataRecord(["value": .string("new")]))

        XCTAssertEqual(
            try snapshot.read(recordID: oldID)?["value"]?.stringValue,
            "old",
            "Active MVCC snapshots must not read bytes overwritten by page reuse after delete"
        )

        try snapshot.rollback()
    }
}
