//
//  FileIntegrityTests.swift
//  BlazeDBTests
//
//  Verifies file-level integrity, checksums, and corruption detection.
//  These tests ensure metadata files don't mysteriously grow or get corrupted.
//

import XCTest
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif
@testable import BlazeDB

final class FileIntegrityTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileInt-\(testID).blazedb")
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        
        do {
            db = try BlazeDBClient(name: "file_test", fileURL: tempURL, password: "FileIntegrityTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Checksum Tests
    
    /// Helper: Calculate SHA256 of file
    private func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Test: Metadata file checksum stable after persist with no changes
    func testMetadataChecksumStable() throws {
        // Insert records
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try db.persist()
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        let hash1 = try sha256(of: metaURL)
        
        // Persist again (no changes)
        try db.persist()
        let hash2 = try sha256(of: metaURL)
        
        XCTAssertEqual(hash1, hash2, 
                      "Metadata checksum should not change when persisting with no changes")
    }
    
    /// Test: Data file checksum stable after persist with no changes
    func testDataFileChecksumStable() throws {
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try db.persist()
        
        let hash1 = try sha256(of: tempURL)
        
        // Persist again (no changes)
        try db.persist()
        let hash2 = try sha256(of: tempURL)
        
        XCTAssertEqual(hash1, hash2, 
                      "Data file checksum should not change when persisting with no changes")
    }
    
    // MARK: - File Size Tests
    
    /// Test: Metadata file size doesn't grow unexpectedly
    func testMetadataFileDoesNotGrowUnexpectedly() throws {
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Insert 10 records
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try db.persist()
        let size1 = try FileManager.default.attributesOfItem(atPath: metaURL.path)[.size] as! Int
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "file_test", fileURL: tempURL, password: "FileIntegrityTest123!")
        
        let size2 = try FileManager.default.attributesOfItem(atPath: metaURL.path)[.size] as! Int
        
        XCTAssertEqual(size1, size2, 
                      "Metadata file grew from \(size1) to \(size2) bytes on reopen!")
        
        // Persist again
        try db.persist()
        let size3 = try FileManager.default.attributesOfItem(atPath: metaURL.path)[.size] as! Int
        
        XCTAssertEqual(size1, size3, 
                      "Metadata file changed size from \(size1) to \(size3) bytes after persist!")
    }
    
    /// Test: Data file size matches expected (pageSize * pageCount)
    func testDataFileSizeConsistent() throws {
        let pageSize = 4096
        let recordCount = 10
        
        for i in 0..<recordCount {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try db.persist()
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as! Int
        let expectedMinSize = pageSize * recordCount
        let expectedMaxSize = pageSize * (recordCount + 1)  // Allow 1 page tolerance
        
        XCTAssertGreaterThanOrEqual(fileSize, expectedMinSize, 
                                    "File should be at least \(expectedMinSize) bytes")
        XCTAssertLessThanOrEqual(fileSize, expectedMaxSize, 
                                 "File should not be larger than \(expectedMaxSize) bytes")
    }
    
    // MARK: - JSON Validity Tests
    
    /// Test: Metadata is always valid JSON
    func testMetadataAlwaysValidJSON() throws {
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Test at various stages
        let stages: [(String, () throws -> Void)] = [
            ("After init", {}),
            ("After 1 insert", { try self.db.insert(BlazeDataRecord(["a": .int(1)])) }),
            ("After persist", { try self.db.persist() }),
            ("After 10 inserts", {
                for i in 2...11 {
                    try self.db.insert(BlazeDataRecord(["a": .int(i)]))
                }
            }),
            ("After reopen", {
                self.db = nil
                BlazeDBClient.clearCachedKey()
                self.db = try BlazeDBClient(name: "file_test", fileURL: self.tempURL, password: "FileIntegrityTest123!")
            })
        ]
        
        for (stageName, action) in stages {
            try action()
            
            guard FileManager.default.fileExists(atPath: metaURL.path) else {
                continue  // No file yet is OK
            }
            
            let data = try Data(contentsOf: metaURL)
            
            // Must be valid JSON
            XCTAssertNoThrow(
                try JSONSerialization.jsonObject(with: data, options: []),
                "\(stageName): Metadata should be valid JSON"
            )
            
            // First byte should NOT be a binary format marker (0x01, 0x02)
            XCTAssertNotEqual(data.first, 0x01, 
                             "\(stageName): Metadata starts with 0x01 (binary format marker!)")
            XCTAssertNotEqual(data.first, 0x02, 
                             "\(stageName): Metadata starts with 0x02 (binary format marker!)")
            
            // Should start with '{' (JSON object)
            XCTAssertEqual(data.first, UInt8(ascii: "{"), 
                          "\(stageName): JSON metadata should start with '{{' character")
        }
    }
    
    /// Test: Metadata file doesn't contain binary garbage
    func testMetadataContainsNoBinaryGarbage() throws {
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        let data = try Data(contentsOf: metaURL)
        
        // Convert to string - should be printable
        if let jsonString = String(data: data, encoding: .utf8) {
            XCTAssertFalse(jsonString.contains("\0"), "JSON should not contain null bytes")
            XCTAssertTrue(jsonString.hasPrefix("{"), "JSON should start with {")
            XCTAssertTrue(jsonString.hasSuffix("}"), "JSON should end with }")
        } else {
            XCTFail("Metadata file should be valid UTF-8")
        }
    }
    
    // MARK: - Atomic Write Tests
    
    /// Test: Atomic write prevents partial updates
    func testAtomicWritePreventsPartialUpdates() throws {
        // This test verifies that .atomic option works correctly
        
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try db.persist()
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Multiple rapid persist calls shouldn't leave temp files
        for _ in 0..<10 {
            try db.persist()
        }
        
        // Check for leftover temp files (atomic write creates .tmp files)
        let dir = metaURL.deletingLastPathComponent()
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let tempFiles = contents.filter { $0.contains(".meta.") && $0.contains("tmp") }
        
        XCTAssertTrue(tempFiles.isEmpty, 
                     "Should not have leftover temp files: \(tempFiles)")
    }
    
    // MARK: - File Descriptor Leak Tests
    
    /// Test: Multiple open/close cycles don't leak file descriptors
    func testNoFileDescriptorLeaks() throws {
        for cycle in 0..<20 {
            // Insert some data
            try db.insert(BlazeDataRecord(["cycle": .int(cycle)]))
            try db.persist()
            
            // Close and reopen
            db = nil
            BlazeDBClient.clearCachedKey()
            db = try BlazeDBClient(name: "file_test", fileURL: tempURL, password: "FileIntegrityTest123!")
        }
        
        // If we get here without "too many open files" error, we're good
        XCTAssertEqual(db.count(), 20, "All 20 records from 20 cycles should exist")
    }
}

