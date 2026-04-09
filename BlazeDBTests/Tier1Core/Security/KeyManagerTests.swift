//  KeyManagerTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

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
    private var tempFile: URL?
    var store: PageStore!

    override func setUpWithError() throws {
        tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blz")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: try requireFixture(tempFile))
    }


    func testPasswordKeyEncryptDecrypt() throws {
        let key = try KeyManager.getKey(from: .password("MySecurePass-99!"))
        let store = try PageStore(fileURL: try requireFixture(tempFile), key: key)

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
        let password = "TestPassword-123"
        let salt1 = "CustomSalt1".data(using: .utf8)!
        let salt2 = "CustomSalt2".data(using: .utf8)!
        
        let key1 = try KeyManager.getKey(from: password, salt: salt1)
        let key2 = try KeyManager.getKey(from: password, salt: salt2)
        
        let key1Data = key1.withUnsafeBytes { Data($0) }
        let key2Data = key2.withUnsafeBytes { Data($0) }
        
        XCTAssertNotEqual(key1Data, key2Data, "Different salts should produce different keys")
    }
    
    func testKeyCacheWorks() throws {
        let password = "CachedPassword-123"
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
    
    func testConcurrentKeyDerivationReturnsSameKeys() async throws {
        // Verify concurrent derivation of the same password/salt returns identical keys
        // and that concurrent derivation of different passwords doesn't corrupt.
        let salt = "concurrent-test".data(using: .utf8)!
        let password = "ConcurrentTestPass!99"

        // Clear cache so derivation actually runs
        KeyManager.clearKeyCache()

        // Derive same key from 20 concurrent tasks
        let keys: [Data] = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let key = try KeyManager.getKey(from: password, salt: salt)
                    return key.withUnsafeBytes { Data($0) }
                }
            }
            var results = [Data]()
            for try await keyData in group {
                results.append(keyData)
            }
            return results
        }

        // All 20 derivations of same password must return same key bytes
        let unique = Set(keys)
        XCTAssertEqual(unique.count, 1, "Same password+salt must always produce same key, even under concurrency")

        // Now verify different passwords don't poison each other
        KeyManager.clearKeyCache()
        let distinctKeys: [Data] = try await withThrowingTaskGroup(of: Data.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let key = try KeyManager.getKey(from: "DistinctPass\(i)!Secure", salt: salt)
                    return key.withUnsafeBytes { Data($0) }
                }
            }
            var results = [Data]()
            for try await keyData in group {
                results.append(keyData)
            }
            return results
        }
        let distinctSet = Set(distinctKeys)
        XCTAssertEqual(distinctSet.count, 10, "10 different passwords should produce 10 different keys under concurrency")
    }

    func testClearKeyCacheUnderConcurrency() async throws {
        let salt = "clear-test".data(using: .utf8)!

        // Derive some keys, then clear while deriving more
        _ = try KeyManager.getKey(from: "PreClearPass!Secure1", salt: salt)

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Clear cache mid-flight
            group.addTask {
                KeyManager.clearKeyCache()
            }
            // Derive concurrently
            for i in 0..<10 {
                group.addTask {
                    _ = try KeyManager.getKey(from: "MidClearPass\(i)!Secure", salt: salt)
                }
            }
            try await group.waitForAll()
        }

        // Post-clear, fresh derivation must still work
        let key = try KeyManager.getKey(from: "PostClearPass!Secure1", salt: salt)
        XCTAssertEqual(key.bitCount, 256, "Key derivation must work after concurrent clear")
    }

    func testMultiplePasswordsSimultaneous() throws {
        var keys: [Data] = []
        
        for i in 0..<10 {
            let password = "Password\(i)-Test1234"
            let salt = "Salt\(i)".data(using: .utf8)!
            let key = try KeyManager.getKey(from: password, salt: salt)
            let keyData = key.withUnsafeBytes { Data($0) }
            keys.append(keyData)
        }
        
        let uniqueKeys = Set(keys)
        XCTAssertEqual(uniqueKeys.count, 10, "All 10 keys should be unique")
    }
}
