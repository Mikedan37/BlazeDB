//
//  QueryErgonomicsTests.swift
//  BlazeDBTests
//
//  Tests for query validation and error messages
//  Verifies error messages are stable, readable, and actionable
//

import Foundation
import XCTest
@testable import BlazeDBCore

final class QueryErgonomicsTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    let password = "test-password-123"
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".blazedb")
        db = try BlazeDBClient(name: "test", fileURL: tempURL, password: password)
        
        // Insert test records
        try db.insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(30), "active": .bool(true)]))
        try db.insert(BlazeDataRecord(["name": .string("Bob"), "age": .int(25), "active": .bool(false)]))
        try db.insert(BlazeDataRecord(["name": .string("Charlie"), "age": .int(35), "role": .string("admin")]))
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // MARK: - Field Name Validation
    
    func testInvalidSortField_ProvidesSuggestions() throws {
        do {
            _ = try db.query()
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
    
    func testInvalidGroupByField_FailsWithHelpfulMessage() throws {
        do {
            _ = try db.query()
                .groupBy("namme")  // Typo: "namme" instead of "name"
                .count()
                .execute()
            XCTFail("Should have thrown error for invalid groupBy field")
        } catch let error as BlazeDBError {
            if case .invalidQuery(let reason, let suggestion) = error {
                XCTAssertTrue(reason.contains("namme"), "Error should mention invalid field")
                XCTAssertNotNil(suggestion, "Should provide suggestion")
            } else {
                XCTFail("Expected invalidQuery error, got \(error)")
            }
        }
    }
    
    func testValidFields_Succeed() throws {
        // Valid sort field
        let result1 = try db.query()
            .orderBy("age", descending: false)
            .execute()
        XCTAssertNotNil(result1)
        
        // Valid groupBy field
        let result2 = try db.query()
            .groupBy("name")
            .count()
            .execute()
        XCTAssertNotNil(result2)
    }
    
    // MARK: - Error Message Stability
    
    func testErrorMessagesAreStable() throws {
        // Test that error messages don't change unexpectedly
        do {
            _ = try db.query()
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
    
    func testErrorMessagesIncludeGuidance() throws {
        do {
            _ = try db.query()
                .groupBy("invalid_field_xyz")
                .count()
                .execute()
            XCTFail("Should have thrown error")
        } catch let error as BlazeDBError {
            if case .invalidQuery(let reason, let suggestion) = error {
                XCTAssertNotNil(suggestion, "Error should include suggestion")
                XCTAssertTrue(suggestion?.count ?? 0 > 10, "Suggestion should be helpful")
            } else {
                XCTFail("Expected invalidQuery error")
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
        
        XCTAssertEqual(result.records.count, 0, "Empty collection should return empty results")
        
        try? FileManager.default.removeItem(at: emptyURL)
    }
}
