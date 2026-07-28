//
//  KeyPathNotEqualsMissingFieldTests.swift
//  BlazeDBTests — #345: KeyPath where(notEquals:) treats missing field as non-match
//
//  The KeyPath query builder must match the sync string semantics fixed in
//  #343: a missing field counts as "not equal" to any given value, while
//  KeyPath `where(_:equals:)` (correct, unchanged) treats a missing field
//  as a non-match — the two are deliberately asymmetric.
//
//  The model uses an optional `status` so a task with `status == nil`
//  encodes with NO `status` key at all (JSONEncoder omits nil optionals),
//  giving a genuine missing-field record that still round-trips through
//  `BlazeStorable` decoding.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class KeyPathNotEqualsMissingFieldTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    struct Task: BlazeStorable {
        var id: UUID = UUID()
        var name: String
        var status: String?
    }

    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyPathNotEqualsMissing-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "KeyPathNotEqualsMissing",
            fileURL: dbURL,
            password: "KeyPathNotEqualsMissing-Pass_123!"
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

    /// #345 reproduction: a record with no `status` field at all must match
    /// KeyPath `notEquals: "archived"`, alongside a record whose `status`
    /// is present but unequal. A record whose `status` equals the given
    /// value must still be excluded.
    func testKeyPathNotEquals_MissingField_MatchesAlongsidePresentUnequal() throws {
        _ = try db.insertMany([
            Task(name: "a", status: nil),          // no status field after encoding
            Task(name: "b", status: "archived"),
            Task(name: "c", status: "active"),
        ])

        let matches = try db.query(Task.self)
            .where(\.status, notEquals: "archived")
            .all()

        XCTAssertEqual(Set(matches.map { $0.name }), ["a", "c"])
    }

    func testKeyPathNotEquals_PresentEqualValue_IsExcluded() throws {
        _ = try db.insert(Task(name: "archived-one", status: "archived"))

        let matches = try db.query(Task.self)
            .where(\.status, notEquals: "archived")
            .all()

        XCTAssertTrue(matches.isEmpty)
    }

    func testKeyPathNotEquals_PresentUnequalValue_IsIncluded() throws {
        _ = try db.insert(Task(name: "active-one", status: "active"))

        let matches = try db.query(Task.self)
            .where(\.status, notEquals: "archived")
            .all()

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.name, "active-one")
    }

    /// Scope guard: KeyPath `equals` missing-field behavior is unchanged by
    /// this fix (still a non-match).
    func testKeyPathEquals_MissingField_IsStillExcluded() throws {
        _ = try db.insert(Task(name: "no-status", status: nil)) // no status field

        let matches = try db.query(Task.self)
            .where(\.status, equals: "archived")
            .all()

        XCTAssertTrue(matches.isEmpty)
    }
}
