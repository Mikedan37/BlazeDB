//
//  ErrorSurfaceTests.swift
//  BlazeDBTests
//
//  Tests error message stability and readability
//

import Foundation
import XCTest
@testable import BlazeDBCore

final class ErrorSurfaceTests: XCTestCase {
    
    func testErrorCategories() {
        XCTAssertEqual(BlazeDBError.corruptedData(location: "page 5", reason: "invalid header").category, .corruption)
        XCTAssertEqual(BlazeDBError.invalidField(name: "age", expectedType: "Int", actualType: "String").category, .schemaMismatch)
        XCTAssertEqual(BlazeDBError.indexNotFound(field: "email").category, .missingIndex)
        XCTAssertEqual(BlazeDBError.passwordTooWeak(requirements: "8+ chars").category, .encryptionKey)
        XCTAssertEqual(BlazeDBError.diskFull().category, .ioFailure)
        XCTAssertEqual(BlazeDBError.invalidInput(reason: "bad input").category, .invalidInput)
        XCTAssertEqual(BlazeDBError.transactionFailed("test").category, .transaction)
        XCTAssertEqual(BlazeDBError.migrationFailed("test").category, .migration)
    }
    
    func testErrorMessagesAreReadable() {
        let errors: [BlazeDBError] = [
            .corruptedData(location: "page 5", reason: "invalid header"),
            .invalidField(name: "age", expectedType: "Int", actualType: "String"),
            .indexNotFound(field: "email", availableIndexes: ["name", "id"]),
            .passwordTooWeak(requirements: "8+ characters"),
            .diskFull(availableSpace: 1024 * 1024),
            .databaseLocked(operation: "open", path: URL(fileURLWithPath: "/test.db")),
            .recordNotFound(id: UUID()),
            .transactionFailed("test failure")
        ]
        
        for error in errors {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.isEmpty, "Error message should not be empty")
            XCTAssertFalse(description.contains("BlazeDBError"), "Error message should not contain type name")
            XCTAssertTrue(description.count > 20, "Error message should be descriptive")
            
            // Check guidance exists
            let guidance = error.guidance
            XCTAssertFalse(guidance.isEmpty, "Guidance should not be empty")
            XCTAssertTrue(guidance.count > 10, "Guidance should be helpful")
        }
    }
    
    func testErrorCategoryNames() {
        let error = BlazeDBError.corruptedData(location: "test", reason: "test")
        XCTAssertEqual(error.categoryName, "Data Corruption")
        
        let indexError = BlazeDBError.indexNotFound(field: "test")
        XCTAssertEqual(indexError.categoryName, "Missing Index")
    }
    
    func testFormattedDescription() {
        let error = BlazeDBError.corruptedData(location: "page 5", reason: "invalid header")
        let formatted = error.formattedDescription
        
        XCTAssertTrue(formatted.contains("Data Corruption"), "Should include category")
        XCTAssertTrue(formatted.contains("💡"), "Should include guidance marker")
        XCTAssertTrue(formatted.contains("backup"), "Should include actionable guidance")
    }
}
