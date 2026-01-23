//
//  CompatibilityTests.swift
//  BlazeDBTests
//
//  Tests for on-disk compatibility contract: format versioning and validation
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import XCTest
@testable import BlazeDBCore

final class CompatibilityTests: XCTestCase {
    
    var tempDir: URL!
    var dbURL: URL!
    var metaURL: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("compat_test.blazedb")
        metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testFormatVersion_CurrentVersion() {
        let version = BlazeDBClient.FormatVersion.current
        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(version.minor, 0)
        XCTAssertEqual(version.patch, 0)
        XCTAssertEqual(version.description, "1.0.0")
    }
    
    func testFormatVersion_Compatibility_SameMajor() {
        let v1_0_0 = BlazeDBClient.FormatVersion(major: 1, minor: 0, patch: 0)
        let v1_1_0 = BlazeDBClient.FormatVersion(major: 1, minor: 1, patch: 0)
        let v1_0_5 = BlazeDBClient.FormatVersion(major: 1, minor: 0, patch: 5)
        
        XCTAssertTrue(v1_0_0.isCompatible(with: v1_1_0), "Same major version should be compatible")
        XCTAssertTrue(v1_0_0.isCompatible(with: v1_0_5), "Same major version should be compatible")
        XCTAssertTrue(v1_1_0.isCompatible(with: v1_0_0), "Compatibility should be symmetric")
    }
    
    func testFormatVersion_Compatibility_DifferentMajor() {
        let v1_0_0 = BlazeDBClient.FormatVersion(major: 1, minor: 0, patch: 0)
        let v2_0_0 = BlazeDBClient.FormatVersion(major: 2, minor: 0, patch: 0)
        
        XCTAssertFalse(v1_0_0.isCompatible(with: v2_0_0), "Different major versions should be incompatible")
        XCTAssertFalse(v2_0_0.isCompatible(with: v1_0_0), "Compatibility should be symmetric")
    }
    
    func testNewDatabase_StoresFormatVersion() throws {
        // Create new database
        let db = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test-password")
        try db.close()
        
        // Verify format version is stored in metadata
        let layout = try StorageLayout.load(from: metaURL)
        if case let .string(version)? = layout.metaData["formatVersion"] {
            XCTAssertEqual(version, "1.0.0", "New database should store current format version")
        } else {
            XCTFail("Format version should be stored in metadata")
        }
    }
    
    func testOpenDatabase_ValidatesFormatVersion() throws {
        // Create database with current version
        let db1 = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test-password")
        try db1.close()
        
        // Should be able to reopen (same version)
        let db2 = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test-password")
        try db2.close()
    }
    
    func testIncompatibleVersion_RefusesToOpen() throws {
        // Create database
        let db1 = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test-password")
        try db1.close()
        
        // Manually modify format version to incompatible version
        var layout = try StorageLayout.load(from: metaURL)
        layout.metaData["formatVersion"] = .string("2.0.0") // Incompatible major version
        try layout.save(to: metaURL)
        
        // Attempt to open should fail
        XCTAssertThrowsError(try BlazeDBClient(name: "test", fileURL: dbURL, password: "test-password")) { error in
            XCTAssertTrue(error is BlazeDBError)
            if case .invalidData(let reason) = error as? BlazeDBError {
                XCTAssertTrue(reason.contains("incompatible"), "Error should mention incompatibility")
                XCTAssertTrue(reason.contains("2.0.0"), "Error should mention incompatible version")
                XCTAssertTrue(reason.contains("resolve"), "Error should include resolution steps")
            } else {
                XCTFail("Expected invalidData error for incompatible version")
            }
        }
    }
    
    func testLegacyDatabase_AssumesCompatibleVersion() throws {
        // Create database without format version (legacy)
        let db1 = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test-password")
        try db1.close()
        
        // Remove format version from metadata
        var layout = try StorageLayout.load(from: metaURL)
        layout.metaData.removeValue(forKey: "formatVersion")
        try layout.save(to: metaURL)
        
        // Should still be able to open (assumes 1.0.0)
        let db2 = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test-password")
        try db2.close()
    }
}
