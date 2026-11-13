//
//  AggregationMissingFieldTests.swift
//  BlazeDBTests — min/max ignore rows that do not store the field
//
//  A missing field used to compare as greater than every stored value, and the
//  winning row then stored 0. MAX(score) became 0 when any row omitted score.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class AggregationMissingFieldTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AggregationMissingField-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "AggregationMissingField",
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

    func testMinMaxIgnoreRowsMissingTheField() throws {
        _ = try db.insert(BlazeDataRecord(["team": .string("a"), "score": .int(100)]))
        _ = try db.insert(BlazeDataRecord(["team": .string("a"), "name": .string("unscored")]))
        _ = try db.insert(BlazeDataRecord(["team": .string("b"), "score": .int(-5)]))
        _ = try db.insert(BlazeDataRecord(["team": .string("c"), "name": .string("empty")]))

        let overall = try db.query().max("score").min("score").execute().aggregation
        XCTAssertEqual(overall["max_score"]?.intValue, 100)
        XCTAssertEqual(overall["min_score"]?.intValue, -5)

        let grouped = try db.query().groupBy("team").max("score").min("score").execute().grouped
        XCTAssertEqual(grouped["a"]?["max_score"]?.intValue, 100)
        XCTAssertEqual(grouped["a"]?["min_score"]?.intValue, 100)
        XCTAssertEqual(grouped["b"]?["max_score"]?.intValue, -5)
        XCTAssertEqual(grouped["b"]?["min_score"]?.intValue, -5)
        XCTAssertNil(grouped["c"]?["max_score"])
        XCTAssertNil(grouped["c"]?["min_score"])
    }

    func testMaxOfDatesDoesNotBecomeZeroWhenAnotherRowOmitsTheField() throws {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try db.insert(BlazeDataRecord(["when": .date(day)]))
        _ = try db.insert(BlazeDataRecord(["name": .string("no date")]))

        let latest = try db.query().max("when").execute().aggregation
        XCTAssertEqual(latest["max_when"]?.dateValue, day)
        XCTAssertNil(latest["max_when"]?.intValue)
    }
}
