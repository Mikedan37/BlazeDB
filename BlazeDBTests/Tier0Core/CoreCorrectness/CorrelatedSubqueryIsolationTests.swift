//
//  CorrelatedSubqueryIsolationTests.swift
//  BlazeDBTests
//
//  lessThanCorrelated / equalsCorrelated used to append each outer correlation
//  value onto the shared subquery builder. The second distinct key was ANDed
//  with the first and dropped. greaterThanCorrelated cached .int(1) and
//  .string("1") under the same display string and reused the wrong threshold.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class CorrelatedSubqueryIsolationTests: XCTestCase {
    private var limitsURL: URL!
    private var ordersURL: URL!
    private var limits: BlazeDBClient!
    private var orders: BlazeDBClient!

    override func setUp() {
        super.setUp()
        let token = UUID().uuidString
        limitsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorrelatedLimits-\(token).blazedb")
        ordersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorrelatedOrders-\(token).blazedb")
        let password = token + "aA1!"
        limits = try! BlazeDBClient(name: "CorrelatedLimits-\(token)", fileURL: limitsURL, password: password)
        orders = try! BlazeDBClient(name: "CorrelatedOrders-\(token)", fileURL: ordersURL, password: password)
    }

    override func tearDown() {
        try? limits.close()
        try? orders.close()
        for url in [limitsURL, ordersURL] {
            guard let url else { continue }
            let base = url.deletingPathExtension()
            for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
                try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
            }
            try? FileManager.default.removeItem(at: url)
        }
        limits = nil
        orders = nil
        limitsURL = nil
        ordersURL = nil
        super.tearDown()
    }

    func testEqualsCorrelatedKeepsEveryDistinctKeyAndDoesNotMutateSubquery() throws {
        _ = try limits.insert(BlazeDataRecord(["code": .string("a"), "value": .int(10)]))
        _ = try limits.insert(BlazeDataRecord(["code": .string("b"), "value": .int(20)]))
        _ = try orders.insert(BlazeDataRecord(["name": .string("match-a"), "code": .string("a"), "value": .int(10)]))
        _ = try orders.insert(BlazeDataRecord(["name": .string("match-b"), "code": .string("b"), "value": .int(20)]))
        _ = try orders.insert(BlazeDataRecord(["name": .string("miss"), "code": .string("a"), "value": .int(99)]))

        let builder = limits.query()
        let descriptorCount = builder.filterDescriptors.count
        let filterCount = builder.filters.count

        let subquery = CorrelatedSubquery(
            subquery: builder,
            correlationField: "code",
            subqueryField: "code"
        )

        let first = try names(orders.query().where("value", equalsCorrelated: subquery).execute())
        let second = try names(orders.query().where("value", equalsCorrelated: subquery).execute())

        XCTAssertEqual(first, ["match-a", "match-b"])
        XCTAssertEqual(second, ["match-a", "match-b"])
        XCTAssertEqual(builder.filters.count, filterCount)
        XCTAssertEqual(builder.filterDescriptors.count, descriptorCount)
    }

    func testLessThanCorrelatedAppliesEachOuterKeySeparately() throws {
        _ = try limits.insert(BlazeDataRecord(["code": .string("a"), "value": .int(10)]))
        _ = try limits.insert(BlazeDataRecord(["code": .string("b"), "value": .int(20)]))
        _ = try orders.insert(BlazeDataRecord(["name": .string("under-a"), "code": .string("a"), "value": .int(5)]))
        _ = try orders.insert(BlazeDataRecord(["name": .string("under-b"), "code": .string("b"), "value": .int(15)]))
        _ = try orders.insert(BlazeDataRecord(["name": .string("over-a"), "code": .string("a"), "value": .int(50)]))

        let subquery = CorrelatedSubquery(
            subquery: limits.query(),
            correlationField: "code",
            subqueryField: "code"
        )
        let matched = try names(orders.query().where("value", lessThanCorrelated: subquery).execute())
        XCTAssertEqual(matched, ["under-a", "under-b"])
    }

    func testGreaterThanCorrelatedDoesNotReuseAnotherTypesThreshold() throws {
        _ = try limits.insert(BlazeDataRecord(["code": .int(1), "value": .int(100)]))
        _ = try limits.insert(BlazeDataRecord(["code": .string("1"), "value": .int(5)]))
        _ = try orders.insert(BlazeDataRecord(["name": .string("int-row"), "code": .int(1), "value": .int(50)]))
        _ = try orders.insert(BlazeDataRecord(["name": .string("str-row"), "code": .string("1"), "value": .int(50)]))

        let subquery = CorrelatedSubquery(
            subquery: limits.query(),
            correlationField: "code",
            subqueryField: "code"
        )
        let matched = try names(orders.query().where("value", greaterThanCorrelated: subquery).execute())
        XCTAssertEqual(matched, ["str-row"])
    }

    private func names(_ result: QueryResult) throws -> Set<String> {
        Set(try result.records.compactMap { $0.storage["name"]?.stringValue })
    }
}
