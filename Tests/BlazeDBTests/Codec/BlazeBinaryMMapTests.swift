//
//  BlazeBinaryMMapTests.swift
//  BlazeDBTests
//
//  Memory-mapped decode tests for zero-copy decoding
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class BlazeBinaryMMapTests: XCTestCase {
    
    var tempFile: URL!
    
    override func setUp() {
        super.setUp()
        tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("blazedb")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFile)
        super.tearDown()
    }
    
    func testMMapDecode_SmallRecord() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Small Record")
        ])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        let armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        try armEncoded.write(to: tempFile)
        
        // Memory-map the file
        let fileHandle = try FileHandle(forReadingFrom: tempFile)
        defer { fileHandle.closeFile() }
        
        let data = try fileHandle.readToEnd()
        guard let data = data else {
            XCTFail("Failed to read file")
            return
        }
        
        // Decode standard-encoded data with both decoders
        let stdDecoded = try BlazeBinaryDecoder.decode(data)
        
        // Decode from memory-mapped buffer (ARM-specific)
        let armDecoded = try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw BlazeBinaryError.invalidFormat("Invalid buffer")
            }
            return try BlazeBinaryDecoder.decodeARM(fromMemoryMappedPage: baseAddress, length: data.count)
        }
        
        // Both decoders must produce identical results
        assertRecordsEqual(stdDecoded, armDecoded)
        XCTAssertEqual(armDecoded.storage.count, 2)
        XCTAssertEqual(armDecoded.storage["title"]?.stringValue, "Small Record")
    }
    
    func testMMapDecode_LargeRecord() throws {
        var storage: [String: BlazeDocumentField] = [:]
        for i in 0..<100 {
            storage["field\(i)"] = .string("Value \(i) " + String(repeating: "x", count: 100))
        }
        let record = BlazeDataRecord(storage)
        
        // Dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        try encoded.write(to: tempFile)
        
        let fileHandle = try FileHandle(forReadingFrom: tempFile)
        defer { fileHandle.closeFile() }
        
        let data = try fileHandle.readToEnd()
        guard let data = data else {
            XCTFail("Failed to read file")
            return
        }
        
        // Decode with both codecs
        let stdDecoded = try BlazeBinaryDecoder.decode(data)
        let armDecoded = try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw BlazeBinaryError.invalidFormat("Invalid buffer")
            }
            return try BlazeBinaryDecoder.decodeARM(fromMemoryMappedPage: baseAddress, length: data.count)
        }
        
        assertRecordsEqual(stdDecoded, armDecoded)
        XCTAssertEqual(armDecoded.storage.count, 100)
    }
    
    func testMMapDecode_AfterUnmap() throws {
        let record = BlazeDataRecord([
            "title": .string("Test")
        ])
        
        // Dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        
        // Decode and store result before buffer is released
        var decoded: BlazeDataRecord!
        encoded.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            decoded = try? BlazeBinaryDecoder.decodeARM(fromMemoryMappedPage: baseAddress, length: encoded.count)
        }
        
        // Buffer is now unmapped, but decoded record should still be valid
        XCTAssertNotNil(decoded)
        assertRecordsEqual(record, decoded)
        XCTAssertEqual(decoded.storage["title"]?.stringValue, "Test")
    }
    
    func testMMapDecode_PageBoundary() throws {
        // Create record that might span page boundaries
        let largeData = Data(repeating: 0xFF, count: 4096) // Page size
        let record = BlazeDataRecord([
            "data": .data(largeData)
        ])
        
        // Dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        
        // Decode standard way
        let stdDecoded = try BlazeBinaryDecoder.decode(encoded)
        
        // Decode memory-mapped way
        let armDecoded = try encoded.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw BlazeBinaryError.invalidFormat("Invalid buffer")
            }
            return try BlazeBinaryDecoder.decodeARM(fromMemoryMappedPage: baseAddress, length: encoded.count)
        }
        
        assertRecordsEqual(stdDecoded, armDecoded)
        XCTAssertEqual(armDecoded.storage["data"]?.dataValue, largeData)
    }
}

