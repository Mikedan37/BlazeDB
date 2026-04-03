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
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class LockingTests: XCTestCase {
    
    private var tempDir: URL?
    private var dbURL: URL?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tempDir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("locking_test.blazedb")
    }
    
    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }
    
    func testDoubleOpen_FailsWithLockError() throws {
        let fileURL = try requireFixture(dbURL)
        // Open first instance
        let db1 = try BlazeDBClient(name: "test", fileURL: fileURL, password: "TestPassword-123!")
        
        // Attempt to open second instance (should fail)
        XCTAssertThrowsError(try BlazeDBClient(name: "test2", fileURL: fileURL, password: "TestPassword-123!")) { error in
            XCTAssertTrue(error is BlazeDBError)
            if case .concurrentProcessAccessNotSupported(let operation, let path) = error as? BlazeDBError {
                XCTAssertEqual(operation, "open database")
                XCTAssertEqual(path, fileURL)
            } else {
                XCTFail("Expected concurrentProcessAccessNotSupported error, got: \(error)")
            }
        }
        
        // Close first instance
        try db1.close()
        
        // Now second open should succeed
        let db2 = try BlazeDBClient(name: "test2", fileURL: fileURL, password: "TestPassword-123!")
        try db2.close()
    }
    
    func testLockError_IncludesActionableMessage() throws {
        let db1 = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        
        do {
            _ = try BlazeDBClient(name: "test2", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
            XCTFail("Should have thrown concurrentProcessAccessNotSupported error")
        } catch let error as BlazeDBError {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("Concurrent") || message.contains("single-process"), "Error message should mention single-process / concurrent")
            XCTAssertTrue(message.contains("process") || message.contains("handle"), "Error message should mention process or handle")
        }
        
        try db1.close()
    }
    
    func testLock_ReleasedOnClose() throws {
        // Open and close
        let db1 = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        try db1.close()
        
        // Small delay to ensure lock is released
        Thread.sleep(forTimeInterval: 0.1)
        
        // Should be able to open again
        let db2 = try BlazeDBClient(name: "test2", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        try db2.close()
    }
}
