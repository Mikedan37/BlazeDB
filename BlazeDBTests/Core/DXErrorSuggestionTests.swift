//
//  DXErrorSuggestionTests.swift
//  BlazeDBTests
//
//  Tests for enhanced error messages with suggestions
//

import XCTest
@testable import BlazeDBCore

final class DXErrorSuggestionTests: XCTestCase {
    
    func testUnknownField_ProducesSuggestions() {
        let availableFields = ["user_id", "user_name", "email", "created_at"]
        let suggestions = BlazeDBError.suggestFieldNames(
            targetField: "userId",
            availableFields: availableFields
        )
        
        // Should suggest "user_id" (prefix match)
        XCTAssertTrue(suggestions.contains("user_id"))
    }
    
    func testSchemaMismatchError_IncludesActionableGuidance() {
        let error = BlazeDBError.migrationFailed(
            "Database schema version (1.0) is older than expected (1.1). Migrations required.",
            underlyingError: nil
        )
        
        let message = error.suggestedMessage
        
        // Should include suggestion
        XCTAssertTrue(message.contains("💡"))
        XCTAssertTrue(message.contains("Suggestion"))
        XCTAssertTrue(message.contains("backup") || message.contains("doctor"))
    }
    
    func testRestoreConflictError_IncludesRemediationSteps() {
        let error = BlazeDBError.invalidInput(
            reason: "Cannot restore to non-empty database. Database has 10 records. Clear database first or use a new database."
        )
        
        let message = error.suggestedMessage
        
        // Should include remediation
        XCTAssertTrue(message.contains("💡"))
        XCTAssertTrue(message.contains("Suggestion"))
    }
    
    func testErrorMessages_AreStable() {
        // Test that error messages are deterministic
        let error1 = BlazeDBError.recordNotFound(id: UUID(), collection: "users", suggestion: nil)
        let error2 = BlazeDBError.recordNotFound(id: UUID(), collection: "users", suggestion: nil)
        
        // Messages should be similar (same structure, different IDs)
        let msg1 = error1.suggestedMessage
        let msg2 = error2.suggestedMessage
        
        // Both should contain key phrases
        XCTAssertTrue(msg1.contains("Record not found"))
        XCTAssertTrue(msg2.contains("Record not found"))
        XCTAssertTrue(msg1.contains("💡"))
        XCTAssertTrue(msg2.contains("💡"))
    }
    
    func testFieldSuggestion_HandlesEmptyList() {
        let suggestions = BlazeDBError.suggestFieldNames(
            targetField: "userId",
            availableFields: []
        )
        
        XCTAssertTrue(suggestions.isEmpty)
    }
    
    func testFieldSuggestion_HandlesExactMatch() {
        let suggestions = BlazeDBError.suggestFieldNames(
            targetField: "userId",
            availableFields: ["userId", "user_id", "userName"]
        )
        
        // Exact match should return immediately
        XCTAssertEqual(suggestions, ["userId"])
    }
}
