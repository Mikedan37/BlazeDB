//
//  GuardrailTests.swift
//  BlazeDBTests
//
//  Tests for guardrails (schema validation, restore conflicts)
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class GuardrailTests: XCTestCase {
    
    private var tempDir: URL?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tempDir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    private func uniqueName(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString)"
    }
    
    // MARK: - Schema Validation Guardrails
    
    func testValidateSchemaVersion_OlderDatabase_Fails() throws {
        let db = try BlazeDBClient.openForTesting(name: uniqueName("testdb"), password: "TestPassword-123!")
        defer { try? db.close() }
        
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
        let db = try BlazeDBClient.openForTesting(name: uniqueName("testdb"), password: "TestPassword-123!")
        defer { try? db.close() }
        
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
        let db = try BlazeDBClient.openForTesting(name: uniqueName("testdb"), password: "TestPassword-123!")
        defer { try? db.close() }
        
        // Set version
        try db.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        
        // Validate with same version
        XCTAssertNoThrow(try db.validateSchemaVersion(expectedVersion: SchemaVersion(major: 1, minor: 0)))
    }
    
    func testOpenWithSchemaValidation_Mismatch_Fails() throws {
        // Create database with version 1.0
        let dbName = uniqueName("testdb")
        let db1 = try BlazeDBClient.openForTesting(name: dbName, password: "TestPassword-123!")
        defer { try? db1.close() }
        try db1.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        
        // Try to open with version 1.1 (should fail)
        XCTAssertThrowsError(
            try BlazeDBClient.openWithSchemaValidation(
                name: dbName,
                password: "TestPassword-123!",
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
        let db = try BlazeDBClient.openForTesting(name: uniqueName("testdb"), password: "TestPassword-123!")
        defer { try? db.close() }
        
        // Insert a record
        try db.insert(BlazeDataRecord(["name": .string("Existing")]))
        
        // Create dump
        let dumpURL = try XCTUnwrap(tempDir).appendingPathComponent("dump.blazedump")
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
        let db1 = try BlazeDBClient.openForTesting(name: uniqueName("db1"), password: "TestPassword-123!")
        let db2 = try BlazeDBClient.openForTesting(name: uniqueName("db2"), password: "TestPassword-123!")
        defer { try? db1.close() }
        defer { try? db2.close() }
        
        // Set different schema versions
        try db1.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        try db2.setSchemaVersion(SchemaVersion(major: 1, minor: 1))
        
        // Create dump from db1
        let dumpURL = try XCTUnwrap(tempDir).appendingPathComponent("dump.blazedump")
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
        let db1 = try BlazeDBClient.openForTesting(name: uniqueName("db1"), password: "TestPassword-123!")
        let db2 = try BlazeDBClient.openForTesting(name: uniqueName("db2"), password: "TestPassword-123!")
        defer { try? db1.close() }
        defer { try? db2.close() }
        
        // Set different schema versions
        try db1.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        try db2.setSchemaVersion(SchemaVersion(major: 1, minor: 1))
        
        // Insert record in db1
        try db1.insert(BlazeDataRecord(["name": .string("Test")]))
        
        // Create dump from db1
        let dumpURL = try XCTUnwrap(tempDir).appendingPathComponent("dump.blazedump")
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
