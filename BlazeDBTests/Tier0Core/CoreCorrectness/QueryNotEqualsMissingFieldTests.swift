//
//  QueryNotEqualsMissingFieldTests.swift
//  BlazeDBTests — #327/#343: where(notEquals:) treats missing field as a match
//
//  A missing field must match `notEquals`, consistent with `whereNil`
//  semantics: absent is "not equal" to any given value. This mirrors
//  `where(_:equals:)`'s (correct, unchanged) behavior of treating a missing
//  field as a non-match — the two are deliberately asymmetric.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class QueryNotEqualsMissingFieldTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotEqualsMissing-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "NotEqualsMissing",
            fileURL: dbURL,
            password: "NotEqualsMissing-Pass_123!"
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

    /// #327 reproduction: a record with no `status` field at all must match
    /// `notEquals: .string("archived")`, alongside a record whose `status`
    /// is present but unequal. A record whose `status` equals the given
    /// value must still be excluded.
    func testNotEquals_MissingField_MatchesAlongsidePresentUnequal() throws {
        _ = try db.insert(BlazeDataRecord(["name": .string("a")])) // no status field
        _ = try db.insert(BlazeDataRecord(["name": .string("b"), "status": .string("archived")]))
        _ = try db.insert(BlazeDataRecord(["name": .string("c"), "status": .string("active")]))

        let rows = try db.query()
            .where("status", notEquals: .string("archived"))
            .execute()

        let names = Set(try rows.records.compactMap { $0.storage["name"]?.stringValue })
        XCTAssertEqual(names, ["a", "c"])
    }

    func testNotEquals_PresentEqualValue_IsExcluded() throws {
        _ = try db.insert(BlazeDataRecord(["name": .string("archived-one"), "status": .string("archived")]))

        let rows = try db.query()
            .where("status", notEquals: .string("archived"))
            .execute()

        XCTAssertTrue(rows.isEmpty)
    }

    func testNotEquals_PresentUnequalValue_IsIncluded() throws {
        _ = try db.insert(BlazeDataRecord(["name": .string("active-one"), "status": .string("active")]))

        let rows = try db.query()
            .where("status", notEquals: .string("archived"))
            .execute()

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows.records.first?.storage["name"]?.stringValue, "active-one")
    }

    /// Scope guard: `equals` missing-field behavior is unchanged by this fix
    /// (still a non-match).
    func testEquals_MissingField_IsStillExcluded() throws {
        _ = try db.insert(BlazeDataRecord(["name": .string("no-status")])) // no status field

        let rows = try db.query()
            .where("status", equals: .string("archived"))
            .execute()

        XCTAssertTrue(rows.isEmpty)
    }
}
