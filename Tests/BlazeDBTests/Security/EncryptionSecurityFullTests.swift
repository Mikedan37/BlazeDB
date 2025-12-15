//
//  EncryptionSecurityFullTests.swift
//  BlazeDBTests
//
//  Complete encryption security validation tests
//

import XCTest
@testable import BlazeDB
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif

final class EncryptionSecurityFullTests: XCTestCase {
    
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncSecurity-\(UUID().uuidString).blazedb")
    }
    
    override func tearDown() {
        if let dbURL = dbURL {
            try? FileManager.default.removeItem(at: dbURL)
        }
        super.tearDown()
    }
    
    // MARK: - Security Validation
    
    func testSecurity_DataEncryptedOnDisk() throws {
        print("🔐 Verifying data is actually encrypted on disk")
        
        db = try BlazeDBClient(name: "Security", fileURL: dbURL, password: "TestPass123456!")
        
        // Insert sensitive data
        let sensitiveMessage = "TOPSECRET-PASSWORD-12345"
        let id = try db.insert(BlazeDataRecord([
            "secret": .string(sensitiveMessage)
        ]))
        
        try db.persist()
        
        // Read raw file bytes
        let rawFileData = try Data(contentsOf: dbURL)
        
        // Convert to string to search for plaintext
        let fileString = String(data: rawFileData, encoding: .utf8) ?? ""
        
        // Sensitive data should NOT appear in plaintext
        XCTAssertFalse(fileString.contains(sensitiveMessage),
                      "Sensitive data found in plaintext! Encryption not working!")
        
        // But we should be able to retrieve it through API
        let retrieved = try db.fetch(id: id)
        XCTAssertEqual(retrieved?.storage["secret"]?.stringValue, sensitiveMessage)
        
        print("  ✅ Data encrypted on disk, NOT readable in plaintext")
        
        // Cleanup
        try? FileManager.default.removeItem(at: dbURL)
    }
    
    func testSecurity_DifferentPasswordsDifferentEncryption() throws {
        print("🔐 Testing different passwords produce different ciphertext")
        
        let data = BlazeDataRecord(["message": .string("Same data")])
        
        // Database 1 with password A
        let url1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("db1-\(UUID().uuidString).blazedb")
        let db1 = try BlazeDBClient(name: "DB1", fileURL: url1, password: "PasswordA12345!")
        let id1 = try db1.insert(data)
        try db1.persist()
        
        BlazeDBClient.clearCachedKey()
        
        // Database 2 with password B
        let url2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("db2-\(UUID().uuidString).blazedb")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: url2, password: "PasswordB12345!")
        let id2 = try db2.insert(data)
        try db2.persist()
        
        // Read raw bytes
        let bytes1 = try Data(contentsOf: url1)
        let bytes2 = try Data(contentsOf: url2)
        
        // Ciphertext should be different (different keys)
        XCTAssertNotEqual(bytes1, bytes2, "Same data with different passwords should produce different ciphertext")
        
        print("  ✅ Different passwords = different ciphertext")
        
        // Cleanup
        try? FileManager.default.removeItem(at: url1)
        try? FileManager.default.removeItem(at: url2)
    }
    
    func testSecurity_EachPageHasUniqueNonce() throws {
        print("🔐 Testing unique nonces per page (no nonce reuse)")
        
        db = try BlazeDBClient(name: "NonceTest", fileURL: dbURL, password: "TestPass123456!")
        
        // Insert 50 records
        for i in 0..<50 {
            _ = try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try db.persist()
        
        // Read file and extract nonces
        let fileData = try Data(contentsOf: dbURL)
        let pageSize = 4096
        let pageCount = fileData.count / pageSize
        
        var nonces: Set<Data> = []
        
        for pageIndex in 0..<pageCount {
            let offset = pageIndex * pageSize
            let page = fileData.subdata(in: offset..<(offset + pageSize))
            
            // Skip empty pages
            if page.allSatisfy({ $0 == 0 }) {
                continue
            }
            
            // Check if encrypted (version 0x02)
            if page[4] == 0x02 {
                let nonce = page.subdata(in: 9..<21)
                nonces.insert(nonce)
            }
        }
        
        // All nonces should be unique (no reuse!)
        XCTAssertEqual(nonces.count, min(50, pageCount), "Each encrypted page must have unique nonce")
        
        print("  ✅ All \(nonces.count) pages have unique nonces (secure)")
    }
    
    func testSecurity_AuthenticationTagPreventsModification() throws {
        print("🔐 Testing authentication tag prevents tampering")
        
        db = try BlazeDBClient(name: "AuthTest", fileURL: dbURL, password: "TestPass123456!")
        
        // Insert data
        let id = try db.insert(BlazeDataRecord([
            "sensitive": .string("Original data")
        ]))
        
        try db.persist()
        
        // Tamper with encrypted file
        let fileHandle = try FileHandle(forUpdating: dbURL)
        try fileHandle.seek(toOffset: 100)  // Modify ciphertext
        try fileHandle.write(contentsOf: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        try fileHandle.close()
        
        // Reload database
        BlazeDBClient.clearCachedKey()
        let db2 = try BlazeDBClient(name: "EncryptionTest", fileURL: dbURL, password: "TestPass123456!")
        
        // Try to fetch - should fail authentication
        do {
            _ = try db2.fetch(id: id)
            XCTFail("Should detect tampered data")
        } catch {
            print("  ✅ Tampering detected: \(error)")
        }
    }
    
    func testSecurity_MetadataAlsoProtected() throws {
        print("🔐 Testing metadata encryption")
        
        db = try BlazeDBClient(name: "MetaTest", fileURL: dbURL, password: "TestPass123456!")
        
        // Insert data with metadata
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Test")
        ]))
        
        try db.persist()
        
        let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")
        
        if FileManager.default.fileExists(atPath: metaURL.path) {
            let metaData = try Data(contentsOf: metaURL)
            let metaString = String(data: metaData, encoding: .utf8) ?? ""
            
            // Metadata should be encrypted or at least not contain sensitive UUIDs in plaintext
            // (This is a basic check - more thorough audit needed)
            print("  ⚠️  Metadata file exists (check encryption)")
        }
    }
    
    // MARK: - Edge Cases
    
    func testEncryption_UpdatePreservesEncryption() throws {
        print("🔐 Testing updates maintain encryption")
        
        db = try BlazeDBClient(name: "UpdateTest", fileURL: dbURL, password: "TestPass123456!")
        
        let id = try db.insert(BlazeDataRecord([
            "value": .int(1)
        ]))
        
        // Update record
        try db.update(id: id, with: BlazeDataRecord([
            "value": .int(2)
        ]))
        
        try db.persist()
        
        // Verify still encrypted on disk
        let rawData = try Data(contentsOf: dbURL)
        let rawString = String(data: rawData, encoding: .utf8) ?? ""
        
        XCTAssertFalse(rawString.contains("value"), "Updated data should still be encrypted")
        
        // But retrievable
        let retrieved = try db.fetch(id: id)
        XCTAssertEqual(retrieved?.storage["value"]?.intValue, 2)
        
        print("  ✅ Updates maintain encryption")
    }
    
    func testEncryption_CrashRecoveryWithEncryption() throws {
        print("🔐 Testing crash recovery with encrypted data")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "CrashTest", fileURL: dbURL, password: "TestPass123456!")
        
        guard let dbInitial = db else {
            XCTFail("Database not initialized")
            return
        }
        
        // Insert data
        let id1 = try dbInitial.insert(BlazeDataRecord(["value": .int(1)]))
        let id2 = try dbInitial.insert(BlazeDataRecord(["value": .int(2)]))
        
        try dbInitial.persist()
        
        // Simulate crash
        db = nil
        
        // Recovery
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "CrashTest", fileURL: dbURL, password: "TestPass123456!")
        
        guard let dbRestored = db else {
            XCTFail("Database not initialized after recovery")
            return
        }
        
        // Data should be recoverable
        let r1 = try dbRestored.fetch(id: id1)
        let r2 = try dbRestored.fetch(id: id2)
        
        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)
        XCTAssertEqual(r1?.storage["value"]?.intValue, 1)
        XCTAssertEqual(r2?.storage["value"]?.intValue, 2)
        
        print("  ✅ Crash recovery works with encryption")
    }
    
    func testPerformance_EncryptionThroughput() throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let testURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("perf-\(UUID().uuidString).blazedb")
            guard let testDB = try? BlazeDBClient(name: "Perf", fileURL: testURL, password: "EncryptionSecurity123!") else {
                XCTFail("Failed to initialize BlazeDBClient")
                return
            }
            
            // Insert 200 encrypted records
            for i in 0..<200 {
                _ = try! testDB.insert(BlazeDataRecord([
                    "index": .int(i),
                    "data": .string("Test data \(i)")
                ]))
            }
            
            try? FileManager.default.removeItem(at: testURL)
        }
    }
}

