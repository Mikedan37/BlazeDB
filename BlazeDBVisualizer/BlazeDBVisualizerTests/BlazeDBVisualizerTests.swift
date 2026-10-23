//
//  BlazeDBVisualizerTests.swift
//  BlazeDBVisualizerTests
//
//  Created by Michael Danylchuk on 6/29/25.
//

import XCTest
import BlazeDB
@testable import BlazeDBVisualizer

final class BlazeDBVisualizerTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testQueryFilter_MissingField_OnlyNotEqualsMatches() {
        let record = BlazeDataRecord(["name": .string("no-status")])
        let cases: [(QueryFilter.FilterOperator, Bool)] = [
            (.equals, false),
            (.notEquals, true),
            (.greaterThan, false),
            (.lessThan, false),
            (.contains, false),
            (.startsWith, false),
            (.endsWith, false)
        ]

        for (op, expected) in cases {
            let filter = QueryFilter(field: "status", operator: op, value: "archived")
            XCTAssertEqual(filter.matches(record: record), expected, "\(op)")
        }
    }

    func testQueryFilter_PresentString_PreservesOperatorBehavior() {
        let record = BlazeDataRecord(["status": .string("Active")])
        let cases: [(QueryFilter.FilterOperator, String, Bool)] = [
            (.equals, "Active", true),
            (.equals, "active", false),
            (.notEquals, "Active", false),
            (.notEquals, "active", true),
            (.contains, "CT", true),
            (.contains, "missing", false),
            (.startsWith, "AC", true),
            (.startsWith, "ve", false),
            (.endsWith, "VE", true),
            (.endsWith, "act", false)
        ]

        for (op, value, expected) in cases {
            let filter = QueryFilter(field: "status", operator: op, value: value)
            XCTAssertEqual(filter.matches(record: record), expected, "\(op): \(value)")
        }
    }

    func testQueryFilter_PresentNumbers_PreservesComparisons() {
        let records = [
            (BlazeDataRecord(["score": .int(10)]), "10"),
            (BlazeDataRecord(["score": .double(10.5)]), "10.5")
        ]
        let cases: [(QueryFilter.FilterOperator, String, Bool)] = [
            (.greaterThan, "9", true),
            (.greaterThan, "11", false),
            (.lessThan, "11", true),
            (.lessThan, "9", false)
        ]

        for (record, equalValue) in records {
            for (op, value, expected) in cases {
                let filter = QueryFilter(field: "score", operator: op, value: value)
                XCTAssertEqual(filter.matches(record: record), expected, "\(op): \(value)")
            }
            for op in [QueryFilter.FilterOperator.greaterThan, .lessThan] {
                let filter = QueryFilter(field: "score", operator: op, value: equalValue)
                XCTAssertFalse(filter.matches(record: record), "\(op) excludes equal values")
            }
        }
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
