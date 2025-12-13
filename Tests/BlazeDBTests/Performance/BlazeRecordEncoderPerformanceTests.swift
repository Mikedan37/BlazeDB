//
//  BlazeRecordEncoderPerformanceTests.swift
//  BlazeDBTests
//
//  Performance benchmarks comparing JSON vs Direct BlazeRecord encoding/decoding
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class BlazeRecordEncoderPerformanceTests: XCTestCase {
    
    struct TestRecord: BlazeRecord {
        static var collection: String { "test" }
        var id: UUID
        var createdAt: Date
        var title: String
        var description: String
        var count: Int
        var price: Double
        var isActive: Bool
        var tags: [String]
        var metadata: [String: String]
    }
    
    var testRecord: TestRecord!
    var testRecords: [TestRecord]!
    
    override func setUp() {
        super.setUp()
        testRecord = TestRecord(
            id: UUID(),
            createdAt: Date(),
            title: "Test Record",
            description: "This is a test record with some content that needs to be encoded and decoded",
            count: 42,
            price: 99.99,
            isActive: true,
            tags: ["tag1", "tag2", "tag3", "tag4", "tag5"],
            metadata: [
                "key1": "value1",
                "key2": "value2",
                "key3": "value3",
                "key4": "value4",
                "key5": "value5"
            ]
        )
        
        // Create 1000 test records for batch testing
        testRecords = (0..<1000).map { i in
            TestRecord(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: Double(i)),
                title: "Record \(i)",
                description: "Description for record \(i) with some content",
                count: i,
                price: Double(i) * 1.5,
                isActive: i % 2 == 0,
                tags: ["tag\(i)", "tag\(i+1)", "tag\(i+2)"],
                metadata: ["key\(i)": "value\(i)"]
            )
        }
    }
    
    // MARK: - Encoding Performance
    
    func testPerformance_JSONEncoding() {
        measure {
            for _ in 0..<100 {
                _ = try? jsonEncode(testRecord)
            }
        }
    }
    
    func testPerformance_DirectEncoding() {
        measure {
            for _ in 0..<100 {
                _ = try? directEncodingEncode(testRecord)
            }
        }
    }
    
    func testPerformance_JSONEncoding_Batch() {
        measure {
            _ = try? jsonEncodeBatch(testRecords)
        }
    }
    
    func testPerformance_DirectEncoding_Batch() {
        measure {
            _ = try? directEncodingEncodeBatch(testRecords)
        }
    }
    
    // MARK: - Decoding Performance
    
    func testPerformance_JSONDecoding() throws {
        let jsonData = try jsonEncode(testRecord)
        // BlazeDataRecord expects JSON with "storage" key, so wrap it
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]
        let wrappedJSON = ["storage": jsonObject]
        let wrappedData = try JSONSerialization.data(withJSONObject: wrappedJSON)
        let blazeRecord = try JSONDecoder().decode(BlazeDataRecord.self, from: wrappedData)
        
        measure {
            for _ in 0..<100 {
                _ = try? jsonDecode(blazeRecord)
            }
        }
    }
    
    func testPerformance_DirectDecoding() throws {
        let encoder = BlazeRecordEncoder()
        try testRecord.encode(to: encoder)
        let blazeRecord = encoder.getBlazeDataRecord()
        
        measure {
            for _ in 0..<100 {
                _ = try? directDecode(blazeRecord)
            }
        }
    }
    
    func testPerformance_JSONDecoding_Batch() throws {
        let blazeRecords = try jsonEncodeBatch(testRecords)
        
        measure {
            _ = try? jsonDecodeBatch(blazeRecords)
        }
    }
    
    func testPerformance_DirectDecoding_Batch() throws {
        let blazeRecords = try directEncodingEncodeBatch(testRecords)
        
        measure {
            _ = try? directDecodeBatch(blazeRecords)
        }
    }
    
    // MARK: - Memory Usage
    
    func testMemoryUsage_JSON() throws {
        let jsonData = try jsonEncode(testRecord)
        let jsonSize = jsonData.count
        
        // BlazeDataRecord expects JSON with "storage" key, so wrap it
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]
        let wrappedJSON = ["storage": jsonObject]
        let wrappedData = try JSONSerialization.data(withJSONObject: wrappedJSON)
        let blazeRecord = try JSONDecoder().decode(BlazeDataRecord.self, from: wrappedData)
        let blazeBinary = try BlazeBinaryEncoder.encodeOptimized(blazeRecord)
        let blazeBinarySize = blazeBinary.count
        
        print("📊 JSON Approach Memory:")
        print("  JSON Data: \(jsonSize) bytes")
        print("  BlazeBinary: \(blazeBinarySize) bytes")
        print("  Total: \(jsonSize + blazeBinarySize) bytes")
        
        XCTAssertGreaterThan(jsonSize, 0)
    }
    
    func testMemoryUsage_Direct() throws {
        let encoder = BlazeRecordEncoder()
        try testRecord.encode(to: encoder)
        let blazeRecord = encoder.getBlazeDataRecord()
        let blazeBinary = try BlazeBinaryEncoder.encodeOptimized(blazeRecord)
        let blazeBinarySize = blazeBinary.count
        
        print("📊 Direct Approach Memory:")
        print("  BlazeBinary: \(blazeBinarySize) bytes")
        print("  Total: \(blazeBinarySize) bytes")
        
        XCTAssertGreaterThan(blazeBinarySize, 0)
    }
    
    // MARK: - Helper Methods
    
    private func jsonEncode(_ record: TestRecord) throws -> Data {
        let jsonData = try JSONEncoder().encode(record)
        return jsonData
    }
    
    private func directEncodingEncode(_ record: TestRecord) throws -> BlazeDataRecord {
        let encoder = BlazeRecordEncoder()
        // TestRecord should automatically request a keyed container when encoding
        // If it requests a single value container, that's a bug in the encoder
        try record.encode(to: encoder)
        return encoder.getBlazeDataRecord()
    }
    
    private func jsonEncodeBatch(_ records: [TestRecord]) throws -> [BlazeDataRecord] {
        return try records.map { record in
            let jsonData = try JSONEncoder().encode(record)
            // BlazeDataRecord expects JSON with "storage" key, so wrap it
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]
            let wrappedJSON = ["storage": jsonObject]
            let wrappedData = try JSONSerialization.data(withJSONObject: wrappedJSON)
            return try JSONDecoder().decode(BlazeDataRecord.self, from: wrappedData)
        }
    }
    
    private func directEncodingEncodeBatch(_ records: [TestRecord]) throws -> [BlazeDataRecord] {
        return try records.map { record in
            let encoder = BlazeRecordEncoder()
            try record.encode(to: encoder)
            return encoder.getBlazeDataRecord()
        }
    }
    
    private func jsonDecode(_ blazeRecord: BlazeDataRecord) throws -> TestRecord {
        var jsonObject: [String: Any] = [:]
        for (key, field) in blazeRecord.storage {
            jsonObject[key] = try convertBlazeFieldToJSON(field)
        }
        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TestRecord.self, from: jsonData)
    }
    
    private func directDecode(_ blazeRecord: BlazeDataRecord) throws -> TestRecord {
        let decoder = BlazeRecordDecoder(storage: blazeRecord.storage)
        return try TestRecord(from: decoder)
    }
    
    private func jsonDecodeBatch(_ blazeRecords: [BlazeDataRecord]) throws -> [TestRecord] {
        return try blazeRecords.map { try jsonDecode($0) }
    }
    
    private func directDecodeBatch(_ blazeRecords: [BlazeDataRecord]) throws -> [TestRecord] {
        return try blazeRecords.map { try directDecode($0) }
    }
    
    private func convertBlazeFieldToJSON(_ field: BlazeDocumentField) throws -> Any {
        switch field {
        case .string(let str): return str
        case .int(let num): return num
        case .double(let num): return num
        case .bool(let bool): return bool
        case .date(let date): return ISO8601DateFormatter().string(from: date)
        case .uuid(let uuid): return uuid.uuidString
        case .data(let data): return data.base64EncodedString()
        case .array(let array): return try array.map { try convertBlazeFieldToJSON($0) }
        case .dictionary(let dict):
            var jsonDict: [String: Any] = [:]
            for (key, value) in dict {
                jsonDict[key] = try convertBlazeFieldToJSON(value)
            }
            return jsonDict
        case .null: return NSNull()
        case .vector(let vec): return vec
        }
    }
}

