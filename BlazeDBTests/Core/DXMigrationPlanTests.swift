//
//  DXMigrationPlanTests.swift
//  BlazeDBTests
//
//  Tests for migration plan pretty printing
//

import XCTest
@testable import BlazeDBCore

final class DXMigrationPlanTests: XCTestCase {
    
    func testPrettyPrint_IncludesVersions() {
        let plan = MigrationPlan(
            currentVersion: SchemaVersion(major: 1, minor: 0),
            targetVersion: SchemaVersion(major: 1, minor: 1),
            migrations: []
        )
        
        let output = plan.prettyDescription()
        
        XCTAssertTrue(output.contains("Current Version: 1.0"))
        XCTAssertTrue(output.contains("Target Version: 1.1"))
    }
    
    func testPrettyPrint_IncludesMigrationsList() {
        struct TestMigration: BlazeDBMigration {
            let name = "TestMigration"
            let fromVersion = SchemaVersion(major: 1, minor: 0)
            let toVersion = SchemaVersion(major: 1, minor: 1)
            
            func up(db: BlazeDBClient) throws {
                // Test migration
            }
        }
        
        let migration = TestMigration()
        let plan = MigrationPlan(
            currentVersion: SchemaVersion(major: 1, minor: 0),
            targetVersion: SchemaVersion(major: 1, minor: 1),
            migrations: [migration]
        )
        
        let output = plan.prettyDescription()
        
        XCTAssertTrue(output.contains("TestMigration"))
        XCTAssertTrue(output.contains("1.0 → 1.1"))
    }
    
    func testPrettyPrint_DestructiveFlagShows() {
        struct DestructiveMigration: BlazeDBMigration {
            let name = "DestructiveMigration"
            let fromVersion = SchemaVersion(major: 1, minor: 0)
            let toVersion = SchemaVersion(major: 1, minor: 1)
            
            var isDestructive: Bool? { return true }
            var summary: String? { return "Removes old data" }
            
            func up(db: BlazeDBClient) throws {
                // Destructive migration
            }
        }
        
        let migration = DestructiveMigration()
        let plan = MigrationPlan(
            currentVersion: SchemaVersion(major: 1, minor: 0),
            targetVersion: SchemaVersion(major: 1, minor: 1),
            migrations: [migration]
        )
        
        let output = plan.prettyDescription()
        
        XCTAssertTrue(output.contains("DESTRUCTIVE OPERATION"))
        XCTAssertTrue(output.contains("WARNING"))
    }
    
    func testPrettyPrint_OutputOrderIsStable() {
        struct Migration1: BlazeDBMigration {
            let name = "Migration1"
            let fromVersion = SchemaVersion(major: 1, minor: 0)
            let toVersion = SchemaVersion(major: 1, minor: 1)
            func up(db: BlazeDBClient) throws {}
        }
        
        struct Migration2: BlazeDBMigration {
            let name = "Migration2"
            let fromVersion = SchemaVersion(major: 1, minor: 1)
            let toVersion = SchemaVersion(major: 1, minor: 2)
            func up(db: BlazeDBClient) throws {}
        }
        
        let plan = MigrationPlan(
            currentVersion: SchemaVersion(major: 1, minor: 0),
            targetVersion: SchemaVersion(major: 1, minor: 2),
            migrations: [Migration1(), Migration2()]
        )
        
        let output1 = plan.prettyDescription()
        let output2 = plan.prettyDescription()
        
        // Output should be identical (deterministic)
        XCTAssertEqual(output1, output2)
        
        // Order should be correct
        let migration1Index = output1.range(of: "1. Migration1")
        let migration2Index = output1.range(of: "2. Migration2")
        XCTAssertNotNil(migration1Index)
        XCTAssertNotNil(migration2Index)
        XCTAssertTrue(migration1Index!.lowerBound < migration2Index!.lowerBound)
    }
}
