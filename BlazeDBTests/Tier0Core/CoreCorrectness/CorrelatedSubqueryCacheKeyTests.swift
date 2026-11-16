//
//  CorrelatedSubqueryCacheKeyTests.swift
//  BlazeDBTests
//
//  greaterThanCorrelated caches the inner scalar per outer correlation value.
//  The key must distinguish values that are not equal, including timestamps
//  inside the same second and integers versus their decimal strings.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class CorrelatedSubqueryCacheKeyTests: XCTestCase {
    private var limitsURL: URL!
    private var eventsURL: URL!
    private var limits: BlazeDBClient!
    private var events: BlazeDBClient!

    override func setUp() {
        super.setUp()
        let token = UUID().uuidString
        limitsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorrelatedLimits-\(token).blazedb")
        eventsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorrelatedEvents-\(token).blazedb")
        let password = token + "aA1!"
        limits = try! BlazeDBClient(name: "CorrelatedLimits", fileURL: limitsURL, password: password)
        events = try! BlazeDBClient(name: "CorrelatedEvents", fileURL: eventsURL, password: password)
    }

    override func tearDown() {
        try? limits.close()
        try? events.close()
        for url in [limitsURL, eventsURL] {
            guard let url else { continue }
            let base = url.deletingPathExtension()
            for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
                try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
            }
            try? FileManager.default.removeItem(at: url)
        }
        limits = nil
        events = nil
        limitsURL = nil
        eventsURL = nil
        super.tearDown()
    }

    func testGreaterThanCorrelated_SameSecondTimestamps_UseTheirOwnThreshold() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let early = base.addingTimeInterval(0.1)
        let later = base.addingTimeInterval(0.8)

        _ = try limits.insert(BlazeDataRecord(["stamp": .date(early), "score": .int(10)]))
        _ = try limits.insert(BlazeDataRecord(["stamp": .date(later), "score": .int(100)]))
        _ = try events.insert(BlazeDataRecord(["name": .string("early"), "stamp": .date(early), "score": .int(50)]))
        _ = try events.insert(BlazeDataRecord(["name": .string("later"), "stamp": .date(later), "score": .int(50)]))

        let subquery = CorrelatedSubquery(
            subquery: limits.query(),
            correlationField: "stamp",
            subqueryField: "stamp"
        )
        let rows = try events.query()
            .where("score", greaterThanCorrelated: subquery)
            .execute()

        let names = Set(try rows.records.compactMap { $0.storage["name"]?.stringValue })
        XCTAssertEqual(names, ["early"])
    }

    func testGreaterThanCorrelated_IntAndDecimalString_DoNotShareCache() throws {
        _ = try limits.insert(BlazeDataRecord(["code": .int(1), "score": .int(10)]))
        _ = try limits.insert(BlazeDataRecord(["code": .string("1"), "score": .int(100)]))
        _ = try events.insert(BlazeDataRecord(["name": .string("numeric"), "code": .int(1), "score": .int(50)]))
        _ = try events.insert(BlazeDataRecord(["name": .string("text"), "code": .string("1"), "score": .int(50)]))

        let subquery = CorrelatedSubquery(
            subquery: limits.query(),
            correlationField: "code",
            subqueryField: "code"
        )
        let rows = try events.query()
            .where("score", greaterThanCorrelated: subquery)
            .execute()

        let names = Set(try rows.records.compactMap { $0.storage["name"]?.stringValue })
        XCTAssertEqual(names, ["numeric"])
    }
}
