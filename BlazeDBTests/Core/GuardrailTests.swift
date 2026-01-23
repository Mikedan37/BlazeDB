//
//  GuardrailTests.swift
//  BlazeDBTests
//
//  Tests for guardrails (schema validation, restore conflicts)
//

import XCTest
@testable import BlazeDBCore

final class GuardrailTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Schema Validation Guardrails
    
    func testValidateSchemaVersion_OlderDatabase_Fails() throws {
        let db = try BlazeDBClient.openForTesting(name: "testdb", password: "test-password")
        
        // Set older version
        try db.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        
        // Try to validate with newer version
        XCTAssertThrowsError(try db.validateSchemaVersion(expectedVersion: SchemaVersion(major: 1, minor: 1))) { error in
            guard case BlazeDBError.migrationFailed(let reason, _) = error else {
                XCTFail("Expected migrationFailed error")
                return
            }
            XCTAssertTrue(reason.contains("older than expected"))
            XCTAssertTrue(reason.contains("Migrations required"))
        }
    }
    
    func testValidateSchemaVersion_NewerDatabase_Fails() throws {
        let db = try BlazeDBClient.openForTesting(name: "testdb", password: "test-password")
        
        // Set newer version
        try db.setSchemaVersion(SchemaVersion(major: 1, minor: 1))
        
        // Try to validate with older version
        XCTAssertThrowsError(try db.validateSchemaVersion(expectedVersion: SchemaVersion(major: 1, minor: 0))) { error in
            guard case BlazeDBError.migrationFailed(let reason, _) = error else {
                XCTFail("Expected migrationFailed error")
                return
            }
            XCTAssertTrue(reason.contains("newer than expected"))
            XCTAssertTrue(reason.contains("Application may be outdated"))
        }
    }
    
    func testValidateSchemaVersion_MatchingVersion_Succeeds() throws {
        let db = try BlazeDBClient.openForTesting(name: "testdb", password: "test-password")
        
        // Set version
        try db.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        
        // Validate with same version
        XCTAssertNoThrow(try db.validateSchemaVersion(expectedVersion: SchemaVersion(major: 1, minor: 0)))
    }
    
    func testOpenWithSchemaValidation_Mismatch_Fails() throws {
        // Create database with version 1.0
        let db1 = try BlazeDBClient.openForTesting(name: "testdb", password: "test-password")
        try db1.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        
        // Try to open with version 1.1 (should fail)
        XCTAssertThrowsError(
            try BlazeDBClient.openWithSchemaValidation(
                name: "testdb",
                password: "test-password",
                expectedVersion: SchemaVersion(major: 1, minor: 1)
            )
        ) { error in
            guard case BlazeDBError.migrationFailed = error else {
                XCTFail("Expected migrationFailed error")
                return
            }
        }
    }
    
    // MARK: - Restore Guardrails
    
    func testRestoreToNonEmptyDatabase_Fails() throws {
        let db = try BlazeDBClient.openForTesting(name: "testdb", password: "test-password")
        
        // Insert a record
        try db.insert(BlazeDataRecord(["name": .string("Existing")]))
        
        // Create dump
        let dumpURL = tempDir.appendingPathComponent("dump.blazedump")
        try db.export(to: dumpURL)
        
        // Try to restore to non-empty database (should fail)
        XCTAssertThrowsError(
            try BlazeDBImporter.restore(from: dumpURL, to: db, allowSchemaMismatch: false)
        ) { error in
            guard case BlazeDBError.invalidInput(let reason) = error else {
                XCTFail("Expected invalidInput error")
                return
            }
            XCTAssertTrue(reason.contains("non-empty database"))
            XCTAssertTrue(reason.contains("Clear database first"))
        }
    }
    
    func testRestoreSchemaMismatch_Fails() throws {
        let db1 = try BlazeDBClient.openForTesting(name: "db1", password: "test-password")
        let db2 = try BlazeDBClient.openForTesting(name: "db2", password: "test-password")
        
        // Set different schema versions
        try db1.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        try db2.setSchemaVersion(SchemaVersion(major: 1, minor: 1))
        
        // Create dump from db1
        let dumpURL = tempDir.appendingPathComponent("dump.blazedump")
        try db1.export(to: dumpURL)
        
        // Try to restore to db2 with mismatched schema (should fail)
        XCTAssertThrowsError(
            try BlazeDBImporter.restore(from: dumpURL, to: db2, allowSchemaMismatch: false)
        ) { error in
            guard case BlazeDBError.migrationFailed(let reason, _) = error else {
                XCTFail("Expected migrationFailed error")
                return
            }
            XCTAssertTrue(reason.contains("Schema version mismatch"))
            XCTAssertTrue(reason.contains("run migrations first"))
        }
    }
    
    func testRestoreSchemaMismatch_WithAllowOverride_Succeeds() throws {
        let db1 = try BlazeDBClient.openForTesting(name: "db1", password: "test-password")
        let db2 = try BlazeDBClient.openForTesting(name: "db2", password: "test-password")
        
        // Set different schema versions
        try db1.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        try db2.setSchemaVersion(SchemaVersion(major: 1, minor: 1))
        
        // Insert record in db1
        try db1.insert(BlazeDataRecord(["name": .string("Test")]))
        
        // Create dump from db1
        let dumpURL = tempDir.appendingPathComponent("dump.blazedump")
        try db1.export(to: dumpURL)
        
        // Restore with allowSchemaMismatch: true (should succeed)
        XCTAssertNoThrow(
            try BlazeDBImporter.restore(from: dumpURL, to: db2, allowSchemaMismatch: true)
        )
        
        // Verify record restored
        let results = try db2.query()
            .where("name", equals: .string("Test"))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 1)
    }
}
