//
//  BlazeBinaryLargeRecordTests.swift
//  BlazeDBTests
//
//  Tests for large records, stress testing, and edge cases
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class BlazeBinaryLargeRecordTests: XCTestCase {
    
    func testLargeRecord_100Fields() throws {
        var storage: [String: BlazeDocumentField] = [:]
        for i in 0..<100 {
            storage["field\(i)"] = .string("Value \(i)")
        }
        let record = BlazeDataRecord(storage)
        
        // Dual-codec validation
        try assertCodecsEqual(record)
    }
    
    func testLargeRecord_10000Fields() throws {
        var storage: [String: BlazeDocumentField] = [:]
        for i in 0..<10000 {
            storage["field\(i)"] = .int(i)
        }
        let record = BlazeDataRecord(storage)
        
        // Dual-codec validation
        try assertCodecsEqual(record)
    }
    
    func testLargeRecord_DeepNesting() throws {
        // 3 levels deep
        var level3: [String: BlazeDocumentField] = ["value": .int(42)]
        var level2: [String: BlazeDocumentField] = ["level3": .dictionary(level3)]
        var level1: [String: BlazeDocumentField] = ["level2": .dictionary(level2)]
        let record = BlazeDataRecord(["level1": .dictionary(level1)])
        
        // Dual-codec validation
        try assertCodecsEqual(record)
    }
    
    func testLargeRecord_LargeArray() throws {
        var items: [BlazeDocumentField] = []
        for i in 0..<10000 {
            items.append(.int(i))
        }
        let record = BlazeDataRecord(["items": .array(items)])
        
        // Dual-codec validation
        try assertCodecsEqual(record)
    }
    
    func testLargeRecord_LargeDataBlob() throws {
        let largeData = Data(repeating: 0xFF, count: 10_000_000) // 10MB
        let record = BlazeDataRecord(["data": .data(largeData)])
        
        // Dual-codec validation
        try assertCodecsEqual(record)
    }
    
    func testLargeRecord_MixedTypes() throws {
        var storage: [String: BlazeDocumentField] = [:]
        
        // Add various types
        storage["uuid"] = .uuid(UUID())
        storage["string"] = .string(String(repeating: "x", count: 1000))
        storage["int"] = .int(Int.max)
        storage["double"] = .double(Double.pi)
        storage["bool"] = .bool(true)
        storage["date"] = .date(Date())
        storage["data"] = .data(Data(repeating: 0xAA, count: 1000))
        
        // Add arrays
        var intArray: [BlazeDocumentField] = []
        for i in 0..<100 {
            intArray.append(.int(i))
        }
        storage["intArray"] = .array(intArray)
        
        // Add dictionaries
        var dict: [String: BlazeDocumentField] = [:]
        for i in 0..<50 {
            dict["key\(i)"] = .string("value\(i)")
        }
        storage["dict"] = .dictionary(dict)
        
        let record = BlazeDataRecord(storage)
        
        // Dual-codec validation
        try assertCodecsEqual(record)
    }
}

