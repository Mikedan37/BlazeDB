//
//  AsyncNotEqualsMissingFieldTests.swift
//  BlazeDBTests — #344: async where(notEquals:) treats missing field as non-match
//
//  The async query path (QueryBuilder+Async.swift) inlines a copy of the
//  sync predicate. It must match the sync semantics fixed in #343: a
//  missing field counts as "not equal" to any given value, while
//  `where(_:equals:)` (correct, unchanged) treats a missing field as a
//  non-match — the two are deliberately asymmetric.
//
//  The async query path is Apple-only (`#if !BLAZEDB_LINUX_CORE`), so these
//  tests compile and run only where that path exists.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

#if !BLAZEDB_LINUX_CORE
final class AsyncNotEqualsMissingFieldTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AsyncNotEqualsMissing-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "AsyncNotEqualsMissing",
            fileURL: dbURL,
            password: "AsyncNotEqualsMissing-Pass_123!"
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

    /// #344 reproduction: a record with no `status` field at all must match
    /// async `notEquals: .string("archived")`, alongside a record whose
    /// `status` is present but unequal. A record whose `status` equals the
    /// given value must still be excluded.
    func testAsyncNotEquals_MissingField_MatchesAlongsidePresentUnequal() async throws {
        _ = try await db.insert(BlazeDataRecord(["name": .string("a")])) // no status field
        _ = try await db.insert(BlazeDataRecord(["name": .string("b"), "status": .string("archived")]))
        _ = try await db.insert(BlazeDataRecord(["name": .string("c"), "status": .string("active")]))

        let query = await db.query()
            .where("status", notEquals: .string("archived"))
        let rows = try await query.execute()

        let names = Set(try rows.records.compactMap { $0.storage["name"]?.stringValue })
        XCTAssertEqual(names, ["a", "c"])
    }

    func testAsyncNotEquals_PresentEqualValue_IsExcluded() async throws {
        _ = try await db.insert(BlazeDataRecord(["name": .string("archived-one"), "status": .string("archived")]))

        let query = await db.query()
            .where("status", notEquals: .string("archived"))
        let rows = try await query.execute()

        XCTAssertTrue(rows.isEmpty)
    }

    func testAsyncNotEquals_PresentUnequalValue_IsIncluded() async throws {
        _ = try await db.insert(BlazeDataRecord(["name": .string("active-one"), "status": .string("active")]))

        let query = await db.query()
            .where("status", notEquals: .string("archived"))
        let rows = try await query.execute()

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows.records.first?.storage["name"]?.stringValue, "active-one")
    }

    /// Scope guard: async `equals` missing-field behavior is unchanged by
    /// this fix (still a non-match).
    func testAsyncEquals_MissingField_IsStillExcluded() async throws {
        _ = try await db.insert(BlazeDataRecord(["name": .string("no-status")])) // no status field

        let query = await db.query()
            .where("status", equals: .string("archived"))
        let rows = try await query.execute()

        XCTAssertTrue(rows.isEmpty)
    }
}
#endif // !BLAZEDB_LINUX_CORE
