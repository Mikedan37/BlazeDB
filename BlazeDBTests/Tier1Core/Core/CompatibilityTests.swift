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
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class CompatibilityTests: XCTestCase {
    
    private var tempDir: URL?
    private var dbURL: URL?
    private var metaURL: URL?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tempDir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("compat_test.blazedb")
        dbURL = url
        metaURL = url.deletingPathExtension().appendingPathExtension("meta")
    }
    
    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
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
        let db = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        try db.close()
        
        // Verify format version is stored in metadata
        let layout = try StorageLayout.load(from: try requireFixture(metaURL))
        if case let .string(version)? = layout.metaData["formatVersion"] {
            XCTAssertEqual(version, "1.0.0", "New database should store current format version")
        } else {
            XCTFail("Format version should be stored in metadata")
        }
    }
    
    func testOpenDatabase_ValidatesFormatVersion() throws {
        // Create database with current version
        let db1 = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        try db1.close()
        
        // Should be able to reopen (same version)
        let db2 = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        try db2.close()
    }
    
    func testIncompatibleVersion_RefusesToOpen() throws {
        // Create database
        let db1 = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        let signingKey = db1.encryptionKey
        let kdfSalt = db1.kdfSalt
        try db1.close()
        
        // Manually modify format version to incompatible version while preserving signature validity
        var layout = try StorageLayout.loadSecure(
            from: try requireFixture(metaURL),
            signingKey: signingKey,
            password: "TestPassword-123!",
            salt: kdfSalt
        )
        layout.metaData["formatVersion"] = .string("2.0.0") // Incompatible major version
        try layout.saveSecure(to: try requireFixture(metaURL), signingKey: signingKey)
        
        // Attempt to open should fail
        XCTAssertThrowsError(try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")) { error in
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
        let db1 = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        let signingKey = db1.encryptionKey
        let kdfSalt = db1.kdfSalt
        try db1.close()
        
        // Remove format version from metadata while preserving signature validity
        var layout = try StorageLayout.loadSecure(
            from: try requireFixture(metaURL),
            signingKey: signingKey,
            password: "TestPassword-123!",
            salt: kdfSalt
        )
        layout.metaData.removeValue(forKey: "formatVersion")
        try layout.saveSecure(to: try requireFixture(metaURL), signingKey: signingKey)
        
        // Should still be able to open (assumes 1.0.0)
        let db2 = try BlazeDBClient(name: "test", fileURL: try requireFixture(dbURL), password: "TestPassword-123!")
        try db2.close()
    }
}
