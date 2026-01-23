//
//  SchemaMigrationTests.swift
//  BlazeDBTests
//
//  Tests for schema migration system
//  Validates explicit migrations, versioning, and error handling
//

import Foundation
import XCTest
@testable import BlazeDBCore

final class SchemaMigrationTests: XCTestCase {
    
    var tempURL: URL!
    let password = "test-password-123"
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".blazedb")
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // MARK: - SchemaVersion Tests
    
    func testSchemaVersion_Comparable() {
        let v1_0 = SchemaVersion(major: 1, minor: 0)
        let v1_1 = SchemaVersion(major: 1, minor: 1)
        let v2_0 = SchemaVersion(major: 2, minor: 0)
        
        XCTAssertTrue(v1_0 < v1_1)
        XCTAssertTrue(v1_1 < v2_0)
        XCTAssertTrue(v1_0 == SchemaVersion(major: 1, minor: 0))
    }
    
    func testSchemaVersion_Description() {
        let version = SchemaVersion(major: 2, minor: 5)
        XCTAssertEqual(version.description, "2.5")
    }
    
    // MARK: - Migration Protocol Tests
    
    struct TestMigration_1_0_to_1_1: BlazeDBMigration {
        var from: SchemaVersion { SchemaVersion(major: 1, minor: 0) }
        var to: SchemaVersion { SchemaVersion(major: 1, minor: 1) }
        
        func up(db: BlazeDBClient) throws {
            // Add "version" field to all records
            let records = try db.fetchAll()
            for record in records {
                if let id = record.storage["id"]?.uuidValue {
                    var updated = record.storage
                    updated["version"] = .string("1.1")
                    try db.update(id: id, with: BlazeDataRecord(updated))
                }
            }
        }
        
        func down(db: BlazeDBClient) throws {
            // Remove "version" field
            let records = try db.fetchAll()
            for record in records {
                if let id = record.storage["id"]?.uuidValue {
                    var updated = record.storage
                    updated.removeValue(forKey: "version")
                    try db.update(id: id, with: BlazeDataRecord(updated))
                }
            }
        }
    }
    
    struct TestMigration_1_1_to_1_2: BlazeDBMigration {
        var from: SchemaVersion { SchemaVersion(major: 1, minor: 1) }
        var to: SchemaVersion { SchemaVersion(major: 1, minor: 2) }
        
        func up(db: BlazeDBClient) throws {
            // Add "migrated" field
            let records = try db.fetchAll()
            for record in records {
                if let id = record.storage["id"]?.uuidValue {
                    var updated = record.storage
                    updated["migrated"] = .bool(true)
                    try db.update(id: id, with: BlazeDataRecord(updated))
                }
            }
        }
        
        func down(db: BlazeDBClient) throws {
            // Remove "migrated" field
            let records = try db.fetchAll()
            for record in records {
                if let id = record.storage["id"]?.uuidValue {
                    var updated = record.storage
                    updated.removeValue(forKey: "migrated")
                    try db.update(id: id, with: BlazeDataRecord(updated))
                }
            }
        }
    }
    
    // MARK: - Migration Planning Tests
    
    func testMigrationPlan_NoMigrationNeeded() {
        let current = SchemaVersion(major: 1, minor: 0)
        let target = SchemaVersion(major: 1, minor: 0)
        let migrations: [BlazeDBMigration] = []
        
        let plan = MigrationPlanner.plan(
            from: current,
            to: target,
            migrations: migrations
        )
        
        XCTAssertTrue(plan.isValid)
        XCTAssertEqual(plan.migrations.count, 0)
    }
    
    func testMigrationPlan_ValidChain() {
        let current = SchemaVersion(major: 1, minor: 0)
        let target = SchemaVersion(major: 1, minor: 2)
        let migrations: [BlazeDBMigration] = [
            TestMigration_1_0_to_1_1(),
            TestMigration_1_1_to_1_2()
        ]
        
        let plan = MigrationPlanner.plan(
            from: current,
            to: target,
            migrations: migrations
        )
        
        XCTAssertTrue(plan.isValid, "Plan should be valid")
        XCTAssertEqual(plan.migrations.count, 2, "Should have 2 migrations")
        XCTAssertEqual(plan.migrations[0].from, SchemaVersion(major: 1, minor: 0))
        XCTAssertEqual(plan.migrations[0].to, SchemaVersion(major: 1, minor: 1))
        XCTAssertEqual(plan.migrations[1].from, SchemaVersion(major: 1, minor: 1))
        XCTAssertEqual(plan.migrations[1].to, SchemaVersion(major: 1, minor: 2))
    }
    
    func testMigrationPlan_MissingMigration_Fails() {
        let current = SchemaVersion(major: 1, minor: 0)
        let target = SchemaVersion(major: 1, minor: 2)
        let migrations: [BlazeDBMigration] = [
            TestMigration_1_0_to_1_1()
            // Missing 1.1 -> 1.2
        ]
        
        let plan = MigrationPlanner.plan(
            from: current,
            to: target,
            migrations: migrations
        )
        
        XCTAssertFalse(plan.isValid, "Plan should be invalid")
        XCTAssertTrue(plan.errors.contains { $0.contains("gap") }, "Should report gap")
    }
    
    func testMigrationPlan_InvalidOrder_Fails() {
        let current = SchemaVersion(major: 1, minor: 0)
        let target = SchemaVersion(major: 1, minor: 2)
        let migrations: [BlazeDBMigration] = [
            TestMigration_1_1_to_1_2(),  // Wrong order
            TestMigration_1_0_to_1_1()
        ]
        
        let plan = MigrationPlanner.plan(
            from: current,
            to: target,
            migrations: migrations
        )
        
        XCTAssertFalse(plan.isValid, "Plan should be invalid")
    }
    
    // MARK: - Migration Execution Tests
    
    func testMigrationExecution_Success() throws {
        // Create database
        let db = try BlazeDBClient(name: "migration-test", fileURL: tempURL, password: password)
        
        // Insert test record
        let id = try db.insert(BlazeDataRecord(["name": .string("Test")]))
        
        // Set initial version
        try db.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        
        // Plan migration
        let plan = MigrationPlanner.plan(
            from: SchemaVersion(major: 1, minor: 0),
            to: SchemaVersion(major: 1, minor: 1),
            migrations: [TestMigration_1_0_to_1_1()]
        )
        
        // Execute migration
        let result = try db.executeMigration(plan: plan, dryRun: false)
        
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.migrationsApplied, 1)
        
        // Verify migration applied
        let record = try db.fetch(id: id)
        XCTAssertNotNil(record?.storage["version"])
        XCTAssertEqual(record?.storage["version"], .string("1.1"))
        
        // Verify version updated
        let newVersion = try db.getSchemaVersion()
        XCTAssertEqual(newVersion, SchemaVersion(major: 1, minor: 1))
    }
    
    func testMigrationExecution_DryRun_NoMutation() throws {
        let db = try BlazeDBClient(name: "dryrun-test", fileURL: tempURL, password: password)
        let id = try db.insert(BlazeDataRecord(["name": .string("Test")]))
        try db.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        
        let plan = MigrationPlanner.plan(
            from: SchemaVersion(major: 1, minor: 0),
            to: SchemaVersion(major: 1, minor: 1),
            migrations: [TestMigration_1_0_to_1_1()]
        )
        
        // Dry run
        let result = try db.executeMigration(plan: plan, dryRun: true)
        
        XCTAssertTrue(result.success)
        
        // Verify no mutation
        let record = try db.fetch(id: id)
        XCTAssertNil(record?.storage["version"], "Dry run should not mutate data")
    }
    
    func testMigrationExecution_InvalidPlan_Fails() throws {
        let db = try BlazeDBClient(name: "invalid-test", fileURL: tempURL, password: password)
        
        let invalidPlan = MigrationPlan(
            currentVersion: SchemaVersion(major: 1, minor: 0),
            targetVersion: SchemaVersion(major: 1, minor: 2),
            migrations: [],
            isValid: false,
            errors: ["Missing migration"]
        )
        
        do {
            _ = try db.executeMigration(plan: invalidPlan, dryRun: false)
            XCTFail("Should have thrown error")
        } catch let error as BlazeDBError {
            if case .migrationFailed = error {
                // Expected
            } else {
                XCTFail("Expected migrationFailed error")
            }
        }
    }
    
    // MARK: - Version Validation Tests
    
    func testVersionValidation_Match_Succeeds() throws {
        let db = try BlazeDBClient(name: "version-test", fileURL: tempURL, password: password)
        try db.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        
        // Should not throw
        try db.validateSchemaVersion(expectedVersion: SchemaVersion(major: 1, minor: 0))
    }
    
    func testVersionValidation_Older_Fails() throws {
        let db = try BlazeDBClient(name: "older-test", fileURL: tempURL, password: password)
        try db.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        
        do {
            try db.validateSchemaVersion(expectedVersion: SchemaVersion(major: 1, minor: 1))
            XCTFail("Should have thrown error")
        } catch let error as BlazeDBError {
            if case .migrationFailed = error {
                // Expected
            } else {
                XCTFail("Expected migrationFailed error")
            }
        }
    }
    
    func testVersionValidation_Newer_Fails() throws {
        let db = try BlazeDBClient(name: "newer-test", fileURL: tempURL, password: password)
        try db.setSchemaVersion(SchemaVersion(major: 1, minor: 1))
        
        do {
            try db.validateSchemaVersion(expectedVersion: SchemaVersion(major: 1, minor: 0))
            XCTFail("Should have thrown error")
        } catch let error as BlazeDBError {
            if case .migrationFailed = error {
                // Expected
            } else {
                XCTFail("Expected migrationFailed error")
            }
        }
    }
}
