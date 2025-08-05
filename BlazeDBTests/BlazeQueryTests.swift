// BlazeQueryTests.swift
// BlazeDBTests
// Created by Michael Danylchuk on 6/15/25.
// Modernized & expanded for BlazeDB V1

import XCTest

@testable import BlazeDB

final class BlazeQueryTests: XCTestCase {

    let testDocs: [[String: BlazeDocumentField]] = [
        ["title": .string("Hello"), "id": .uuid(UUID()), "views": .int(42), "tags": .string("ios,swift,db"), "priority": .double(1.5)],
        ["title": .string("World"), "id": .uuid(UUID()), "views": .int(99), "tags": .string("macos,swift"), "priority": .double(2.0)],
        ["title": .string("Swift"), "id": .uuid(UUID()), "views": .int(7), "tags": .string("linux"), "priority": .double(0.1)]
    ]

    func testEqualsOperator() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .evaluate { $0["title"] == .string("Hello") }
        let results = testDocs.filter(query.matches)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?["title"], .string("Hello"))
    }

    func testEqualsOperatorWithMismatch() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .evaluate { $0["title"] == .string("Goodbye") }
        let results = testDocs.filter(query.matches)
        XCTAssertTrue(results.isEmpty)
    }

    func testContainsOperator() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .evaluate {
                guard let tagsRaw = $0["tags"]?.value as? String else { return false }
                return tagsRaw.split(separator: ",").contains("swift")
            }
        let results = testDocs.filter(query.matches)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { ($0["tags"]?.value as? String)?.contains("swift") ?? false })
    }

    func testContainsOperatorFails() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .evaluate {
                guard let tagsRaw = $0["tags"]?.value as? String else { return false }
                return tagsRaw.split(separator: ",").contains("windows")
            }
        let results = testDocs.filter(query.matches)
        XCTAssertTrue(results.isEmpty)
    }

    func testWhereEqualsBuilder() {
        let query = BlazeQuery<[String: BlazeDocumentField]>.whereField("title").equals("Hello")
        let results = testDocs.filter(query.matches)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?["title"], .string("Hello"))
    }

    func testWhereBuilderGreaterThan() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .evaluate {
                guard let v = $0["views"]?.value as? Int else { return false }
                return v > 10
            }
        let results = testDocs.filter(query.matches)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { ($0["views"]?.value as? Int ?? 0) > 10 })
    }

    func testAddPredicate() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .evaluate { $0["tags"] == .string("linux") }
            .addPredicate { $0["priority"] == .double(0.1) }
        let results = testDocs.filter(query.matches)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?["tags"], .string("linux"))
        XCTAssertEqual(results.first?["priority"], .double(0.1))
    }

    func testSortByIntAscending() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .sort { lhs, rhs in
                let l = lhs["views"]?.value as? Int ?? 0
                let r = rhs["views"]?.value as? Int ?? 0
                return l < r
            }
        let sorted = query.apply(to: testDocs)
        let views = sorted.compactMap { $0["views"]?.value as? Int }
        XCTAssertEqual(views, views.sorted())
    }

    func testSortByDoubleDescending() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .sort { lhs, rhs in
                let l = lhs["priority"]?.value as? Double ?? 0
                let r = rhs["priority"]?.value as? Double ?? 0
                return l > r
            }
        let sorted = query.apply(to: testDocs)
        let priorities = sorted.compactMap { $0["priority"]?.value as? Double }
        XCTAssertEqual(priorities, priorities.sorted(by: >))
    }

    func testRangeLimit() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .sort { lhs, rhs in
                let l = lhs["views"]?.value as? Int ?? 0
                let r = rhs["views"]?.value as? Int ?? 0
                return l > r
            }
            .range(0..<2)
        let ranged = query.apply(to: testDocs)
        XCTAssertEqual(ranged.count, 2)
        let views = ranged.compactMap { $0["views"]?.value as? Int }
        XCTAssertEqual(views.count, 2)
        XCTAssertTrue(views[0] >= views[1])
    }

    func testChainedQuery() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .evaluate { $0["tags"] == .string("macos,swift") }
            .sort { lhs, rhs in
                let l = lhs["views"]?.value as? Int ?? 0
                let r = rhs["views"]?.value as? Int ?? 0
                return l < r
            }
            .range(0..<1)
        let result = query.apply(to: testDocs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?["tags"], .string("macos,swift"))
    }

    func testEmptyData() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .evaluate { $0["title"] == .string("none") }
        let results = query.apply(to: [])
        XCTAssertTrue(results.isEmpty)
    }

    func testTypeMismatch() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .evaluate { $0["views"] == .string("notAnInt") }
        let results = query.apply(to: testDocs)
        XCTAssertTrue(results.isEmpty)
    }

    func testFilterConvenience() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .filter { $0["priority"] == .double(2.0) }
        let results = query.apply(to: testDocs)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?["priority"], .double(2.0))
    }
    
    func testMultiplePredicatesAndSorts() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .evaluate { $0["views"] != nil }
            .addPredicate { $0["priority"] != nil }
            .sort { lhs, rhs in
                // Sort by priority, then by views
                let lp = lhs["priority"]?.value as? Double ?? 0
                let rp = rhs["priority"]?.value as? Double ?? 0
                if lp != rp { return lp < rp }
                let lv = lhs["views"]?.value as? Int ?? 0
                let rv = rhs["views"]?.value as? Int ?? 0
                return lv < rv
            }
        let sorted = query.apply(to: testDocs)
        let priorities = sorted.compactMap { $0["priority"]?.value as? Double }
        XCTAssertEqual(priorities, priorities.sorted())
        XCTAssertEqual(sorted.count, 3)
    }

    func testFilterAfterSortAndRange() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .sort { lhs, rhs in
                let l = lhs["views"]?.value as? Int ?? 0
                let r = rhs["views"]?.value as? Int ?? 0
                return l > r
            }
            .range(0..<2)
            .filter { $0["tags"]?.value as? String == "ios,swift,db" }
        let filtered = query.apply(to: testDocs)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?["tags"], .string("ios,swift,db"))
    }

    func testOutOfBoundsRange() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .range(0..<10)
        let ranged = query.apply(to: testDocs)
        XCTAssertEqual(ranged.count, 3)
    }

    func testSingleElementRange() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .range(1..<2)
        let ranged = query.apply(to: testDocs)
        XCTAssertEqual(ranged.count, 1)
        XCTAssertEqual(ranged.first?["title"], .string("World"))
    }

    func testEmptyResultAfterFilter() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .filter { $0["priority"] == .double(42.0) }
        let filtered = query.apply(to: testDocs)
        XCTAssertTrue(filtered.isEmpty)
    }

    func testAllCombined() {
        let query = BlazeQuery<[String: BlazeDocumentField]>()
            .evaluate { $0["tags"]?.value as? String == "linux" }
            .addPredicate { ($0["views"]?.value as? Int ?? 0) < 10 }
            .sort { lhs, rhs in
                let l = lhs["priority"]?.value as? Double ?? 0
                let r = rhs["priority"]?.value as? Double ?? 0
                return l > r
            }
            .range(0..<1)
        let result = query.apply(to: testDocs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?["title"], .string("Swift"))
    }
    
    
}
