//
//  BlazeDBInitializationTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for BlazeDB initialization patterns.
//  Tests both throwing and failable initializers with various scenarios.
//

import XCTest
@testable import BlazeDBCore

final class BlazeDBInitializationTests: XCTestCase {
    
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        
        // Small delay to ensure previous test's tearDown completed
        Thread.sleep(forTimeInterval: 0.01)
        
        // Create unique database file per test run
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Init-\(testID).blazedb")
        
        // Ensure no leftover files from previous runs (try multiple times)
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
            
            // Check if files are actually gone
            if !FileManager.default.fileExists(atPath: tempURL.path) {
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        // Clear cached encryption key to ensure each test validates the password
        BlazeDBClient.clearCachedKey()
    }
    
    override func tearDown() {
        // Manual cleanup since this test file doesn't have a persistent db property
        if let tempURL = tempURL {
            // Small delay to ensure file handles are released
            Thread.sleep(forTimeInterval: 0.05)
            
            // Remove all associated files
            let extensions = ["", "meta", "indexes", "wal", "backup", "transaction_backup"]
            for ext in extensions {
                let url = ext.isEmpty ? tempURL : tempURL.deletingPathExtension().appendingPathExtension(ext)
                try? FileManager.default.removeItem(at: url)
            }
            
            Thread.sleep(forTimeInterval: 0.02)
        }
        BlazeDBClient.clearCachedKey()
        BlazeLogger.reset()
        super.tearDown()
    }
    
    // MARK: - Throwing Initializer Tests
    
    /// Test successful initialization with throwing initializer
    func testThrowingInit_Success() throws {
        print("🔷 Testing throwing initializer with valid password...")
        
        var db: BlazeDBClient? = try BlazeDBClient(
            name: "TestDB",
            fileURL: tempURL,
            password: "secure-password-123"
        )
        
        XCTAssertNotNil(db)
        XCTAssertEqual(db?.name, "TestDB")
        
        // Verify it works
        let id = try db?.insert(BlazeDataRecord(["test": .string("value")]))
        XCTAssertNotNil(id)
        
        // Clean up explicitly
        try? db?.persist()
        db = nil
        
        print("✅ Throwing initializer works with valid password")
    }
    
    /// Test throwing initializer rejects weak password
    func testThrowingInit_WeakPassword() throws {
        print("🔷 Testing throwing initializer with weak password...")
        
        XCTAssertThrowsError(try BlazeDBClient(
            name: "TestDB",
            fileURL: tempURL,
            password: "weak"  // Only 4 characters
        )) { error in
            XCTAssertTrue(error is BlazeDBError, "Should throw BlazeDBError")
            if case BlazeDBError.transactionFailed(let msg, _) = error {
                XCTAssertTrue(msg.contains("8 characters"), "Should mention 8 character requirement")
                XCTAssertTrue(msg.contains("weak") || msg.contains("4"), "Should mention actual length")
            }
        }
        
        print("✅ Throwing initializer rejects weak password correctly")
    }
    
    /// Test throwing initializer with invalid file path
    func testThrowingInit_InvalidPath() throws {
        print("🔷 Testing throwing initializer with invalid path...")
        
        let invalidURL = URL(fileURLWithPath: "/invalid/nonexistent/path/db.blazedb")
        
        XCTAssertThrowsError(try BlazeDBClient(
            name: "TestDB",
            fileURL: invalidURL,
            password: "secure-password-123"
        )) { error in
            // Should throw some error (storage initialization failure)
            XCTAssertTrue(error is BlazeDBError || error is CocoaError)
        }
        
        print("✅ Throwing initializer handles invalid paths")
    }
    
    // MARK: - Failable Initializer Tests
    
    /// Test failable initializer with valid password
    func testFailableInit_Success() throws {
        print("🔷 Testing failable initializer with valid password...")
        
        var db: BlazeDBClient? = BlazeDBClient(name: "TestDB", at: tempURL, password: "secure-password-123")
        
        guard let dbUnwrapped = db else {
            XCTFail("Should successfully initialize with strong password")
            return
        }
        
        XCTAssertNotNil(db)
        XCTAssertEqual(dbUnwrapped.name, "TestDB")
        
        // Verify it works
        let id = try dbUnwrapped.insert(BlazeDataRecord(["test": .string("value")]))
        XCTAssertNotNil(id)
        
        // Clean up explicitly
        try? db?.persist()
        db = nil
        
        print("✅ Failable initializer succeeds with valid password")
    }
    
