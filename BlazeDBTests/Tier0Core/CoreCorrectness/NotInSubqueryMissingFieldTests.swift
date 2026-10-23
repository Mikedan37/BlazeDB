//
//  NotInSubqueryMissingFieldTests.swift
//  BlazeDBTests — #422: where(notInSubquery:) treats missing field as a match
//
//  Missing fields match NOT IN, including an empty subquery. Present values
//  retain membership behavior, and IN still excludes missing fields.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class NotInSubqueryMissingFieldTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotInSubqueryMissing-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "NotInSubqueryMissing",
            fileURL: dbURL,
            password: UUID().uuidString + "aA1!"
        )
    }

    override func tearDown() {
        try? db.close()
        let base = dbURL.deletingPathExtension()
        for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
            try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
        }
        try? FileManager.default.removeItem(at: dbURL)
        db = nil
        dbURL = nil
        super.tearDown()
    }

    func testNotInSubquery_MissingField_MatchesAlongsidePresentUnequal() throws {
        _ = try db.insert(BlazeDataRecord(["name": .string("a")]))
        _ = try db.insert(BlazeDataRecord(["name": .string("b"), "status": .string("archived")]))
        _ = try db.insert(BlazeDataRecord(["name": .string("c"), "status": .string("active")]))

        let subquery = db.query()
            .where("status", equals: .string("archived"))
            .asSubquery(extracting: "status")
        let rows = try db.query()
            .where("status", notInSubquery: subquery)
            .execute()

        let names = Set(try rows.records.compactMap { $0.storage["name"]?.stringValue })
        XCTAssertEqual(names, ["a", "c"])
    }

    func testNotInSubquery_EmptySubquery_IncludesMissingAndPresent() throws {
        _ = try db.insert(BlazeDataRecord(["name": .string("a")]))
        _ = try db.insert(BlazeDataRecord(["name": .string("b"), "status": .string("active")]))

        let subquery = db.query()
            .where("status", equals: .string("archived"))
            .asSubquery(extracting: "status")
        let rows = try db.query()
            .where("status", notInSubquery: subquery)
            .execute()

        let names = Set(try rows.records.compactMap { $0.storage["name"]?.stringValue })
        XCTAssertEqual(names, ["a", "b"])
    }

    func testInSubquery_MissingField_IsStillExcluded() throws {
        _ = try db.insert(BlazeDataRecord(["name": .string("a")]))
        _ = try db.insert(BlazeDataRecord(["name": .string("b"), "status": .string("archived")]))
        _ = try db.insert(BlazeDataRecord(["name": .string("c"), "status": .string("active")]))

        let subquery = db.query()
            .where("status", equals: .string("archived"))
            .asSubquery(extracting: "status")
        let rows = try db.query()
            .where("status", inSubquery: subquery)
            .execute()

        let names = Set(try rows.records.compactMap { $0.storage["name"]?.stringValue })
        XCTAssertEqual(names, ["b"])
    }
}
