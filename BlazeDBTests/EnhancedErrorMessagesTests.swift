//
//  EnhancedErrorMessagesTests.swift
//  BlazeDBTests
//
//  Tests for enhanced error messages with helpful context
//

import XCTest
@testable import BlazeDBCore

final class EnhancedErrorMessagesTests: XCTestCase {
    
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorTest-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "ErrorTest", fileURL: dbURL, password: "test-pass-123456")
    }
    
    override func tearDown() {
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    // MARK: - RecordNotFound Error
    
    func testRecordNotFoundError_IncludesID() async throws {
        print("❌ Testing recordNotFound error includes ID")
        
        let missingID = UUID()
        
        do {
            _ = try await db.fetch(id: missingID)
            XCTFail("Should throw error")
        } catch let error as BlazeDBError {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(description.contains(missingID.uuidString), "Should include ID")
            XCTAssertTrue(description.contains("deleted") || description.contains("existed"), "Should suggest reasons")
            print("  ✅ Error: \(description)")
        }
    }
    
    // MARK: - RecordExists Error
    
    func testRecordExistsError_IncludesID() async throws {
        print("❌ Testing recordExists error includes ID")
        
        let id = UUID()
        _ = try await db.insert(BlazeDataRecord(["value": .int(1)]), id: id)
        
        do {
            _ = try await db.insert(BlazeDataRecord(["value": .int(2)]), id: id)
            XCTFail("Should throw error for duplicate")
        } catch let error as BlazeDBError {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(description.contains(id.uuidString) || description.contains("exists"), "Should mention duplicate")
            XCTAssertTrue(description.contains("update") || description.contains("upsert"), "Should suggest alternatives")
            print("  ✅ Error: \(description)")
        }
    }
    
    // MARK: - InvalidQuery Error
    
    func testInvalidQueryError_IncludesSuggestion() {
        print("❌ Testing invalidQuery error includes suggestion")
        
        let error = BlazeDBError.invalidQuery(
            reason: "Cannot use field 'nonexistent'",
            suggestion: "Check field name spelling"
        )
        
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("Invalid query"))
        XCTAssertTrue(description.contains("nonexistent"))
        XCTAssertTrue(description.contains("Check field name"))
        
        print("  ✅ Error: \(description)")
    }
    
    // MARK: - IndexNotFound Error
    
    func testIndexNotFoundError_ShowsAvailableIndexes() {
        print("❌ Testing indexNotFound error shows available indexes")
        
        let error = BlazeDBError.indexNotFound(
            field: "priority",
            availableIndexes: ["status", "assignee", "created_at"]
        )
        
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("priority"))
        XCTAssertTrue(description.contains("status"))
        XCTAssertTrue(description.contains("assignee"))
        XCTAssertTrue(description.contains("createIndex"))
        
        print("  ✅ Error: \(description)")
    }
    
    // MARK: - InvalidField Error
    
    func testInvalidFieldError_ShowsExpectedVsActual() {
        print("❌ Testing invalidField error shows type mismatch")
        
        let error = BlazeDBError.invalidField(
            name: "priority",
            expectedType: "Int",
            actualType: "String"
        )
        
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("priority"))
        XCTAssertTrue(description.contains("Int"))
        XCTAssertTrue(description.contains("String"))
        
        print("  ✅ Error: \(description)")
    }
    
    // MARK: - DiskFull Error
    
    func testDiskFullError_ShowsAvailableSpace() {
        print("❌ Testing diskFull error shows available space")
        
        let error = BlazeDBError.diskFull(availableSpace: 10_485_760)  // 10 MB
        
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("10 MB") || description.contains("full"))
        XCTAssertTrue(description.contains("Free up"))
        
        print("  ✅ Error: \(description)")
    }
    
    // MARK: - DatabaseLocked Error
    
    func testDatabaseLockedError_ShowsOperation() {
        print("❌ Testing databaseLocked error shows operation")
        
        let error = BlazeDBError.databaseLocked(operation: "VACUUM", timeout: 30.0)
        
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("VACUUM"))
        XCTAssertTrue(description.contains("30"))
        XCTAssertTrue(description.contains("locked") || description.contains("retry"))
        
        print("  ✅ Error: \(description)")
    }
    
    // MARK: - CorruptedData Error
    
    func testCorruptedDataError_ShowsLocation() {
        print("❌ Testing corruptedData error shows location")
        
        let error = BlazeDBError.corruptedData(location: "Page 42", reason: "Invalid header")
        
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("Page 42"))
        XCTAssertTrue(description.contains("Invalid header"))
        XCTAssertTrue(description.contains("backup") || description.contains("corruption"))
        
        print("  ✅ Error: \(description)")
    }
    
    // MARK: - All Errors Have Descriptions
    
    func testAllErrorsHaveDescriptions() {
        print("❌ Testing all errors have helpful descriptions")
        
        let errors: [BlazeDBError] = [
            .recordExists(id: UUID()),
            .recordNotFound(id: UUID()),
            .transactionFailed("test"),
            .migrationFailed("test"),
            .invalidQuery(reason: "test"),
            .indexNotFound(field: "test"),
            .invalidField(name: "test", expectedType: "Int", actualType: "String"),
            .diskFull(),
            .permissionDenied(operation: "test"),
            .databaseLocked(operation: "test"),
            .corruptedData(location: "test", reason: "test"),
            .passwordTooWeak(requirements: "8+ chars"),
            .invalidData(reason: "test")
        ]
        
        for error in errors {
            let description = error.errorDescription
            XCTAssertNotNil(description, "Error should have description: \(error)")
            XCTAssertFalse(description!.isEmpty, "Description should not be empty")
        }
        
        print("  ✅ All \(errors.count) error types have helpful descriptions")
    }
}

