//
//  EncryptionRoundTripTests.swift
//  BlazeDBTests
//
//  Comprehensive encryption tests
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

final class EncryptionRoundTripTests: XCTestCase {
    
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Encryption-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "EncryptionTest", fileURL: dbURL, password: "TestPass123456!")
    }
    
    override func tearDown() {
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    // MARK: - Basic Encryption Tests
    
    func testEncryption_BasicRoundTrip() throws {
        print("🔐 Testing basic encrypt/decrypt round-trip")
        
        // Insert data (should be encrypted)
        let originalData = BlazeDataRecord([
            "message": .string("Secret data"),
            "value": .int(42)
        ])
        
        let id = try db.insert(originalData)
        
        // Fetch data (should be decrypted)
        let retrieved = try db.fetch(id: id)
        
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.storage["message"]?.stringValue, "Secret data")
        XCTAssertEqual(retrieved?.storage["value"]?.intValue, 42)
        
        print("  ✅ Encrypt/decrypt round-trip successful")
    }
    
    func testEncryption_AllDataTypes() throws {
        print("🔐 Testing encryption with all data types")
        
        let testData = BlazeDataRecord([
            "string": .string("Hello 世界"),
            "int": .int(Int.max),
            "double": .double(3.14159265359),
            "bool": .bool(true),
            "date": .date(Date()),
            "uuid": .uuid(UUID()),
            "data": .data(Data([0xFF, 0xAA, 0x55, 0x00])),
            "array": .array([.int(1), .int(2), .int(3)]),
            "dict": .dictionary(["key": .string("value")])
        ])
        
        let id = try db.insert(testData)
        let retrieved = try db.fetch(id: id)
        
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.storage["string"]?.stringValue, "Hello 世界")
        XCTAssertEqual(retrieved?.storage["int"]?.intValue, Int.max)
        XCTAssertEqual(retrieved?.storage["double"]?.doubleValue ?? 0.0, 3.14159265359, accuracy: 0.000001)
        XCTAssertEqual(retrieved?.storage["bool"]?.boolValue, true)
        XCTAssertNotNil(retrieved?.storage["date"]?.dateValue)
        XCTAssertNotNil(retrieved?.storage["uuid"]?.uuidValue)
        XCTAssertNotNil(retrieved?.storage["data"]?.dataValue)
        
        print("  ✅ All data types survived encryption/decryption")
    }
    
    func testEncryption_LargeData() throws {
        print("🔐 Testing encryption with large data")
        
        // Create large string (3000 bytes, close to page limit)
        let largeString = String(repeating: "A", count: 3000)
        
        let id = try db.insert(BlazeDataRecord([
            "large": .string(largeString)
        ]))
        
        let retrieved = try db.fetch(id: id)
        
        XCTAssertEqual(retrieved?.storage["large"]?.stringValue?.count, 3000)
        
        print("  ✅ Large data encrypted/decrypted correctly")
    }
    
    func testEncryption_EmptyData() throws {
        print("🔐 Testing encryption with empty data")
        
        let id = try db.insert(BlazeDataRecord([
            "empty": .string("")
        ]))
        
        let retrieved = try db.fetch(id: id)
        
        XCTAssertEqual(retrieved?.storage["empty"]?.stringValue, "")
        
        print("  ✅ Empty data handled correctly")
    }
    
    // MARK: - Wrong Password Tests
    
    func testEncryption_WrongPassword() throws {
        print("🔐 Testing wrong password fails")
        
        // Create database with password1
        let dbURL1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("pw1-\(UUID().uuidString).blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: dbURL1, password: "Password12345!")
        
        // Insert data
        let id = try db1.insert(BlazeDataRecord([
            "secret": .string("Sensitive data")
        ]))
        
        try db1.persist()
        
        // Clear key cache
        BlazeDBClient.clearCachedKey()
        
        // Try to open with wrong password
        do {
            let db2 = try BlazeDBClient(name: "DB1", fileURL: dbURL1, password: "WrongPassword99!")
            
            // Try to fetch data
            _ = try db2.fetch(id: id)
            
            XCTFail("Should have failed with wrong password")
        } catch {
            // Expected to fail (either at init or decrypt)
            print("  ✅ Wrong password correctly rejected: \(error)")
        }
        
        // Cleanup
        try? FileManager.default.removeItem(at: dbURL1)
    }
    
    // MARK: - Data Integrity Tests
    
    // NOTE: Corruption detection test moved to EncryptionSecurityFullTests.swift (testSecurity_AuthenticationTagPreventsModification)
    // and EncryptionRoundTripVerificationTests.swift (testDetectFileCorruption) for more comprehensive coverage
    
    func testEncryption_MultipleRecords() throws {
        print("🔐 Testing encryption with multiple records")
        
        // Insert 100 records
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
            ids.append(id)
        }
        
        try db.persist()
        
        // Fetch all and verify
        for (i, id) in ids.enumerated() {
            let record = try db.fetch(id: id)
            XCTAssertNotNil(record)
            XCTAssertEqual(record?.storage["index"]?.intValue, i)
            XCTAssertEqual(record?.storage["data"]?.stringValue, "Record \(i)")
        }
        
        print("  ✅ 100 records encrypted/decrypted correctly")
    }
    
    // NOTE: Unique nonces test moved to EncryptionSecurityFullTests.swift (testSecurity_EachPageHasUniqueNonce)
    // to avoid duplication - that version tests with 50 records for better coverage
    
    // MARK: - Performance Tests
    
    func testPerformance_EncryptionOverhead() throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for i in 0..<100 {
                _ = try? self.db.insert(BlazeDataRecord([
                    "value": .int(i),
                    "data": .string("Test data for encryption")
                ]))
            }
        }
    }
}

