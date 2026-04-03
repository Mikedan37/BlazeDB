//
//  LifecycleTests.swift
//  BlazeDBTests
//
//  Tests for process lifecycle safety: close(), idempotency, resource cleanup
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class LifecycleTests: XCTestCase {
    
    private var tempDir: URL?
    private var dbURL: URL?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tempDir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("lifecycle_test.blazedb")
    }
    
    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }
    
    // MARK: - Close Tests
    
    func testClose_IsIdempotent() throws {
        let db = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        
        // First close should succeed
        try db.close()
        XCTAssertTrue(try db.isClosed, "Database should be closed after close()")
        
        // Second close should be idempotent (no error)
        try db.close()
        XCTAssertTrue(try db.isClosed, "Database should still be closed after second close()")
    }
    
    func testClose_FlushesPendingChanges() throws {
        let db = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        
        // Insert a record
        let record = BlazeDataRecord(["name": .string("Test")])
        _ = try db.insert(record)
        
        // Close database
        try db.close()
        
        // Reopen and verify record exists
        let reopenedDB = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        let allRecords = try reopenedDB.fetchAll()
        XCTAssertEqual(allRecords.count, 1, "Record should persist after close")
        XCTAssertEqual(allRecords.first?.storage["name"], .string("Test"))
    }
    
    func testOperations_ThrowAfterClose() throws {
        let db = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        
        // Close database
        try db.close()
        
        // Operations should throw
        let record = BlazeDataRecord(["name": .string("Test")])
        
        XCTAssertThrowsError(try db.insert(record)) { error in
            XCTAssertTrue(error is BlazeDBError)
            if case .invalidInput(let reason) = error as? BlazeDBError {
                XCTAssertTrue(reason.contains("closed"), "Error should mention database is closed")
            }
        }
        
        XCTAssertThrowsError(try db.fetch(id: UUID())) { error in
            XCTAssertTrue(error is BlazeDBError)
        }
        
        XCTAssertThrowsError(try db.persist()) { error in
            XCTAssertTrue(error is BlazeDBError)
        }
    }
    
    func testDeinit_AutoCloses() throws {
        var db: BlazeDBClient? = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        
        // Insert a record
        let record = BlazeDataRecord(["name": .string("Test")])
        _ = try db!.insert(record)
        
        // Release reference (triggers deinit)
        db = nil
        
        // Small delay to allow deinit to complete
        Thread.sleep(forTimeInterval: 0.1)
        
        // Reopen and verify record exists (deinit should have flushed)
        let reopenedDB = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        let allRecords = try reopenedDB.fetchAll()
        XCTAssertEqual(allRecords.count, 1, "Record should persist after deinit")
    }
    
    func testOpenCloseReopen_Works() throws {
        // Open, insert, close
        let db1 = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        let record = BlazeDataRecord(["name": .string("Test")])
        let id = try db1.insert(record)
        try db1.close()
        
        // Reopen and verify
        let db2 = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        let fetched = try db2.fetch(id: id)
        XCTAssertNotNil(fetched, "Record should exist after reopen")
        XCTAssertEqual(fetched?.storage["name"], .string("Test"))
        
        try db2.close()
    }
}
