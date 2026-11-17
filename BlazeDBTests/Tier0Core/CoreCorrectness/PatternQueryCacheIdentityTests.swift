//
//  PatternQueryCacheIdentityTests.swift
//  BlazeDBTests
//
//  LIKE, regex, and indexed range filters must change the query cache key.
//  Those predicates used to append a closure without a filter descriptor, so
//  execute(withCache:) reused another query's rows.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class PatternQueryCacheIdentityTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    override func setUp() {
        super.setUp()
        QueryCache.shared.clearAll()
        QueryCache.shared.isEnabled = true
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PatternQueryCache-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "PatternQueryCache",
            fileURL: dbURL,
            password: UUID().uuidString + "aA1!"
        )
    }

    override func tearDown() {
        try? db.close()
        QueryCache.shared.clearAll()
        let base = dbURL.deletingPathExtension()
        for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
            try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
        }
        try? FileManager.default.removeItem(at: dbURL)
        db = nil
        dbURL = nil
        super.tearDown()
    }

    func testLikePatternsDoNotShareCachedResults() throws {
        _ = try db.insert(BlazeDataRecord(["name": .string("alice")]))
        _ = try db.insert(BlazeDataRecord(["name": .string("bob")]))

        let alice = try db.query().where("name", like: "a%").execute(withCache: 60)
        let bob = try db.query().where("name", like: "b%").execute(withCache: 60)
        let everyone = try db.query().execute(withCache: 60)

        XCTAssertEqual(try names(alice), ["alice"])
        XCTAssertEqual(try names(bob), ["bob"])
        XCTAssertEqual(try names(everyone), ["alice", "bob"])
        XCTAssertNotEqual(
            db.query().where("name", like: "a%").generateCacheKey(),
            db.query().where("name", like: "b%").generateCacheKey()
        )
        XCTAssertNotEqual(
            db.query().where("name", like: "a%").generateCacheKey(),
            db.query().generateCacheKey()
        )
    }

    func testIlikeAndNotLikeDoNotShareCachedResults() throws {
        _ = try db.insert(BlazeDataRecord(["name": .string("Alice")]))
        _ = try db.insert(BlazeDataRecord(["name": .string("bob")]))

        let alice = try db.query().where("name", ilike: "AL%").execute(withCache: 60)
        let notAlice = try db.query().where("name", notLike: "A%").execute(withCache: 60)

        XCTAssertEqual(try names(alice), ["Alice"])
        XCTAssertEqual(try names(notAlice), ["bob"])
    }

    func testRegexPatternsDoNotShareCachedResults() throws {
        _ = try db.insert(BlazeDataRecord(["name": .string("alice")]))
        _ = try db.insert(BlazeDataRecord(["name": .string("bob")]))

        let alice = try db.query().where("name", matches: "^a").execute(withCache: 60)
        let bob = try db.query().where("name", matches: "^b").execute(withCache: 60)
        let caseInsensitive = try db.query()
            .where("name", matches: "^A", options: [.caseInsensitive])
            .execute(withCache: 60)

        XCTAssertEqual(try names(alice), ["alice"])
        XCTAssertEqual(try names(bob), ["bob"])
        XCTAssertEqual(try names(caseInsensitive), ["alice"])
        XCTAssertNotEqual(
            db.query().where("name", matches: "^a").generateCacheKey(),
            db.query().where("name", matches: "^A", options: [.caseInsensitive]).generateCacheKey()
        )
    }

    func testIndexedRangesDoNotShareCachedResults() throws {
        _ = try db.insert(BlazeDataRecord(["name": .string("low"), "score": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["name": .string("high"), "score": .int(100)]))
        _ = try db.insert(BlazeDataRecord(["name": .string("missing")]))
        try db.createIndex(on: "score")

        let low = try db.query()
            .whereRange("score", min: .int(0), max: .int(10))
            .execute(withCache: 60)
        let high = try db.query()
            .whereRange("score", min: .int(50), max: .int(200))
            .execute(withCache: 60)
        let unbounded = try db.query()
            .whereRange("score", min: nil, max: nil)
            .execute(withCache: 60)

        XCTAssertEqual(try names(low), ["low"])
        XCTAssertEqual(try names(high), ["high"])
        XCTAssertEqual(try names(unbounded), ["low", "high", "missing"])
    }

    private func names(_ result: QueryResult) throws -> Set<String> {
        Set(try result.records.compactMap { $0.storage["name"]?.stringValue })
    }
}
