//
//  EncryptionSecurityTests.swift
//  BlazeDBTests
//
//  Critical security tests for encryption, key management, and password handling.
//  Tests wrong password scenarios, key mismatch detection, and encryption failures.
//
//  Created: Phase 1 Critical Gap Testing
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
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class EncryptionSecurityTests: XCTestCase {
    private var tempURL: URL?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Small delay and clear cache
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncSec-\(testID).blazedb")
        
        // Clean up any leftover files
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: try requireFixture(tempURL))
            try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("backup"))
            
            if !FileManager.default.fileExists(atPath: try requireFixture(tempURL).path) {
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
    
    override func tearDown() {
        if let tempURL = tempURL {
            try? FileManager.default.removeItem(at: try requireFixture(tempURL))
            try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("backup"))
        }
        
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Wrong Password Tests
    
    /// Test encryption key derivation (currently, encryption is not fully implemented)
    /// KNOWN LIMITATION: PageStore currently stores data in plaintext
    /// Encryption keys are derived but not yet applied to page storage
    func testEncryptionKeyDerivation() throws {
        print("🔐 Testing encryption key derivation...")
        
        // Create database with password1
        let id: UUID
        do {
            let db1 = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "CorrectPassword-123!")
            id = try requireFixture(db1).insert(BlazeDataRecord(["secret": .string("sensitive data")]))
            try requireFixture(db1).persist()
        }
        
        print("  Created DB with password 'correct-password-123'")
        
        // IMPORTANT: Clear cached key to force re-derivation with new password
        BlazeDBClient.clearCachedKey()
        print("  Cleared cached encryption key")
        
        print("  Attempting reopen with wrong password...")
        XCTAssertThrowsError(
            try {
                let db2 = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "wrong-password-456")
                _ = try requireFixture(db2).fetch(id: id)
            }(),
            "Wrong password should not successfully read encrypted metadata/data"
        )
        
        // Clear cache again to test correct password
        BlazeDBClient.clearCachedKey()
        
        // Verify correct password still works
        let db3 = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "CorrectPassword-123!")
        let correctFetch = try db3.fetch(id: id)
        print("  Reopened with correct password, secret: '\(correctFetch?.storage["secret"]?.stringValue ?? "nil")'")
        
        XCTAssertEqual(correctFetch?.storage["secret"]?.stringValue, "sensitive data",
                      "Correct password should access data")
        
        print("✅ Key derivation works (encryption pending full implementation)")
    }
    
    /// Test encryption key derivation with different passwords
    /// KNOWN LIMITATION: PageStore currently stores data in plaintext
    /// Encryption keys are derived but not yet applied to page storage
    func testDifferentPasswordsDeriveDifferentKeys() throws {
        print("🔐 Testing different passwords derive different keys...")
        
        // Clear cache to ensure fresh key derivation
        BlazeDBClient.clearCachedKey()
        
        // Create DB with first password
        let sensitiveData = "Confidential Information: Account #12345"
        let id: UUID
        do {
            let db1 = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "FirstPassword-ABC123!")
            id = try requireFixture(db1).insert(BlazeDataRecord([
                "data": .string(sensitiveData),
                "level": .string("confidential")
            ]))
            try requireFixture(db1).persist()
        }
        
        print("  Created DB with password 'first-password-ABC'")
        
        // Clear cache to force new key derivation
        BlazeDBClient.clearCachedKey()
        
        // Try to open with completely different password (different key)
        XCTAssertThrowsError(
            try {
                let db2 = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "SecondPassword-XYZ789!")
                _ = try requireFixture(db2).fetch(id: id)
            }(),
            "Different password should not be able to read data"
        )
        
        // Clear cache again
        BlazeDBClient.clearCachedKey()
        
        // Verify original password still works
        let db3 = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "FirstPassword-ABC123!")
        let fetchedCorrect = try db3.fetch(id: id)
        XCTAssertEqual(fetchedCorrect?.storage["data"]?.stringValue, sensitiveData,
                      "Original password should access data")
        
        print("✅ Different passwords derive different keys (encryption infrastructure ready)")
    }
    
    /// Test that strong passwords work correctly
    func testStrongPasswordAccepted() throws {
        print("🔐 Testing strong password acceptance...")
        
        // These should all work
        let passwords = [
            "Correct-Password-123!",
            "MySecureP@ssw0rd!",
            "!Password123",
            "Str0ng&Secure#Pass"
        ]
        
        for password in passwords {
            XCTAssertNoThrow(try KeyManager.getKey(from: .password(password)),
                           "Strong password '\(password)' should be accepted")
        }
        
        print("✅ Strong passwords accepted correctly")
    }
    
    /// Test encryption key persistence across sessions
    func testEncryptionKeyPersistenceAcrossSessions() throws {
        print("🔐 Testing key persistence across sessions...")
        
        // Session 1: Create and insert data
        do {
            let db = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "SessionTest-123!")
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "session": .int(1),
                "data": .string("Session 1 data")
            ]))
            try requireFixture(db).persist()
            print("  Session 1: Inserted record \(id)")
        }
        
        // Session 2: Read with same password
        do {
            let db = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "SessionTest-123!")
            let records = try requireFixture(db).fetchAll()
            XCTAssertEqual(records.count, 1, "Should decrypt record from session 1")
            XCTAssertEqual(records[0].storage["session"]?.intValue, 1)
            print("  Session 2: Successfully read session 1 data")
        }
        
        // Session 3: Add more data
        do {
            let db = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "SessionTest-123!")
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "session": .int(3),
                "data": .string("Session 3 data")
            ]))
            try requireFixture(db).persist()
            print("  Session 3: Added more data")
        }
        
        // Session 4: Verify both records
        do {
            let db = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "SessionTest-123!")
            let records = try requireFixture(db).fetchAll()
            XCTAssertEqual(records.count, 2, "Should have records from multiple sessions")
            print("  Session 4: Both records present")
        }
        
        print("✅ Encryption key persistence works correctly")
    }
    
    /// Test that encrypted data cannot be read without decryption
    func testEncryptedDataUnreadableWithoutKey() throws {
        print("🔐 Testing encrypted data security...")
        
        // Create DB and insert sensitive data
        let db = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "EncryptionTest-789!")
        let sensitiveData = "Credit Card: 1234-5678-9012-3456"
        let id = try requireFixture(db).insert(BlazeDataRecord([
            "type": .string("payment"),
            "data": .string(sensitiveData)
        ]))
        try requireFixture(db).persist()
        
        print("  Inserted sensitive data")
        
        // Read raw file - should be encrypted (not plaintext)
        let fileData = try Data(contentsOf: try requireFixture(tempURL))
        let fileString = String(data: fileData, encoding: .utf8) ?? ""
        
        XCTAssertFalse(fileString.contains("1234-5678-9012-3456"),
                      "Sensitive data should NOT be plaintext in file")
        XCTAssertFalse(fileString.contains("Credit Card"),
                      "Sensitive strings should NOT be plaintext in file")
        
        print("  ✅ Sensitive data is encrypted on disk")
        
        // Verify we can decrypt with correct password
        let decrypted = try requireFixture(db).fetch(id: id)
        XCTAssertEqual(decrypted?.storage["data"]?.stringValue, sensitiveData,
                      "Should decrypt correctly with right password")
        
        print("✅ Encryption security verified")
    }
    
    /// Test multiple databases with different passwords don't interfere
    /// Test multiple databases with different passwords
    /// KNOWN LIMITATION: PageStore currently stores data in plaintext
    func testMultipleDatabasesWithDifferentPasswords() throws {
        print("🔐 Testing multiple databases with different passwords...")
        
        // Clear cache to ensure fresh key derivation
        BlazeDBClient.clearCachedKey()
        
        let url1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("db1-\(UUID().uuidString).blazedb")
        let url2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("db2-\(UUID().uuidString).blazedb")
        
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url1.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: url2)
            try? FileManager.default.removeItem(at: url2.deletingPathExtension().appendingPathExtension("meta"))
            BlazeDBClient.clearCachedKey()
        }
        
        // Create two databases with different passwords
        let db1 = try BlazeDBClient(name: "DB1", fileURL: url1, password: "SecurePassword-DB1-AAA!")
        
        // Clear cache before creating db2 to force new key
        BlazeDBClient.clearCachedKey()
        
        let db2 = try BlazeDBClient(name: "DB2", fileURL: url2, password: "SecurePassword-DB2-BBB!")
        
        let id1 = try requireFixture(db1).insert(BlazeDataRecord(["db": .string("DB1"), "value": .int(111)]))
        let id2 = try requireFixture(db2).insert(BlazeDataRecord(["db": .string("DB2"), "value": .int(222)]))
        
        try requireFixture(db1).persist()
        try requireFixture(db2).persist()
        
        print("  Created 2 databases with different passwords")
        
        // Verify each database works with its own password
        let record1 = try requireFixture(db1).fetch(id: id1)
        let record2 = try requireFixture(db2).fetch(id: id2)
        
        XCTAssertEqual(record1?.storage["value"]?.intValue, 111, "DB1 should read its own data")
        XCTAssertEqual(record2?.storage["value"]?.intValue, 222, "DB2 should read its own data")
        
        // Clear cache before testing cross-password access
        BlazeDBClient.clearCachedKey()
        
        // Try to read DB1 with DB2's password (different key)
        XCTAssertThrowsError(
            try {
                let db1WrongPass = try BlazeDBClient(name: "DB1", fileURL: url1, password: "SecurePassword-DB2-BBB!")
                _ = try db1WrongPass.fetch(id: id1)
            }(),
            "Cross-password access should fail for protected metadata/data"
        )
        
        print("✅ Multiple databases with different key derivation work (encryption pending)")
    }
    
    /// Test password with special characters and Unicode
    func testPasswordWithSpecialCharacters() throws {
        print("🔐 Testing passwords with special characters...")
        
        let specialPasswords = [
            "P@ssw0rd!#$%",
            "密碼🔐Passw0rd!",
            "🔥🔒🔑DatabaseAa1!",
            "Pass\nWith\tEscapesA1!"
        ]
        
        for (index, password) in specialPasswords.enumerated() {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("special-\(index)-\(UUID().uuidString).blazedb")
            
            defer {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
            }
            
            // Create DB with special password
            let id: UUID
            do {
                let db1 = try BlazeDBClient(name: "Special\(index)", fileURL: url, password: password)
                id = try requireFixture(db1).insert(BlazeDataRecord(["test": .string("works")]))
                try requireFixture(db1).persist()
            }
            
            // Reopen with same special password
            let record: BlazeDataRecord?
            do {
                let db2 = try BlazeDBClient(name: "Special\(index)", fileURL: url, password: password)
                record = try requireFixture(db2).fetch(id: id)
            }
            
            XCTAssertEqual(record?.storage["test"]?.stringValue, "works",
                          "Special password '\(password)' should work")
        }
        
        print("✅ Special character passwords work correctly")
    }
    
    /// Test that changing password invalidates old database access
    /// Test key derivation with different passwords on same database
    /// KNOWN LIMITATION: PageStore currently stores data in plaintext
    func testDifferentPasswordsOnSameDatabase() throws {
        print("🔐 Testing different passwords on same database...")
        
        // Clear cache to ensure fresh key derivation
        BlazeDBClient.clearCachedKey()
        
        // Create DB with initial password
        let id: UUID
        do {
            let db1 = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "InitialPassword-123!")
            id = try requireFixture(db1).insert(BlazeDataRecord(["version": .int(1)]))
            try requireFixture(db1).persist()
        }
        
        print("  Created DB with initial password")
        
        // Clear cache to force new key derivation
        BlazeDBClient.clearCachedKey()
        
        // Open with different password (different key) must fail for protected store.
        XCTAssertThrowsError(
            try {
                let db2 = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "NewPassword-456ABC!")
                _ = try requireFixture(db2).fetch(id: id)
            }(),
            "Different password should not access existing protected store"
        )
        
        // Clear cache again
        BlazeDBClient.clearCachedKey()
        
        // Verify original password still works
        let db3 = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "InitialPassword-123!")
        let originalFetch = try db3.fetch(id: id)
        XCTAssertEqual(originalFetch?.storage["version"]?.intValue, 1,
                      "Original password should access data")
        
        print("✅ Different passwords derive different keys (encryption pending)")
    }
    
    /// Test encryption with very large data (stress test encryption/decryption)
    /// Test with reasonably large data (within 4KB page limit)
    func testKeyDerivationWithLargerRecords() throws {
        print("🔐 Testing key derivation with larger records...")
        
        // Clear cache
        BlazeDBClient.clearCachedKey()
        
        let db = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "LargeDataTest-123!")
        
        // Create ~1.5KB of data (well within 4KB page limit)
        // BlazeDB uses 4KB pages, so max realistic data is ~2-3KB after JSON encoding
        let largeString = String(repeating: "Test data ", count: 150)  // ~1.5KB
        let startTime = Date()
        
        let id = try requireFixture(db).insert(BlazeDataRecord([
            "size": .int(largeString.count),
            "data": .string(largeString),
            "description": .string("Performance test record")
        ]))
        
        let insertDuration = Date().timeIntervalSince(startTime)
        print("  Inserted \(largeString.count) bytes in \(String(format: "%.3f", insertDuration))s")
        
        try requireFixture(db).persist()
        
        // Fetch and verify
        let fetchStart = Date()
        let fetched = try requireFixture(db).fetch(id: id)
        let fetchDuration = Date().timeIntervalSince(fetchStart)
        
        print("  Fetched \(largeString.count) bytes in \(String(format: "%.3f", fetchDuration))s")
        
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, largeString.count,
                      "Should retrieve large data correctly")
        
        // Performance check: should be fast
        XCTAssertLessThan(insertDuration, 0.1, "Insert should be < 100ms")
        XCTAssertLessThan(fetchDuration, 0.1, "Fetch should be < 100ms")
        
        print("✅ Key derivation with larger records works correctly")
    }
    
    /// Test concurrent access with same password (should work)
    func testConcurrentAccessWithSamePassword() throws {
        print("🔐 Testing concurrent access with same password...")
        
        // Create and seed database
        let db = try BlazeDBClient(name: "Test", fileURL: try requireFixture(tempURL), password: "ConcurrentTest-123!")
        
        // Insert 10 seed records
        for i in 0..<10 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["index": .int(i)]))
        }
        try requireFixture(db).persist()
        
        print("  Created DB with 10 records")
        
        // Single-process model: concurrent opens on the same path should fail for new handles.
        let expectation = self.expectation(description: "Concurrent open rejections")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let fileURL = try requireFixture(self.tempURL)
        
        for threadID in 0..<10 {
            queue.async {
                do {
                    // Each thread opens with same password
                    _ = try BlazeDBClient(name: "Test\(threadID)",
                                          fileURL: fileURL,
                                          password: "ConcurrentTest-123!")
                    XCTFail("Thread \(threadID) should not be able to open a second handle")
                    expectation.fulfill()
                } catch {
                    // Expected under single-process lock enforcement.
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        print("✅ Concurrent same-path opens correctly rejected in single-process mode")
    }
}

