//
//  DXQueryExplainTests.swift
//  BlazeDBTests
//
//  Tests for query explainability
//

import XCTest
@testable import BlazeDBCore

final class DXQueryExplainTests: XCTestCase {
    
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        db = try! BlazeDBClient.openTemporary(password: "test-password")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: db.fileURL)
        super.tearDown()
    }
    
    func testExplain_IncludesCorrectFilterCount() throws {
        // Insert test data
        try db.insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(30)]))
        
        let plan = try db.query()
            .where("name", equals: .string("Alice"))
            .where("age", greaterThan: .int(25))
            .explain()
        
        XCTAssertEqual(plan.filterPredicateCount, 2)
        XCTAssertEqual(Set(plan.referencedFilterFields), ["age", "name"])
    }
    
    func testExplain_WarnsForUnindexedFilter() throws {
        // Insert test data
        try db.insert(BlazeDataRecord(["name": .string("Alice"), "status": .string("active")]))
        
        // Query without index
        let plan = try db.query()
            .where("status", equals: .string("active"))
            .explain()
        
        XCTAssertEqual(plan.filterPredicateCount, 1)
        XCTAssertEqual(plan.referencedFilterFields, ["status"])
        XCTAssertTrue(plan.candidateIndexes.isEmpty)
        XCTAssertTrue(plan.steps.contains { if case .tableScan = $0.type { return true }; return false })
        XCTAssertTrue(plan.steps.contains { if case .filter = $0.type { return true }; return false })
    }
    
    func testExecuteWithWarnings_ReturnsSameResultsAsExecute() throws {
        // Insert test data
        let id1 = try db.insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(30)]))
        let id2 = try db.insert(BlazeDataRecord(["name": .string("Bob"), "age": .int(25)]))
        
        // Execute with warnings
        let result1 = try db.query()
            .where("age", greaterThan: .int(20))
            .executeWithWarnings()
        
        // Execute normally
        let result2 = try db.query()
            .where("age", greaterThan: .int(20))
            .execute()
        
        // Results should be identical
        XCTAssertEqual(result1.records.count, result2.records.count)
        XCTAssertEqual(result1.records.map { $0.id }, result2.records.map { $0.id })
    }
    
    func testExplain_HandlesEmptyQuery() throws {
        let plan = try db.query().explain()
        
        XCTAssertEqual(plan.filterPredicateCount, 0)
        XCTAssertTrue(plan.referencedFilterFields.isEmpty)
    }
}
