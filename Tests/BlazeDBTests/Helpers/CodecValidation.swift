//
//  CodecValidation.swift
//  BlazeDBTests
//
//  Dual-codec validation helpers ensuring Standard and ARM codecs produce identical results
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

/// Assert that both Standard and ARM codecs produce identical encoded bytes
func assertCodecsEncodeEqual(_ record: BlazeDataRecord, file: StaticString = #file, line: UInt = #line) throws {
    let stdEncoded = try BlazeBinaryEncoder.encode(record)
    let armEncoded = try BlazeBinaryEncoder.encodeARM(record)
    
    XCTAssertEqual(stdEncoded, armEncoded, "Standard and ARM encoders must produce identical bytes", file: file, line: line)
}

/// Assert that both Standard and ARM codecs produce identical decoded records
func assertCodecsDecodeEqual(_ data: Data, file: StaticString = #file, line: UInt = #line) throws {
    let stdDecoded = try BlazeBinaryDecoder.decode(data)
    let armDecoded = try BlazeBinaryDecoder.decodeARM(data)
    
    XCTAssertEqual(stdDecoded.storage.count, armDecoded.storage.count, "Decoded record field counts must match", file: file, line: line)
    
    for (key, stdValue) in stdDecoded.storage {
        guard let armValue = armDecoded.storage[key] else {
            XCTFail("ARM decoder missing key: \(key)", file: file, line: line)
            continue
        }
        XCTAssertEqual(stdValue, armValue, "Value mismatch for key: \(key)", file: file, line: line)
    }
    
    for (key, _) in armDecoded.storage {
        if stdDecoded.storage[key] == nil {
            XCTFail("Standard decoder missing key: \(key)", file: file, line: line)
        }
    }
}

/// Assert that both Standard and ARM codecs produce identical results (encode + decode round-trip)
func assertCodecsEqual(_ record: BlazeDataRecord, file: StaticString = #file, line: UInt = #line) throws {
    
    let stdEncoded = try BlazeBinaryEncoder.encode(record)
    let armEncoded = try BlazeBinaryEncoder.encodeARM(record)
    
    // Assert encoded bytes are identical
    XCTAssertEqual(stdEncoded, armEncoded, "Standard and ARM encoders must produce identical bytes", file: file, line: line)
    
    // Decode standard-encoded data with both decoders
    let stdDecodedFromStd = try BlazeBinaryDecoder.decode(stdEncoded)
    let armDecodedFromStd = try BlazeBinaryDecoder.decodeARM(stdEncoded)
    
    // Decode ARM-encoded data with both decoders
    let stdDecodedFromARM = try BlazeBinaryDecoder.decode(armEncoded)
    let armDecodedFromARM = try BlazeBinaryDecoder.decodeARM(armEncoded)
    
    // Assert all decoded records match original
    assertRecordsEqual(record, stdDecodedFromStd, file: file, line: line)
    assertRecordsEqual(record, armDecodedFromStd, file: file, line: line)
    assertRecordsEqual(record, stdDecodedFromARM, file: file, line: line)
    assertRecordsEqual(record, armDecodedFromARM, file: file, line: line)
    
    // Assert all decoded records match each other
    assertRecordsEqual(stdDecodedFromStd, armDecodedFromStd, file: file, line: line)
    assertRecordsEqual(stdDecodedFromStd, stdDecodedFromARM, file: file, line: line)
    assertRecordsEqual(stdDecodedFromStd, armDecodedFromARM, file: file, line: line)
}

/// Recursively compare two BlazeDocumentField values, handling NaN at all levels
func fieldsEqual(_ field1: BlazeDocumentField, _ field2: BlazeDocumentField, file: StaticString = #file, line: UInt = #line) -> Bool {
    switch (field1, field2) {
    case (.double(let d1), .double(let d2)):
        // Special handling for NaN values (NaN != NaN in IEEE 754)
        if d1.isNaN && d2.isNaN {
            return true
        }
        return d1 == d2
        
    case (.array(let arr1), .array(let arr2)):
        guard arr1.count == arr2.count else { return false }
        for (item1, item2) in zip(arr1, arr2) {
            if !fieldsEqual(item1, item2, file: file, line: line) {
                return false
            }
        }
        return true
        
    case (.dictionary(let dict1), .dictionary(let dict2)):
        guard dict1.count == dict2.count else { return false }
        for (key, value1) in dict1 {
            guard let value2 = dict2[key] else { return false }
            if !fieldsEqual(value1, value2, file: file, line: line) {
                return false
            }
        }
        return true
        
    default:
        return field1 == field2
    }
}

/// Assert that two records are equal
func assertRecordsEqual(_ record1: BlazeDataRecord, _ record2: BlazeDataRecord, file: StaticString = #file, line: UInt = #line) {
    
    XCTAssertEqual(record1.storage.count, record2.storage.count, "Record field counts must match", file: file, line: line)
    
    for (key, value1) in record1.storage {
        guard let value2 = record2.storage[key] else {
            XCTFail("Record2 missing key: \(key)", file: file, line: line)
            continue
        }
        
        if !fieldsEqual(value1, value2, file: file, line: line) {
            XCTFail("Value mismatch for key: \(key)", file: file, line: line)
        }
    }
    
    for (key, _) in record2.storage {
        if record1.storage[key] == nil {
            XCTFail("Record1 missing key: \(key)", file: file, line: line)
        }
    }
}

