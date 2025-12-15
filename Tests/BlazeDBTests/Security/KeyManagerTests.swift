//  KeyManagerTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
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

final class KeyManagerTests: XCTestCase {
    
    let testText = "🔥 Blaze it. Don't lose it.".data(using: .utf8)!
    var tempFile: URL!
    var store: BlazeDB.PageStore!

    override func setUpWithError() throws {
        tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blz")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempFile)
    }


    func testPasswordKeyEncryptDecrypt() throws {
        let key = try KeyManager.getKey(from: .password("MySecurePassword123!🔥"))
        let store = try BlazeDB.PageStore(fileURL: tempFile, key: key)

        try store.writePage(index: 1, plaintext: testText)
        let readBack = try store.readPage(index: 1)

        XCTAssertEqual(readBack, testText, "Password-derived key should decrypt properly")
    }

    func testWeakPasswordFails() throws {
        XCTAssertThrowsError(try KeyManager.getKey(from: .password("123"))) { error in
            guard case KeyManagerError.passwordTooWeak = error else {
                XCTFail("Expected passwordTooWeak error, got \(error)")
                return
            }
        }
    }
    
    func testCustomSaltKeyDerivation() throws {
        let password = "TestPassword123!"
        let salt1 = "CustomSalt1".data(using: .utf8)!
        let salt2 = "CustomSalt2".data(using: .utf8)!
        
        let key1 = try KeyManager.getKey(from: password, salt: salt1)
        let key2 = try KeyManager.getKey(from: password, salt: salt2)
        
        let key1Data = key1.withUnsafeBytes { Data($0) }
        let key2Data = key2.withUnsafeBytes { Data($0) }
        
        XCTAssertNotEqual(key1Data, key2Data, "Different salts should produce different keys")
    }
    
    func testKeyCacheWorks() throws {
        let password = "CachedPassword123!"
        let salt = "TestSalt".data(using: .utf8)!
        
        let startTime1 = Date()
        let key1 = try KeyManager.getKey(from: password, salt: salt)
        let duration1 = Date().timeIntervalSince(startTime1)
        
        let startTime2 = Date()
        let key2 = try KeyManager.getKey(from: password, salt: salt)
        let duration2 = Date().timeIntervalSince(startTime2)
        
        let key1Data = key1.withUnsafeBytes { Data($0) }
        let key2Data = key2.withUnsafeBytes { Data($0) }
        
        XCTAssertEqual(key1Data, key2Data, "Cached key should be identical")
        XCTAssertLessThan(duration2, duration1 / 10, "Cached key should be much faster")
    }
    
    func testMultiplePasswordsSimultaneous() throws {
        var keys: [Data] = []
        
        for i in 0..<10 {
            let password = "Password\(i)Test123!"
            let salt = "Salt\(i)".data(using: .utf8)!
            let key = try KeyManager.getKey(from: password, salt: salt)
            let keyData = key.withUnsafeBytes { Data($0) }
            keys.append(keyData)
        }
        
        let uniqueKeys = Set(keys)
        XCTAssertEqual(uniqueKeys.count, 10, "All 10 keys should be unique")
    }
}
