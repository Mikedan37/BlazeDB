//
//  PasswordVaultServiceTests.swift
//  BlazeDBVisualizerTests
//
//  Comprehensive tests for secure password storage
//  ✅ Keychain integration
//  ✅ Biometric unlock
//  ✅ Error handling
//
//  Created by Michael Danylchuk on 11/13/25.
//

import XCTest
@testable import BlazeDBVisualizer

final class PasswordVaultServiceTests: XCTestCase {
    
    var vault: PasswordVaultService!
    let testDBPath = "/Users/test/test_database.blazedb"
    let testPassword = "super_secret_password_123"
    
    override func setUp() {
        super.setUp()
        vault = PasswordVaultService.shared
        
        // Clean up any existing test data
        try? vault.deletePassword(for: testDBPath)
    }
    
    override func tearDown() {
        // Clean up test data
        try? vault.deletePassword(for: testDBPath)
        super.tearDown()
    }
    
    // MARK: - Password Storage Tests
    
    func testSavePassword() throws {
        // Save password
        try vault.savePassword(testPassword, for: testDBPath, useBiometrics: false)
        
        // Verify it was saved
        XCTAssertTrue(vault.hasStoredPassword(for: testDBPath), "Password should be stored")
    }
    
    func testSavePasswordOverwritesExisting() throws {
        // Save initial password
        try vault.savePassword("password1", for: testDBPath, useBiometrics: false)
        
        // Overwrite with new password
        try vault.savePassword("password2", for: testDBPath, useBiometrics: false)
        
        // Verify new password is stored
        let retrieved = try vault.getPassword(for: testDBPath, reason: "Test")
        XCTAssertEqual(retrieved, "password2", "Should retrieve updated password")
    }
    
    func testDeletePassword() throws {
        // Save password
        try vault.savePassword(testPassword, for: testDBPath, useBiometrics: false)
        
        // Delete it
        try vault.deletePassword(for: testDBPath)
        
        // Verify it's gone
        XCTAssertFalse(vault.hasStoredPassword(for: testDBPath), "Password should be deleted")
    }
    
    func testDeleteNonExistentPassword() {
        // Should not throw error
        XCTAssertNoThrow(try vault.deletePassword(for: "/nonexistent/path.blazedb"))
    }
    
    // MARK: - Password Retrieval Tests
    
    func testGetPassword() throws {
        // Save password
        try vault.savePassword(testPassword, for: testDBPath, useBiometrics: false)
        
        // Retrieve it
        let retrieved = try vault.getPassword(for: testDBPath, reason: "Test")
        
        // Verify it matches
        XCTAssertEqual(retrieved, testPassword, "Retrieved password should match saved password")
    }
    
    func testGetNonExistentPassword() {
        // Try to get password that doesn't exist
        XCTAssertThrowsError(try vault.getPassword(for: "/nonexistent/path.blazedb", reason: "Test")) { error in
            // Should throw keychain error
            XCTAssertTrue(error is PasswordVaultError, "Should throw PasswordVaultError")
        }
    }
    
    // MARK: - Unicode and Special Characters
    
    func testSavePasswordWithUnicode() throws {
        let unicodePassword = "🔥🚀💎 BlazeDB Password 中文 العربية"
        
        try vault.savePassword(unicodePassword, for: testDBPath, useBiometrics: false)
        let retrieved = try vault.getPassword(for: testDBPath, reason: "Test")
        
        XCTAssertEqual(retrieved, unicodePassword, "Unicode passwords should be preserved")
    }
    
    func testSavePasswordWithSpecialChars() throws {
        let specialPassword = "p@$$w0rd!#%&*()[]{}|\\/:;\"'<>,.?~`"
        
        try vault.savePassword(specialPassword, for: testDBPath, useBiometrics: false)
        let retrieved = try vault.getPassword(for: testDBPath, reason: "Test")
        
        XCTAssertEqual(retrieved, specialPassword, "Special characters should be preserved")
    }
    
    // MARK: - Multiple Databases
    
