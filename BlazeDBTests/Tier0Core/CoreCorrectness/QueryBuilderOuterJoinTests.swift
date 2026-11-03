//
//  QueryBuilderOuterJoinTests.swift
//  BlazeDBTests
//
//  query().join(type: .right / .full).execute() must keep right-hand rows that
//  no left row references. Batch-fetching only left foreign keys dropped them.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class QueryBuilderOuterJoinTests: XCTestCase {
    private var bugsURL: URL!
    private var usersURL: URL!
    private var bugs: BlazeDBClient!
    private var users: BlazeDBClient!

    override func setUp() {
        super.setUp()
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
        bugsURL = directory.appendingPathComponent("QueryOuterJoin-bugs-\(id).blazedb")
        usersURL = directory.appendingPathComponent("QueryOuterJoin-users-\(id).blazedb")
        bugs = try! BlazeDBClient(
            name: "query_outer_join_bugs_\(id)",
            fileURL: bugsURL,
            password: "QueryOuterJoin-Test-2026!"
        )
        users = try! BlazeDBClient(
            name: "query_outer_join_users_\(id)",
            fileURL: usersURL,
            password: "QueryOuterJoin-Test-2026!"
        )
    }

    override func tearDown() {
        try? bugs.close()
        try? users.close()
        for url in [bugsURL, usersURL] {
            let base = url?.deletingPathExtension()
            for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
                if let base {
                    try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
                }
            }
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
        }
        bugs = nil
        users = nil
        bugsURL = nil
        usersURL = nil
        super.tearDown()
    }

    func testQueryRightJoinKeepsUnmatchedRightRows() throws {
        let alice = UUID()
        let bob = UUID()
        try users.insert(BlazeDataRecord(["id": .uuid(alice), "name": .string("Alice")]))
        try users.insert(BlazeDataRecord(["id": .uuid(bob), "name": .string("Bob")]))
        try bugs.insert(BlazeDataRecord(["title": .string("Bug 1"), "author_id": .uuid(alice)]))

        let results = try bugs.query()
            .join(users.collection, on: "author_id", equals: "id", type: .right)
            .execute()
            .joined

        XCTAssertEqual(results.count, 2, "RIGHT JOIN must return every right-hand row")
        let names = Set(results.compactMap { $0.right?.storage["name"]?.stringValue })
        XCTAssertEqual(names, ["Alice", "Bob"])
        let withBugs = results.filter { !$0.left.storage.isEmpty }
        let withoutBugs = results.filter { $0.left.storage.isEmpty }
        XCTAssertEqual(withBugs.count, 1)
        XCTAssertEqual(withBugs.first?.left.storage["title"]?.stringValue, "Bug 1")
        XCTAssertEqual(withoutBugs.count, 1)
        XCTAssertEqual(withoutBugs.first?.right?.storage["name"]?.stringValue, "Bob")
    }

    func testQueryRightJoinWithNoLeftRowsStillReturnsRightRows() throws {
        try users.insert(BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Alice")]))
        try users.insert(BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Bob")]))

        let results = try bugs.query()
            .join(users.collection, on: "author_id", equals: "id", type: .right)
            .execute()
            .joined

        let names = Set(results.compactMap { $0.right?.storage["name"]?.stringValue })
        XCTAssertEqual(names, ["Alice", "Bob"])
        XCTAssertTrue(results.allSatisfy { $0.left.storage.isEmpty })
    }

    func testQueryFullJoinKeepsOrphansFromBothSides() throws {
        let alice = UUID()
        try users.insert(BlazeDataRecord(["id": .uuid(alice), "name": .string("Alice")]))
        try users.insert(BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Bob")]))
        try bugs.insert(BlazeDataRecord(["title": .string("Has author"), "author_id": .uuid(alice)]))
        try bugs.insert(BlazeDataRecord(["title": .string("Orphan"), "author_id": .uuid(UUID())]))

        let results = try bugs.query()
            .join(users.collection, on: "author_id", equals: "id", type: .full)
            .execute()
            .joined

        XCTAssertEqual(results.count, 3)
        let titles = Set(results.compactMap { $0.left.storage["title"]?.stringValue })
        XCTAssertEqual(titles, ["Has author", "Orphan"])
        let names = Set(results.compactMap { $0.right?.storage["name"]?.stringValue })
        XCTAssertEqual(names, ["Alice", "Bob"])
    }

    func testQueryInnerJoinStillDropsUnmatchedRightRows() throws {
        let alice = UUID()
        try users.insert(BlazeDataRecord(["id": .uuid(alice), "name": .string("Alice")]))
        try users.insert(BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Bob")]))
        try bugs.insert(BlazeDataRecord(["title": .string("Bug 1"), "author_id": .uuid(alice)]))

        let results = try bugs.query()
            .join(users.collection, on: "author_id", equals: "id", type: .inner)
            .execute()
            .joined

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.right?.storage["name"]?.stringValue, "Alice")
    }
}