/// Assert that both Standard and ARM codecs throw an error for the given corrupted data, and their error descriptions match.
func assertCodecsErrorEqual(_ corruptedData: Data, file: StaticString = #file, line: UInt = #line) {
    var stdError: Error?
    var armError: Error?

    XCTAssertThrowsError(try BlazeBinaryDecoder.decode(corruptedData), "Standard decoder should throw an error", file: file, line: line) { error in
        stdError = error
    }
    XCTAssertThrowsError(try BlazeBinaryDecoder.decodeARM(corruptedData), "ARM decoder should throw an error", file: file, line: line) { error in
        armError = error
    }

    XCTAssertNotNil(stdError, "Standard decoder error should not be nil", file: file, line: line)
    XCTAssertNotNil(armError, "ARM decoder error should not be nil", file: file, line: line)

    if let stdErr = stdError as? BlazeBinaryError, let armErr = armError as? BlazeBinaryError {
        XCTAssertEqual(stdErr.errorDescription, armErr.errorDescription, "Error descriptions must match for corrupted data", file: file, line: line)
    } else if let stdErr = stdError, let armErr = armError {
        XCTAssertEqual(stdErr.localizedDescription, armErr.localizedDescription, "Localized error descriptions must match for corrupted data", file: file, line: line)
    } else {
        XCTFail("Both errors must be non-nil and of expected type for comparison", file: file, line: line)
    }
}

/// Asserts that both standard and ARM codecs produce identical records when decoding from a memory-mapped page.
func assertCodecsMMapEqual(from ptr: UnsafeRawPointer, length: Int, expectedRecord: BlazeDataRecord, file: StaticString = #file, line: UInt = #line) throws {
    // Convert pointer to Data for standard decoder
    let data = Data(bytes: ptr, count: length)
    let stdDecoded = try BlazeBinaryDecoder.decode(data)
    let armDecoded = try BlazeBinaryDecoder.decodeARM(fromMemoryMappedPage: ptr, length: length)

    XCTAssertEqual(stdDecoded, expectedRecord, "Standard mmap decode output mismatch", file: file, line: line)
    XCTAssertEqual(armDecoded, expectedRecord, "ARM mmap decode output mismatch", file: file, line: line)
    XCTAssertEqual(stdDecoded, armDecoded, "Mmap decoded records from both codecs must be identical", file: file, line: line)
}

/// Measures and compares the performance of ARM vs Standard codecs, asserting ARM is faster.
func measureCodecPerformance(
    testCase: XCTestCase,
    description: String,
    iterations: Int,
    record: BlazeDataRecord,
    minSpeedupFactor: Double = 1.4, // 40% faster
    file: StaticString = #file, line: UInt = #line
) throws {
    // First, ensure correctness
    try assertCodecsEqual(record, file: file, line: line)

    var standardEncodeTime: TimeInterval = 0
    var armEncodeTime: TimeInterval = 0
    var standardDecodeTime: TimeInterval = 0
    var armDecodeTime: TimeInterval = 0

    // Measure Standard Encode
    let standardEncodeStart = Date()
    for _ in 0..<iterations {
        _ = try BlazeBinaryEncoder.encode(record)
    }
    standardEncodeTime = Date().timeIntervalSince(standardEncodeStart)

    // Measure ARM Encode
    let armEncodeStart = Date()
    for _ in 0..<iterations {
        _ = try BlazeBinaryEncoder.encodeARM(record)
    }
    armEncodeTime = Date().timeIntervalSince(armEncodeStart)

    let encodedStandard = try BlazeBinaryEncoder.encode(record)
    let encodedARM = try BlazeBinaryEncoder.encodeARM(record)

    // Measure Standard Decode
    let standardDecodeStart = Date()
    for _ in 0..<iterations {
        _ = try BlazeBinaryDecoder.decode(encodedStandard)
    }
    standardDecodeTime = Date().timeIntervalSince(standardDecodeStart)

    // Measure ARM Decode
    let armDecodeStart = Date()
    for _ in 0..<iterations {
        _ = try BlazeBinaryDecoder.decodeARM(encodedARM)
    }
    armDecodeTime = Date().timeIntervalSince(armDecodeStart)

    XCTAssertLessThanOrEqual(armEncodeTime, standardEncodeTime, "ARM encode should be faster or equal for \(description)", file: file, line: line)
    XCTAssertLessThanOrEqual(armDecodeTime, standardDecodeTime, "ARM decode should be faster or equal for \(description)", file: file, line: line)

    let encodeSpeedup = standardEncodeTime / armEncodeTime
    let decodeSpeedup = standardDecodeTime / armDecodeTime

    XCTAssertGreaterThanOrEqual(encodeSpeedup, minSpeedupFactor, "ARM encode speedup (\(String(format: "%.2fx", encodeSpeedup))) for \(description) is below \(String(format: "%.2fx", minSpeedupFactor))", file: file, line: line)
    XCTAssertGreaterThanOrEqual(decodeSpeedup, minSpeedupFactor, "ARM decode speedup (\(String(format: "%.2fx", decodeSpeedup))) for \(description) is below \(String(format: "%.2fx", minSpeedupFactor))", file: file, line: line)

    print("Performance for \(description):")
    print("  Encode - Standard: \(String(format: "%.4f", standardEncodeTime))s, ARM: \(String(format: "%.4f", armEncodeTime))s (Speedup: \(String(format: "%.2fx", encodeSpeedup)))")
    print("  Decode - Standard: \(String(format: "%.4f", standardDecodeTime))s, ARM: \(String(format: "%.4f", armDecodeTime))s (Speedup: \(String(format: "%.2fx", decodeSpeedup)))")
}