    /// Test failable initializer returns nil for weak password
    func testFailableInit_WeakPassword() throws {
        print("🔷 Testing failable initializer with weak password...")
        
        // Should return nil (not crash)
        let db = BlazeDBClient(name: "TestDB", at: tempURL, password: "weak")
        
        XCTAssertNil(db, "Should return nil for weak password")
        
        print("✅ Failable initializer returns nil for weak password")
    }
    
    /// Test failable initializer returns nil for invalid path
    func testFailableInit_InvalidPath() throws {
        print("🔷 Testing failable initializer with invalid path...")
        
        let invalidURL = URL(fileURLWithPath: "/invalid/nonexistent/path/db.blazedb")
        
        // Should return nil (not crash)
        let db = BlazeDBClient(name: "TestDB", at: invalidURL, password: "secure-password-123")
        
        XCTAssertNil(db, "Should return nil for invalid path")
        
        print("✅ Failable initializer returns nil for invalid path")
    }
    
    /// Test failable initializer with various weak passwords
    func testFailableInit_VariousWeakPasswords() throws {
        print("🔷 Testing failable initializer with various weak passwords...")
        
        let weakPasswords = ["", "a", "ab", "abc", "1234", "test", "pass"]
        
        for password in weakPasswords {
            let db = BlazeDBClient(name: "TestDB", at: tempURL, password: password)
            XCTAssertNil(db, "Should return nil for password: '\(password)' (length: \(password.count))")
        }
        
        print("✅ Failable initializer rejects all weak passwords")
    }
    
    /// Test failable initializer with minimum valid password
    func testFailableInit_MinimumValidPassword() throws {
        print("🔷 Testing failable initializer with 8-character password...")
        
        var db: BlazeDBClient? = BlazeDBClient(name: "TestDB", at: tempURL, password: "12345678")
        
        guard let dbUnwrapped = db else {
            XCTFail("Should accept 8-character password")
            return
        }
        
        XCTAssertNotNil(db)
        
        // Verify it works
        let id = try dbUnwrapped.insert(BlazeDataRecord(["test": .string("value")]))
        XCTAssertNotNil(id)
        
        // Clean up explicitly
        try? db?.persist()
        db = nil
        
        print("✅ Failable initializer accepts 8-character password")
    }
    
    // MARK: - Error Message Quality Tests
    
    /// Test that error messages are helpful
    func testErrorMessages_AreHelpful() throws {
        print("🔷 Testing error message quality...")
        
        // Capture error message
        var errorMessage = ""
        
        do {
            _ = try BlazeDBClient(name: "TestDB", fileURL: tempURL, password: "bad")
            XCTFail("Should have thrown error")
        } catch {
            errorMessage = "\(error)"
        }
        
        // Verify message contains helpful information
        XCTAssertTrue(errorMessage.contains("8") || errorMessage.contains("character"), 
                     "Should mention character requirement")
        XCTAssertTrue(errorMessage.contains("Password") || errorMessage.contains("weak"),
                     "Should mention password issue")
        
        print("  Error message: \(errorMessage)")
        print("✅ Error messages are clear and helpful")
    }
    
    /// Test that failable initializer logs errors
    func testFailableInit_LogsErrors() throws {
        print("🔷 Testing that failable initializer logs errors...")
        
        var loggedMessages: [String] = []
        
        // CRITICAL: Enable error-level logging (tests default to .silent)
        BlazeLogger.level = .error
        
        // Capture log output
        BlazeLogger.handler = { message, level in
            if level == .error {
                loggedMessages.append(message)
                print("  [CAPTURED] \(message)")
            }
        }
        
        // Try to initialize with weak password
        let db = BlazeDBClient(name: "TestDB", at: tempURL, password: "weak")
        
        XCTAssertNil(db, "Should return nil with weak password")
        XCTAssertFalse(loggedMessages.isEmpty, "Should have logged error")
        
        let errorLog = loggedMessages.joined(separator: " ")
        XCTAssertTrue(errorLog.contains("Failed to initialize"), "Should log initialization failure")
        
        // Reset logger
        BlazeLogger.reset()
        
        print("  Logged \(loggedMessages.count) error(s)")
        print("  First error: \(loggedMessages.first ?? "none")")
        print("✅ Failable initializer logs errors correctly")
    }
    
