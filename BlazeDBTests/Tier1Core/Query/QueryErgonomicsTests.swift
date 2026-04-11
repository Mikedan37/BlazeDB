//
//  QueryErgonomicsTests.swift
//  BlazeDBTests
//
//  Tests for query validation and error messages
//  Verifies error messages are stable, readable, and actionable
//

import Foundation
import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class QueryErgonomicsTests: LinuxTier1NonCryptoKDFHarness {
    
    private var tempURL: URL?
    private var db: BlazeDBClient?
    let password = "TestPassword-123!"
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".blazedb")
        db = try BlazeDBClient(name: "test", fileURL: try requireFixture(tempURL), password: password)
        
        // Insert test records
        try requireFixture(db).insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(30), "active": .bool(true)]))
        try requireFixture(db).insert(BlazeDataRecord(["name": .string("Bob"), "age": .int(25), "active": .bool(false)]))
        try requireFixture(db).insert(BlazeDataRecord(["name": .string("Charlie"), "age": .int(35), "role": .string("admin")]))
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: try requireFixture(tempURL))
    }
    
    // MARK: - Field Name Validation
    
    func testInvalidSortField_ProvidesSuggestions() throws {
        do {
            _ = try requireFixture(db).query()
                .orderBy("agge", descending: false)  // Typo: "agge" instead of "age"
                .execute()
            XCTFail("Should have thrown error for invalid sort field")
        } catch let error as BlazeDBError {
            if case .invalidQuery(let reason, let suggestion) = error {
                XCTAssertTrue(reason.contains("agge"), "Error should mention invalid field")
                XCTAssertNotNil(suggestion, "Should provide suggestion")
                XCTAssertTrue(suggestion?.contains("age") == true || suggestion?.contains("Available fields") == true, 
                            "Suggestion should mention 'age' or available fields")
            } else {
                XCTFail("Expected invalidQuery error, got \(error)")
            }
        }
    }
    
    /// GROUP BY on a field absent from every row is allowed (SQL-style): all rows share one
    /// missing-key bucket. Validation only logs best-effort hints; see `validateGroupByFields`
    /// and `AggregationTests.testGroupByOnMissingField`.
    func testGroupByFieldAbsentFromAllRecords_SingleMissingBucketAndTotalCount() throws {
        let absentFields = ["namme", "invalid_field_xyz"]
        for field in absentFields {
            let result = try requireFixture(db).query()
                .groupBy(field)
                .count()
                .execute()
            let grouped = try result.grouped
            XCTAssertEqual(
                grouped.groups.count,
                1,
                "Expected one group for missing key '\(field)' (all rows bucket as missing)"
            )
            XCTAssertNotNil(grouped.groups["null"], "Missing-key bucket should use composite key 'null'")
            XCTAssertEqual(
                grouped.groups["null"]?.count,
                3,
                "All fixture rows should be counted in the missing-key bucket for '\(field)'"
            )
            XCTAssertEqual(grouped.totalCount, 3, "totalCount should match fixture size for '\(field)'")
        }
    }
    
    func testValidFields_Succeed() throws {
        // Valid sort field
        let result1 = try requireFixture(db).query()
            .orderBy("age", descending: false)
            .execute()
        XCTAssertNotNil(result1)
        
        // Valid groupBy field
        let result2 = try requireFixture(db).query()
            .groupBy("name")
            .count()
            .execute()
        XCTAssertNotNil(result2)
    }
    
    // MARK: - Error Message Stability
    
    func testErrorMessagesAreStable() throws {
        // Test that error messages don't change unexpectedly
        do {
            _ = try requireFixture(db).query()
                .orderBy("nonexistent", descending: false)
                .execute()
            XCTFail("Should have thrown error")
        } catch let error as BlazeDBError {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.isEmpty, "Error message should not be empty")
            XCTAssertFalse(description.contains("BlazeDBError"), "Error message should not contain type name")
            XCTAssertTrue(description.count > 20, "Error message should be descriptive")
        }
    }
    
    /// Sort field validation still throws `invalidQuery` with suggestions; GROUP BY does not.
    func testInvalidOrderByField_IncludesGuidanceInInvalidQuery() throws {
        do {
            _ = try requireFixture(db).query()
                .orderBy("invalid_field_xyz", descending: false)
                .execute()
            XCTFail("Should have thrown error for invalid sort field")
        } catch let error as BlazeDBError {
            if case .invalidQuery(_, let suggestion) = error {
                XCTAssertNotNil(suggestion, "Error should include suggestion")
                XCTAssertTrue(suggestion?.count ?? 0 > 10, "Suggestion should be helpful")
            } else {
                XCTFail("Expected invalidQuery error, got \(error)")
            }
        }
    }
    
    // MARK: - Empty Collection Handling
    
    func testEmptyCollection_DoesNotCrash() throws {
        // Create empty database
        let emptyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".blazedb")
        let emptyDB = try BlazeDBClient(name: "empty", fileURL: emptyURL, password: password)
        
        // Query on empty collection should not crash
        let result = try emptyDB.query()
            .orderBy("age", descending: false)
            .execute()
        
        XCTAssertEqual(try result.records.count, 0, "Empty collection should return empty results")
        
        try? FileManager.default.removeItem(at: emptyURL)
    }
}
