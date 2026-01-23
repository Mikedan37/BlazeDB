//
//  CrossAppSyncTests.swift
//  BlazeDBTests
//
//  Tests for cross-app synchronization
//

import XCTest
@testable import BlazeDBCore

final class CrossAppSyncTests: XCTestCase {
    var tempDir: URL!
    
    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrossAppSyncTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testExportPolicy() {
        let policy = ExportPolicy(
            collections: ["bugs", "comments"],
            fields: ["id", "title", "status"],
            readOnly: true
        )
        
        XCTAssertEqual(policy.collections.count, 2)
        XCTAssertEqual(policy.fields?.count, 3)
        XCTAssertTrue(policy.readOnly)
    }
    
    func testExportPolicyAllFields() {
        let policy = ExportPolicy(
            collections: ["bugs"],
            fields: nil,  // All fields
            readOnly: true
        )
        
        XCTAssertNil(policy.fields)  // nil means all fields
    }
    
    func testExportPolicyNoFields() {
        let policy = ExportPolicy(
            collections: ["bugs"],
            fields: [],  // No fields
            readOnly: true
        )
        
        XCTAssertEqual(policy.fields?.count, 0)
    }
    
    // Note: Full cross-app sync tests require App Groups setup
    // These are unit tests for the policy structure
}

