//
//  EncryptionRoundTripVerificationTests.swift
//  BlazeDBTests
//
//  Low-level encryption/decryption verification to catch byte-level bugs
//  like the AES-GCM ciphertext padding issue we found.
//
//  These tests verify that data survives encryption → decryption with
//  BYTE-PERFECT accuracy across all edge cases.
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

final class EncryptionRoundTripVerificationTests: XCTestCase {
    
    var tempURL: URL!
    var store: PageStore!
    var key: SymmetricKey!
    
    override func setUp() {
        super.setUp()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncRoundTrip-\(testID).blazedb")
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
        
        // Generate test key
        key = SymmetricKey(size: .bits256)
        store = try! PageStore(fileURL: tempURL, key: key)
    }
    
    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }
    
    // MARK: - Basic Round-Trip Tests
    
    /// Test: Write 1 byte, read 1 byte, verify exact match
    func testSingleByteRoundTrip() throws {
        let original = Data([0x42])
        
        try store.writePage(index: 0, plaintext: original)
        let retrieved = try store.readPage(index: 0)
        
        XCTAssertNotNil(retrieved, "Data should not be nil")
        XCTAssertEqual(retrieved, original, "Single byte should survive round-trip")
    }
    
    /// Test: Empty data round-trip
    func testEmptyDataRoundTrip() throws {
        let original = Data()
        
        try store.writePage(index: 0, plaintext: original)
        let retrieved = try store.readPage(index: 0)
        
        // Empty data is valid and should return empty Data
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.count ?? -1, 0, "Empty data should return empty Data")
    }
    
    /// Test: Various data sizes (especially near AES block boundaries)
    func testVariousDataSizes() throws {
        // Test sizes that exposed the AES-GCM padding bug:
        // 105 bytes was being rounded to 112
        // 119 bytes was being rounded to 128
        let testSizes = [
            1, 15, 16, 17,        // Around AES block boundary (16 bytes)
            31, 32, 33,           // 2 blocks
            105, 112,             // Bug case #1
            119, 128,             // Bug case #2
            255, 256, 257,        // Power of 2
            1000, 2000, 3000      // Larger sizes
        ]
        
        for size in testSizes {
            let original = Data((0..<size).map { UInt8($0 % 256) })
            
            try store.writePage(index: 0, plaintext: original)
            let retrieved = try store.readPage(index: 0)
            
            XCTAssertNotNil(retrieved, "Size \(size): Data should not be nil")
            XCTAssertEqual(retrieved?.count, size, "Size \(size): Length should match exactly")
            XCTAssertEqual(retrieved, original, "Size \(size): Data should match byte-for-byte")
        }
    }
    
    /// Test: Maximum page size (edge of 4KB page)
    func testMaximumPageSize() throws {
        // Max plaintext is pageSize - encryption overhead (37 bytes: header + nonce + tag)
        let maxSize = 4096 - 37
        let original = Data(repeating: 0xAB, count: maxSize)
        
        try store.writePage(index: 0, plaintext: original)
        let retrieved = try store.readPage(index: 0)
        
        XCTAssertEqual(retrieved, original, "Max size data should survive round-trip")
    }
    
    // MARK: - AES-GCM Specific Tests
    
    /// Test: Verify ciphertext length equals plaintext length (not rounded)
    func testCiphertextNotRounded() throws {
        // This test would have caught the bug!
        let plaintext = Data(repeating: 0xFF, count: 105)  // Not divisible by 16
        
        try store.writePage(index: 0, plaintext: plaintext)
        
        // Read the raw page to inspect ciphertext
        let fileHandle = try FileHandle(forReadingFrom: tempURL)
        defer { try? fileHandle.close() }
        
        let page = try fileHandle.read(upToCount: 4096)!
        
        // Extract ciphertext length from page structure:
        // [BZDB][0x02][length:4][nonce:12][tag:16][ciphertext:N][padding]
        let plaintextLength = Int(page.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        let ciphertext = page.subdata(in: 37..<(37 + plaintextLength))
        
        XCTAssertEqual(plaintextLength, 105, "Plaintext length should be 105")
        XCTAssertEqual(ciphertext.count, 105, "Ciphertext should be exactly 105 bytes, NOT rounded to 112!")
    }
    
    /// Test: Multiple writes to same page
    func testOverwriteSamePage() throws {
        let data1 = "First write".data(using: .utf8)!
        let data2 = "Second write with different length".data(using: .utf8)!
        
        // Write first data
        try store.writePage(index: 0, plaintext: data1)
        let retrieved1 = try store.readPage(index: 0)
        XCTAssertEqual(retrieved1, data1)
        
        // Overwrite with different data
        try store.writePage(index: 0, plaintext: data2)
        let retrieved2 = try store.readPage(index: 0)
        XCTAssertEqual(retrieved2, data2)
        XCTAssertNotEqual(retrieved2, data1, "Old data should be completely overwritten")
    }
    
    // MARK: - Multi-Page Tests
    
    /// Test: Write and read multiple pages
    func testMultiplePagesRoundTrip() throws {
        let pageCount = 100
        
        // Write unique data to each page
        for i in 0..<pageCount {
            let data = "Page \(i) data".data(using: .utf8)!
            try store.writePage(index: i, plaintext: data)
        }
        
        // Verify all pages readable
        for i in 0..<pageCount {
            let expected = "Page \(i) data".data(using: .utf8)!
            let retrieved = try store.readPage(index: i)
            
            XCTAssertNotNil(retrieved, "Page \(i) should be readable")
            XCTAssertEqual(retrieved, expected, "Page \(i) data should match")
        }
    }
    
    /// Test: Sparse page writes (non-sequential)
    func testSparsePageWrites() throws {
        let pages = [0, 5, 10, 100, 500]
        
        for pageIndex in pages {
            let data = "Sparse page \(pageIndex)".data(using: .utf8)!
            try store.writePage(index: pageIndex, plaintext: data)
        }
        
        // Verify all written pages
        for pageIndex in pages {
            let expected = "Sparse page \(pageIndex)".data(using: .utf8)!
            let retrieved = try store.readPage(index: pageIndex)
            XCTAssertEqual(retrieved, expected)
        }
        
        // Verify unwritten pages return nil
        XCTAssertNil(try store.readPage(index: 1))
        XCTAssertNil(try store.readPage(index: 50))
    }
    
    // MARK: - Key Consistency Tests
    
    /// Test: Same key encrypts/decrypts consistently
    func testKeyConsistency() throws {
        let data = "Test data".data(using: .utf8)!
        
        // Write with key
        try store.writePage(index: 0, plaintext: data)
        
        // Read with same key (should work)
        let retrieved = try store.readPage(index: 0)
        XCTAssertEqual(retrieved, data)
        
        // Try to read with different key (should fail)
        let wrongKey = SymmetricKey(size: .bits256)
        let wrongStore = try PageStore(fileURL: tempURL, key: wrongKey)
        
        XCTAssertThrowsError(try wrongStore.readPage(index: 0)) { error in
            // Should get authentication failure
            let nsError = error as NSError
            XCTAssertTrue(nsError.domain.contains("CryptoKit") || 
                         nsError.localizedDescription.contains("authentication"),
                         "Wrong key should cause authentication failure")
        }
    }
    
    // MARK: - Random Data Tests
    
    /// Test: Random data round-trip (property-based)
    func testRandomDataRoundTrip() throws {
        for _ in 0..<100 {
            let size = Int.random(in: 1...3000)
            var original = Data(count: size)
            _ = original.withUnsafeMutableBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                arc4random_buf(baseAddress, size)
            }
            
            let pageIndex = Int.random(in: 0..<1000)
            try store.writePage(index: pageIndex, plaintext: original)
            let retrieved = try store.readPage(index: pageIndex)
            
            XCTAssertEqual(retrieved, original, "Random data (size: \(size)) should survive round-trip")
        }
    }
    
    // MARK: - Corruption Detection Tests
    
    /// Test: Detect file corruption
    func testDetectFileCorruption() throws {
        // Write a larger record to ensure we have substantial encrypted data
        let largeData = Data(repeating: 0xAB, count: 1000)
        try store.writePage(index: 0, plaintext: largeData)
        
        // Read back to verify it was written correctly
        if let readBack = try store.readPage(index: 0) {
            XCTAssertEqual(readBack, largeData, "Data should round-trip correctly before corruption")
        } else {
            XCTFail("Failed to read back data after writing")
            return
        }
        
        // Get file size to ensure we corrupt actual data
        let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as! UInt64
        print("📁 File size: \(fileSize) bytes")
        
        guard fileSize > 200 else {
            XCTFail("File too small (\(fileSize) bytes)")
            return
        }
        
        // Close store to ensure everything is flushed
        store = nil
        
        // Read entire file to see structure
        let originalFile = try Data(contentsOf: tempURL)
        print("📄 Original file size: \(originalFile.count) bytes")
        
        // Corrupt multiple bytes throughout the encrypted data area
        // Target multiple locations to ensure we hit encrypted page data
        var corruptedFile = originalFile
        let corruptionOffsets = [64, 128, 256, 512, 1024]
        for offset in corruptionOffsets where offset < corruptedFile.count {
            corruptedFile[offset] ^= 0xFF  // Flip all bits
            print("💥 Corrupted byte at offset \(offset)")
        }
        
        try corruptedFile.write(to: tempURL)
        
        // Try to read with new store - should fail authentication
        let newStore = try PageStore(fileURL: tempURL, key: key)
        
        do {
            let result = try newStore.readPage(index: 0)
            let resultCount = result?.count ?? 0
            XCTFail("Should have thrown error on corrupted data, but read \(resultCount) bytes successfully")
        } catch {
            // Success - corruption was detected
            print("✅ Corruption detected: \(error)")
            XCTAssertTrue(error.localizedDescription.contains("authentication") ||
                         error.localizedDescription.contains("corrupt") ||
                         error.localizedDescription.contains("decrypt") ||
                         error.localizedDescription.contains("CryptoKit"),
                         "Should detect corruption, got: \(error)")
        }
    }
    
    /// Test: Detect tag tampering
    func testDetectTagTampering() throws {
        let data = "Secret data".data(using: .utf8)!
        try store.writePage(index: 0, plaintext: data)
        
        store = nil
        
        // Corrupt the authentication tag (bytes 21-37)
        let fileHandle = try FileHandle(forUpdating: tempURL)
        defer { try? fileHandle.close() }
        
        try fileHandle.seek(toOffset: 25)  // Middle of tag
        try fileHandle.write(contentsOf: Data([0x00]))
        try fileHandle.synchronize()
        
        // Should fail authentication
        let newStore = try PageStore(fileURL: tempURL, key: key)
        XCTAssertThrowsError(try newStore.readPage(index: 0), "Tampered tag should be detected")
    }
    
    // MARK: - Concurrent Access Tests
    
    /// Test: Concurrent writes to different pages
    func testConcurrentWritesDifferentPages() throws {
        let group = DispatchGroup()
        var errors: [Error] = []
        let errorLock = NSLock()
        
        // Write 100 pages concurrently
        for i in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    let data = "Page \(i)".data(using: .utf8)!
                    try self.store.writePage(index: i, plaintext: data)
                } catch {
                    errorLock.lock()
                    errors.append(error)
                    errorLock.unlock()
                }
            }
        }
        
        group.wait()
        XCTAssertTrue(errors.isEmpty, "Concurrent writes should not cause errors: \(errors)")
        
        // Verify all pages readable
        for i in 0..<100 {
            let expected = "Page \(i)".data(using: .utf8)!
            let retrieved = try store.readPage(index: i)
            XCTAssertEqual(retrieved, expected, "Page \(i) should be readable after concurrent writes")
        }
    }
    
    /// Test: Concurrent read/write doesn't cause corruption
    func testConcurrentReadWrite() throws {
        // Pre-populate 50 pages
        for i in 0..<50 {
            try store.writePage(index: i, plaintext: "Initial \(i)".data(using: .utf8)!)
        }
        
        let group = DispatchGroup()
        var errors: [Error] = []
        let errorLock = NSLock()
        
        // Concurrent readers and writers
        for _ in 0..<20 {
            // Readers
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    for i in 0..<50 {
                        _ = try self.store.readPage(index: i)
                    }
                } catch {
                    errorLock.lock()
                    errors.append(error)
                    errorLock.unlock()
                }
            }
            
            // Writers
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    let page = Int.random(in: 0..<50)
                    try self.store.writePage(index: page, plaintext: "Updated".data(using: .utf8)!)
                } catch {
                    errorLock.lock()
                    errors.append(error)
                    errorLock.unlock()
                }
            }
        }
        
        group.wait()
        XCTAssertTrue(errors.isEmpty, "Concurrent read/write should be thread-safe: \(errors)")
    }
}