    // MARK: - Convenience Initializer Tests
    
    /// Test throwing convenience initializer (without project param)
    func testConvenienceInit_Throwing() throws {
        print("🔷 Testing throwing convenience initializer...")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "TestDB", fileURL: tempURL, password: "secure-password-123")
        
        XCTAssertNotNil(db)
        XCTAssertEqual(db?.name, "TestDB")
        
        // Clean up explicitly
        try? db?.persist()
        db = nil
        
        print("✅ Throwing convenience initializer works")
    }
    
    /// Test failable convenience initializer
    func testConvenienceInit_Failable() throws {
        print("🔷 Testing failable convenience initializer...")
        
        var db: BlazeDBClient? = BlazeDBClient(name: "TestDB", at: tempURL, password: "secure-password-123")
        
        guard db != nil else {
            XCTFail("Should successfully initialize")
            return
        }
        
        XCTAssertNotNil(db)
        
        // Clean up explicitly
        try? db?.persist()
        db = nil
        
        print("✅ Failable convenience initializer works")
    }
    
    // MARK: - Real-World Usage Tests
    
    /// Test typical production usage pattern (guard let)
    func testRealWorld_GuardLetPattern() throws {
        print("🔷 Testing real-world guard-let pattern...")
        
        var db: BlazeDBClient?
        
        func initializeDatabase() -> BlazeDBClient? {
            guard let dbInstance = BlazeDBClient(
                name: "ProductionDB",
                at: tempURL,
                password: "production-secure-password"
            ) else {
                return nil
            }
            return dbInstance
        }
        
        guard let dbInstance = initializeDatabase() else {
            XCTFail("Should initialize successfully")
            return
        }
        
        db = dbInstance
        
        // Verify database is usable
        let id = try db?.insert(BlazeDataRecord(["status": .string("active")]))
        XCTAssertNotNil(id)
        
        // Clean up explicitly
        try? db?.persist()
        db = nil
        
        print("✅ Real-world guard-let pattern works perfectly")
    }
    
    /// Test typical production usage pattern (do-catch)
    func testRealWorld_DoCatchPattern() throws {
        print("🔷 Testing real-world do-catch pattern...")
        
        var db: BlazeDBClient?
        
        func initializeDatabase() throws -> BlazeDBClient {
            return try BlazeDBClient(
                name: "ProductionDB",
                fileURL: tempURL,
                password: "production-secure-password"
            )
        }
        
        do {
            db = try initializeDatabase()
            
            // Verify database is usable
            let id = try db?.insert(BlazeDataRecord(["status": .string("active")]))
            XCTAssertNotNil(id)
            
            // Clean up explicitly
            try? db?.persist()
            db = nil
            
            print("✅ Real-world do-catch pattern works perfectly")
        } catch {
            XCTFail("Should not throw: \(error)")
        }
    }
    
    /// Test error recovery pattern
    func testRealWorld_ErrorRecovery() throws {
        print("🔷 Testing real-world error recovery pattern...")
        
        var db: BlazeDBClient?
        
        // Try with weak password first (simulating user input)
        db = BlazeDBClient(name: "TestDB", at: tempURL, password: "weak")
        XCTAssertNil(db, "First attempt should fail")
        
        // Retry with strong password (simulating retry logic)
        db = BlazeDBClient(name: "TestDB", at: tempURL, password: "strong-password-123")
        XCTAssertNotNil(db, "Second attempt should succeed")
        
        // Verify database works
        if let validDB = db {
            let id = try validDB.insert(BlazeDataRecord(["test": .string("value")]))
            XCTAssertNotNil(id)
        }
        
        // Clean up explicitly
        try? db?.persist()
        db = nil
        
        print("✅ Error recovery pattern works")
    }
}

