//
//  IOFaultInjectionTests.swift
//  BlazeDBTests
//
//  Tests for I/O fault injection (rename failures during VACUUM)
//

import XCTest
@testable import BlazeDBCore

/// I/O fault injection tests focused on VACUUM file replacement behavior.
///
/// These tests simulate failures during the atomic rename steps of VACUUM and
/// verify that BlazeDB:
/// - Surfaces a clear error
/// - Keeps the database usable (no corruption)
final class IOFaultInjectionTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOFault-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }
    
    /// Simulate a rename failure during VACUUM and ensure:
    /// - VACUUM throws
    /// - Original database remains readable
    func testVacuumRenameFailure_RollbackLeavesDatabaseUsable() throws {
        let dbURL = tempDir.appendingPathComponent("iofault_vacuum.blazedb")
        let db = try BlazeDBClient(name: "IOFault", fileURL: dbURL, password: "iofault-pass-123")
        
        // Seed some data
        let ids = try (0..<50).map { i -> UUID in
            try db.insert(BlazeDataRecord([
                "value": .int(i),
                "payload": .string("record-\(i)")
            ]))
        }
        
        try db.persist()
        
        // Enable simulated rename failure
        setenv("BLAZEDB_SIMULATE_VACUUM_RENAME_FAILURE", "1", 1)
        defer { unsetenv("BLAZEDB_SIMULATE_VACUUM_RENAME_FAILURE") }
        
        // VACUUM should throw, not corrupt
        do {
            _ = try db.vacuum()
            XCTFail("VACUUM should have thrown due to simulated rename failure")
        } catch {
            // Expected: transactionFailed or similar
        }
        
        // Database should still be usable after the failure
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, ids.count, "All records should still be present after VACUUM rollback")
        
        // Verify we can still write and read
        let newID = try db.insert(BlazeDataRecord(["value": .int(999)]))
        let fetched = try db.fetch(id: newID)
        XCTAssertEqual(fetched?.int("value"), 999)
    }
}


