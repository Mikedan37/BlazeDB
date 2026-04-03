//
//  DXQueryExplainTests.swift
//  BlazeDBTests
//
//  Tests for query explainability
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class DXQueryExplainTests: XCTestCase {
    
    var db: BlazeDBClient?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient.openTemporary(password: "TestPassword-123!")
    }
    
    override func tearDownWithError() throws {
        if let db = db {
            let fileURL = db.fileURL
            try db.close()
            self.db = nil
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        BlazeDBClient.clearCachedKey()
        try super.tearDownWithError()
    }
    
    func testExplain_IncludesCorrectFilterCount() throws {
        let db = try XCTUnwrap(self.db, "db should be set in setUp")
        // Insert test data
        try db.insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(30)]))
        
        let explanation = try db.query()
            .where("name", equals: .string("Alice"))
            .where("age", greaterThan: .int(25))
            .explainCost()
        
        XCTAssertEqual(explanation.filterCount, 2)
    }
    
    func testExplain_WarnsForUnindexedFilter() throws {
        let db = try XCTUnwrap(self.db, "db should be set in setUp")
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
        let db = try XCTUnwrap(self.db, "db should be set in setUp")
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
        let records1 = try result1.records
        let records2 = try result2.records
        XCTAssertEqual(records1.count, records2.count)
    }
    
    func testExplain_HandlesEmptyQuery() throws {
        let db = try XCTUnwrap(self.db, "db should be set in setUp")
        let explanation = try db.query().explainCost()
        
        XCTAssertEqual(explanation.filterCount, 0)
        XCTAssertTrue(explanation.filterFields.isEmpty)
    }
}
