//
//  BlazeQueryTests.swift
//  BlazeDBTests
//
//  Modernized query behavior tests aligned with current async APIs.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class BlazeQueryTests: LinuxTier1NonCryptoKDFHarness {
    private var db: BlazeDBClient?
    private var tempURL: URL?

    override func setUp() async throws {
        continueAfterFailure = false
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazequery_test_\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "BlazeQueryTest", fileURL: try requireFixture(tempURL), password: "UltraSecurePass-123!")
    }

    override func tearDown() async throws {
        if let db {
            try? await requireFixture(db).close()
        }
        db = nil
        if let tempURL {
            try? FileManager.default.removeItem(at: try requireFixture(tempURL))
            try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("meta"))
        }
        tempURL = nil
    }

    func testBasicWhereQuery() async throws {
        _ = try await requireFixture(db).insert(BlazeDataRecord(["status": .string("open"), "name": .string("A")]))
        _ = try await requireFixture(db).insert(BlazeDataRecord(["status": .string("closed"), "name": .string("B")]))
        _ = try await requireFixture(db).insert(BlazeDataRecord(["status": .string("open"), "name": .string("C")]))

        let results = try await requireFixture(db).query()
            .where("status", equals: .string("open"))
            .orderBy("name")
            .execute()

        XCTAssertEqual(results.count, 2)
    }

    func testLimitAndOffset() async throws {
        for i in 0..<20 {
            _ = try await requireFixture(db).insert(BlazeDataRecord(["index": .int(i)]))
        }

        let page = try await requireFixture(db).query()
            .orderBy("index")
            .offset(5)
            .limit(5)
            .execute()

        XCTAssertEqual(page.count, 5)
    }

    func testGroupedAggregation() async throws {
        _ = try await requireFixture(db).insert(BlazeDataRecord(["kind": .string("A")]))
        _ = try await requireFixture(db).insert(BlazeDataRecord(["kind": .string("A")]))
        _ = try await requireFixture(db).insert(BlazeDataRecord(["kind": .string("B")]))

        let stats = try await requireFixture(db).query()
            .groupBy("kind")
            .count(as: "total")
            .execute()

        let grouped = try stats.grouped
        XCTAssertEqual(grouped.groups.count, 2)
    }

    func testOrderByDescending() async throws {
        _ = try await requireFixture(db).insert(BlazeDataRecord(["score": .int(1)]))
        _ = try await requireFixture(db).insert(BlazeDataRecord(["score": .int(5)]))
        _ = try await requireFixture(db).insert(BlazeDataRecord(["score": .int(3)]))

        let results = try await requireFixture(db).query()
            .orderBy("score", descending: true)
            .execute()

        let records = try results.records
        let scores = records.compactMap { $0.storage["score"]?.intValue }
        XCTAssertEqual(scores.prefix(3), [5, 3, 1])
    }

    func testMultiWhereFiltering() async throws {
        _ = try await requireFixture(db).insert(BlazeDataRecord(["status": .string("open"), "priority": .int(5)]))
        _ = try await requireFixture(db).insert(BlazeDataRecord(["status": .string("open"), "priority": .int(2)]))
        _ = try await requireFixture(db).insert(BlazeDataRecord(["status": .string("closed"), "priority": .int(5)]))

        let results = try await requireFixture(db).query()
            .where("status", equals: .string("open"))
            .where("priority", equals: .int(5))
            .execute()

        XCTAssertEqual(results.count, 1)
    }

    func testQueryAfterUpdateReflectsNewState() async throws {
        let id = try await requireFixture(db).insert(BlazeDataRecord(["state": .string("new")]))
        let before = try await requireFixture(db).query().where("state", equals: .string("new")).execute()
        XCTAssertEqual(before.count, 1)

        try await requireFixture(db).update(id: id, with: BlazeDataRecord(["state": .string("done")]))
        let afterOld = try await requireFixture(db).query().where("state", equals: .string("new")).execute()
        let afterNew = try await requireFixture(db).query().where("state", equals: .string("done")).execute()

        XCTAssertEqual(afterOld.count, 0)
        XCTAssertEqual(afterNew.count, 1)
    }

    func testQueryAfterDeleteShrinksResultSet() async throws {
        let id1 = try await requireFixture(db).insert(BlazeDataRecord(["bucket": .string("A")]))
        _ = try await requireFixture(db).insert(BlazeDataRecord(["bucket": .string("A")]))

        let before = try await requireFixture(db).query().where("bucket", equals: .string("A")).execute()
        XCTAssertEqual(before.count, 2)

        try await requireFixture(db).delete(id: id1)
        let after = try await requireFixture(db).query().where("bucket", equals: .string("A")).execute()
        XCTAssertEqual(after.count, 1)
    }

    func testPaginationAcrossPages() async throws {
        for i in 0..<30 {
            _ = try await requireFixture(db).insert(BlazeDataRecord(["index": .int(i)]))
        }

        let page1 = try await requireFixture(db).query().orderBy("index").limit(10).execute()
        let page2 = try await requireFixture(db).query().orderBy("index").offset(10).limit(10).execute()
        let page3 = try await requireFixture(db).query().orderBy("index").offset(20).limit(10).execute()

        XCTAssertEqual(page1.count, 10)
        XCTAssertEqual(page2.count, 10)
        XCTAssertEqual(page3.count, 10)
    }
}
