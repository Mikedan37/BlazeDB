//
//  PageStoreCodecIntegrationTests.swift
//  BlazeDBTests
//
//  Integration tests for PageStore using dual-codec validation
//
//  Created by Auto on 1/XX/25.
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

final class PageStoreCodecIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    var pageStore: PageStore!
    var key: SymmetricKey!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let fileURL = tempDir.appendingPathComponent("test.blz")
        key = SymmetricKey(size: .bits256)
        pageStore = try! PageStore(fileURL: fileURL, key: key)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Page Write/Read Tests
    
    func testPageWriteRead_DualCodec() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Page Test"),
            "count": .int(42)
        ])
        
        // Encode with standard codec
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        
        // Write page using standard-encoded data
        let pageIndex = 0
        try pageStore.writePage(index: pageIndex, plaintext: stdEncoded)
        
        // Read page
        let readData = try pageStore.readPage(index: pageIndex)
        
        // Decode with both codecs
        guard let readData = readData else {
            XCTFail("Failed to read page")
            return
        }
        let stdDecoded = try BlazeBinaryDecoder.decode(readData)
        let armDecoded = try BlazeBinaryDecoder.decodeARM(readData)
        
        // Both must produce identical results
        assertRecordsEqual(stdDecoded, armDecoded)
        assertRecordsEqual(record, stdDecoded)
        assertRecordsEqual(record, armDecoded)
    }
    
    func testPageWriteRead_ARMCodec() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("ARM Page Test"),
            "count": .int(99)
        ])
        
        // Encode with ARM codec
        let armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        
        // Write page using ARM-encoded data
        let pageIndex = 0
        try pageStore.writePage(index: pageIndex, plaintext: armEncoded)
        
        // Read page
        guard let readData = try pageStore.readPage(index: pageIndex) else {
            XCTFail("Failed to read page")
            return
        }
        
        // Decode with both codecs
        let stdDecoded = try BlazeBinaryDecoder.decode(readData)
        let armDecoded = try BlazeBinaryDecoder.decodeARM(readData)
        
        // Both must produce identical results
        assertRecordsEqual(stdDecoded, armDecoded)
        assertRecordsEqual(record, stdDecoded)
        assertRecordsEqual(record, armDecoded)
    }
    
    // MARK: - Page Boundary Tests
    
    func testPageBoundary_DualCodec() throws {
        // Create record with large data that fits in a single page
        // Max page size is 4096 bytes, with 37 bytes overhead (header + nonce + tag) = 4059 bytes max payload
        // Use a size that ensures encoded record fits (accounting for UUID + encoding overhead)
        // Conservative size: 3500 bytes data + ~50 bytes encoding overhead = ~3550 bytes total
        let largeData = Data(repeating: 0xFF, count: 3500) // Large but fits in one page
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "largeData": .data(largeData)
        ])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        let armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Verify encoded size fits in one page (max 4059 bytes)
        XCTAssertLessThanOrEqual(stdEncoded.count, 4059, "Encoded data must fit in one page (max: 4059 bytes, got: \(stdEncoded.count))")
        
        // Write page (single page, no overflow - writePage doesn't support overflow)
        let pageIndex = 0
        try pageStore.writePage(index: pageIndex, plaintext: stdEncoded)
        
        // Read back
        guard let readData = try pageStore.readPage(index: pageIndex) else {
            XCTFail("Failed to read page")
            return
        }
        
        // Decode with both codecs
        let stdDecoded = try BlazeBinaryDecoder.decode(readData)
        let armDecoded = try BlazeBinaryDecoder.decodeARM(readData)
        
        assertRecordsEqual(stdDecoded, armDecoded)
        assertRecordsEqual(record, stdDecoded)
    }
    
    // MARK: - CRC Validation
    
    func testCRCValidation_DualCodec() throws {
        BlazeBinaryEncoder.crc32Mode = .enabled
        defer { BlazeBinaryEncoder.crc32Mode = .disabled }
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("CRC Test")
        ])
        
        // Encode with both codecs (both should include CRC32)
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        let armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Write page
        let pageIndex = 0
        try pageStore.writePage(index: pageIndex, plaintext: stdEncoded)
        
        // Read back
        guard let readData = try pageStore.readPage(index: pageIndex) else {
            XCTFail("Failed to read page")
            return
        }
        
        // Both decoders should validate CRC32 identically
        let stdDecoded = try BlazeBinaryDecoder.decode(readData)
        let armDecoded = try BlazeBinaryDecoder.decodeARM(readData)
        
        assertRecordsEqual(stdDecoded, armDecoded)
    }
    
    // MARK: - Multiple Pages
    
    func testMultiplePages_DualCodec() throws {
        var pageIndices: [Int] = []
        
        // Write multiple pages with different records
        for i in 0..<10 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string(String(repeating: "x", count: 100))
            ])
            
            // Alternate between codecs
            let encoded = (i % 2 == 0) 
                ? try BlazeBinaryEncoder.encode(record)
                : try BlazeBinaryEncoder.encodeARM(record)
            
            let pageIndex = i
            try pageStore.writePage(index: pageIndex, plaintext: encoded)
            pageIndices.append(pageIndex)
        }
        
        // Read all pages and validate
        for pageIndex in pageIndices {
            guard let readData = try pageStore.readPage(index: pageIndex) else {
                XCTFail("Failed to read page \(pageIndex)")
                continue
            }
            
            let stdDecoded = try BlazeBinaryDecoder.decode(readData)
            let armDecoded = try BlazeBinaryDecoder.decodeARM(readData)
            
            assertRecordsEqual(stdDecoded, armDecoded)
        }
    }
}