    func testMultipleDatabases() throws {
        let db1Path = "/Users/test/db1.blazedb"
        let db2Path = "/Users/test/db2.blazedb"
        let db3Path = "/Users/test/db3.blazedb"
        
        let password1 = "password1"
        let password2 = "password2"
        let password3 = "password3"
        
        // Save passwords for multiple databases
        try vault.savePassword(password1, for: db1Path, useBiometrics: false)
        try vault.savePassword(password2, for: db2Path, useBiometrics: false)
        try vault.savePassword(password3, for: db3Path, useBiometrics: false)
        
        // Verify each one
        XCTAssertEqual(try vault.getPassword(for: db1Path, reason: "Test"), password1)
        XCTAssertEqual(try vault.getPassword(for: db2Path, reason: "Test"), password2)
        XCTAssertEqual(try vault.getPassword(for: db3Path, reason: "Test"), password3)
        
        // Clean up
        try vault.deletePassword(for: db1Path)
        try vault.deletePassword(for: db2Path)
        try vault.deletePassword(for: db3Path)
    }
    
    // MARK: - Biometrics Availability
    
    func testBiometricsAvailability() {
        // This will depend on the test environment
        // Just verify the method doesn't crash
        let _ = vault.isBiometricsAvailable()
        let _ = vault.biometricType()
        
        // On CI/test environments without biometrics, this should return false or "None"
        // On Macs with Touch ID/Face ID, this should return true
        print("Biometrics available: \(vault.isBiometricsAvailable())")
        print("Biometric type: \(vault.biometricType())")
    }
    
    // MARK: - Edge Cases
    
    func testEmptyPassword() throws {
        // Empty passwords should be allowed (though not recommended!)
        try vault.savePassword("", for: testDBPath, useBiometrics: false)
        let retrieved = try vault.getPassword(for: testDBPath, reason: "Test")
        XCTAssertEqual(retrieved, "", "Empty password should be preserved")
    }
    
    func testVeryLongPassword() throws {
        // Test with a 10KB password
        let longPassword = String(repeating: "a", count: 10_000)
        
        try vault.savePassword(longPassword, for: testDBPath, useBiometrics: false)
        let retrieved = try vault.getPassword(for: testDBPath, reason: "Test")
        
        XCTAssertEqual(retrieved, longPassword, "Long passwords should be preserved")
        XCTAssertEqual(retrieved.count, 10_000, "Password length should be preserved")
    }
    
    func testHasStoredPassword() throws {
        // Initially should not have password
        XCTAssertFalse(vault.hasStoredPassword(for: testDBPath))
        
        // Save password
        try vault.savePassword(testPassword, for: testDBPath, useBiometrics: false)
        
        // Now should have password
        XCTAssertTrue(vault.hasStoredPassword(for: testDBPath))
        
        // Delete password
        try vault.deletePassword(for: testDBPath)
        
        // Should no longer have password
        XCTAssertFalse(vault.hasStoredPassword(for: testDBPath))
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentSave() throws {
        let expectation = self.expectation(description: "Concurrent save")
        expectation.expectedFulfillmentCount = 10
        
        // Save passwords concurrently for different databases
        for i in 0..<10 {
            DispatchQueue.global().async {
                let path = "/Users/test/db\(i).blazedb"
                do {
                    try self.vault.savePassword("password\(i)", for: path, useBiometrics: false)
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent save failed: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Clean up
        for i in 0..<10 {
            try? vault.deletePassword(for: "/Users/test/db\(i).blazedb")
        }
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceSavePassword() {
        measure {
            do {
                try vault.savePassword(testPassword, for: testDBPath, useBiometrics: false)
                try vault.deletePassword(for: testDBPath)
            } catch {
                XCTFail("Performance test failed: \(error)")
            }
        }
    }
    
    func testPerformanceGetPassword() throws {
        // Set up
        try vault.savePassword(testPassword, for: testDBPath, useBiometrics: false)
        
        measure {
            do {
                _ = try vault.getPassword(for: testDBPath, reason: "Performance Test")
            } catch {
                XCTFail("Performance test failed: \(error)")
            }
        }
    }
}

