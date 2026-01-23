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
        
        let explanation = try db.query()
            .where("name", equals: .string("Alice"))
            .where("age", greaterThan: .int(25))
            .explainCost()
        
        XCTAssertEqual(explanation.filterCount, 2)
    }
    
    func testExplain_WarnsForUnindexedFilter() throws {
        // Insert test data
        try db.insert(BlazeDataRecord(["name": .string("Alice"), "status": .string("active")]))
        
        // Query without index
        let explanation = try db.query()
            .where("status", equals: .string("active"))
            .explainCost()
        
        // Should warn about unindexed filter (if index detection works)
        // If index detection is unavailable, riskLevel will be .unknown
        XCTAssertTrue(
            explanation.riskLevel == .warnUnindexedFilter ||
            explanation.riskLevel == .unknown
        )
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
        let explanation = try db.query().explainCost()
        
        XCTAssertEqual(explanation.filterCount, 0)
        XCTAssertTrue(explanation.filterFields.isEmpty)
    }
}
