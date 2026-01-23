//
//  LockingTests.swift
//  BlazeDBTests
//
//  Tests for single-writer enforcement: file locking prevents double-open
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import XCTest
@testable import BlazeDBCore

final class LockingTests: XCTestCase {
    
    var tempDir: URL!
    var dbURL: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("locking_test.blazedb")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testDoubleOpen_FailsWithLockError() throws {
        // Open first instance
        let db1 = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test-password")
        
        // Attempt to open second instance (should fail)
        XCTAssertThrowsError(try BlazeDBClient(name: "test2", fileURL: dbURL, password: "test-password")) { error in
            XCTAssertTrue(error is BlazeDBError)
            if case .databaseLocked(let operation, _, let path) = error as? BlazeDBError {
                XCTAssertEqual(operation, "open database")
                XCTAssertEqual(path, dbURL)
            } else {
                XCTFail("Expected databaseLocked error, got: \(error)")
            }
        }
        
        // Close first instance
        try db1.close()
        
        // Now second open should succeed
        let db2 = try BlazeDBClient(name: "test2", fileURL: dbURL, password: "test-password")
        try db2.close()
    }
    
    func testLockError_IncludesActionableMessage() throws {
        let db1 = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test-password")
        
        do {
            _ = try BlazeDBClient(name: "test2", fileURL: dbURL, password: "test-password")
            XCTFail("Should have thrown databaseLocked error")
        } catch let error as BlazeDBError {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("locked"), "Error message should mention lock")
            XCTAssertTrue(message.contains("Another process"), "Error message should mention another process")
            XCTAssertTrue(message.contains("resolve"), "Error message should include resolution steps")
        }
        
        try db1.close()
    }
    
    func testLock_ReleasedOnClose() throws {
        // Open and close
        let db1 = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test-password")
        try db1.close()
        
        // Small delay to ensure lock is released
        Thread.sleep(forTimeInterval: 0.1)
        
        // Should be able to open again
        let db2 = try BlazeDBClient(name: "test2", fileURL: dbURL, password: "test-password")
        try db2.close()
    }
}
