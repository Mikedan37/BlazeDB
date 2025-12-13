//
//  BlazeCollectionCompatibilityTests.swift
//  BlazeDBTests
//
//  MIGRATED: Now uses BlazeDBClient + DynamicCollection instead of deprecated BlazeCollection
//  Tests verify encoding/decoding compatibility using the recommended API
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class BlazeCollectionCompatibilityTests: XCTestCase {
    
    struct TestRecord: BlazeRecord {
        static var collection: String { "test" }
        var id: UUID
        var title: String
        var description: String
        var count: Int
        var price: Double
        var isActive: Bool
        var createdAt: Date
        var tags: [String]
        var metadata: [String: String]
    }
    
    func testRoundTrip_InsertAndFetch() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blazedb")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        defer { try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta")) }
        
        let db = try BlazeDBClient(name: "test", fileURL: tempURL, password: "BlazeCollectionCompat123!")
        
        let original = TestRecord(
            id: UUID(),
            title: "Test Record",
            description: "This is a test description",
            count: 42,
            price: 99.99,
            isActive: true,
            createdAt: Date(),
            tags: ["tag1", "tag2", "tag3"],
            metadata: ["key1": "value1", "key2": "value2"]
        )
        
        // Convert to BlazeDataRecord and insert via BlazeDBClient
        let encoder = BlazeRecordEncoder()
        try original.encode(to: encoder)
        let record = encoder.getBlazeDataRecord()
        let id = try db.insert(record)
        XCTAssertEqual(id, original.id)
        
        // Fetch via BlazeDBClient
        let fetchedRecord = try db.fetch(id: original.id)
        XCTAssertNotNil(fetchedRecord, "Record should be fetchable after insert")
        
        // Convert back to TestRecord
        let decoder = BlazeRecordDecoder(storage: fetchedRecord!.storage)
        let fetched = try TestRecord(from: decoder)
        
        XCTAssertEqual(fetched.id, original.id, "ID should match")
        XCTAssertEqual(fetched.title, original.title, "Title should match")
        XCTAssertEqual(fetched.description, original.description, "Description should match")
        XCTAssertEqual(fetched.count, original.count, "Count should match")
        XCTAssertEqual(fetched.price, original.price, accuracy: 0.001, "Price should match")
        XCTAssertEqual(fetched.isActive, original.isActive, "isActive should match")
        XCTAssertEqual(fetched.tags, original.tags, "Tags should match")
        XCTAssertEqual(fetched.metadata, original.metadata, "Metadata should match")
    }
    
    func testRoundTrip_Update() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blazedb")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        defer { try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta")) }
        
        let db = try BlazeDBClient(name: "test", fileURL: tempURL, password: "BlazeCollectionCompat123!")
        
        let id = UUID()
        let original = TestRecord(
            id: id,
            title: "Original",
            description: "Original description",
            count: 10,
            price: 50.0,
            isActive: false,
            createdAt: Date(),
            tags: ["old"],
            metadata: ["old": "value"]
        )
        
        // Insert
        let encoder = BlazeRecordEncoder()
        try original.encode(to: encoder)
        let record = encoder.getBlazeDataRecord()
        try db.insert(record)
        
        // Update
        let updated = TestRecord(
            id: id,
            title: "Updated",
            description: "Updated description",
            count: 20,
            price: 100.0,
            isActive: true,
            createdAt: original.createdAt,
            tags: ["new"],
            metadata: ["new": "value"]
        )
        let updateEncoder = BlazeRecordEncoder()
        try updated.encode(to: updateEncoder)
        let updatedRecord = updateEncoder.getBlazeDataRecord()
        try db.update(id: id, with: updatedRecord)
        
        // Fetch
        let fetchedRecord = try db.fetch(id: id)
        XCTAssertNotNil(fetchedRecord, "Record should be fetchable after update")
        
        let decoder = BlazeRecordDecoder(storage: fetchedRecord!.storage)
        let fetched = try TestRecord(from: decoder)
        
        XCTAssertEqual(fetched.title, "Updated", "Title should be updated")
        XCTAssertEqual(fetched.count, 20, "Count should be updated")
        XCTAssertEqual(fetched.isActive, true, "isActive should be updated")
    }
    
    func testRoundTrip_InsertMany() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blazedb")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        defer { try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta")) }
        
        let db = try BlazeDBClient(name: "test", fileURL: tempURL, password: "BlazeCollectionCompat123!")
        
        let records = (0..<10).map { i in
            TestRecord(
                id: UUID(),
                title: "Record \(i)",
                description: "Description \(i)",
                count: i,
                price: Double(i) * 1.5,
                isActive: i % 2 == 0,
                createdAt: Date(timeIntervalSince1970: Double(i)),
                tags: ["tag\(i)"],
                metadata: ["key\(i)": "value\(i)"]
            )
        }
        
        // Convert and insert many via BlazeDBClient
        let encoder = BlazeRecordEncoder()
        let blazeRecords = try records.map { record -> BlazeDataRecord in
            let enc = BlazeRecordEncoder()
            try record.encode(to: enc)
            return enc.getBlazeDataRecord()
        }
        let ids = try db.insertMany(blazeRecords)
        XCTAssertEqual(ids.count, records.count)
        
        // Fetch all via BlazeDBClient
        let fetchedRecords = try db.fetchAll()
        XCTAssertEqual(fetchedRecords.count, records.count, "All records should be fetchable")
        
        // Verify each record
        for original in records {
            let fetchedRecord = try db.fetch(id: original.id)
            XCTAssertNotNil(fetchedRecord, "Record \(original.id) should be fetchable")
            
            let decoder = BlazeRecordDecoder(storage: fetchedRecord!.storage)
            let fetched = try TestRecord(from: decoder)
            XCTAssertEqual(fetched.title, original.title, "Title should match for \(original.id)")
            XCTAssertEqual(fetched.count, original.count, "Count should match for \(original.id)")
        }
    }
    
    func testCompatibility_BlazeDataRecordRoundTrip() throws {
        // Test that encoding/decoding produces identical BlazeDataRecord
        let original = TestRecord(
            id: UUID(),
            title: "Test",
            description: "Description",
            count: 42,
            price: 99.99,
            isActive: true,
            createdAt: Date(),
            tags: ["tag1"],
            metadata: ["key1": "value1"]
        )
        
        // Direct encoding
        let encoder = BlazeRecordEncoder()
        try original.encode(to: encoder)
        let directBlazeRecord = encoder.getBlazeDataRecord()
        
        // Encode to BlazeBinary
        let encoded = try BlazeBinaryEncoder.encodeOptimized(directBlazeRecord)
        
        // Decode from BlazeBinary
        // UPDATED: Use dual-codec validation
        try assertCodecsDecodeEqual(encoded)
        
        let decodedBlazeRecord = try BlazeBinaryDecoder.decodeARM(encoded)
        
        // Decode back to Record
        let decoder = BlazeRecordDecoder(storage: decodedBlazeRecord.storage)
        let decodedRecord = try TestRecord(from: decoder)
        
        // Verify round-trip
        XCTAssertEqual(decodedRecord.id, original.id)
        XCTAssertEqual(decodedRecord.title, original.title)
        XCTAssertEqual(decodedRecord.description, original.description)
        XCTAssertEqual(decodedRecord.count, original.count)
        XCTAssertEqual(decodedRecord.price, original.price, accuracy: 0.001)
        XCTAssertEqual(decodedRecord.isActive, original.isActive)
        XCTAssertEqual(decodedRecord.tags, original.tags)
        XCTAssertEqual(decodedRecord.metadata, original.metadata)
    }
    
    func testCompatibility_AllTypes() throws {
        struct AllTypesRecord: BlazeRecord {
            static var collection: String { "alltypes" }
            var id: UUID
            var createdAt: Date
            var stringField: String
            var intField: Int
            var doubleField: Double
            var boolField: Bool
            var dateField: Date
            var uuidField: UUID
            var dataField: Data
            var arrayField: [String]
            var dictField: [String: Int]
        }
        
        let original = AllTypesRecord(
            id: UUID(),
            createdAt: Date(),
            stringField: "test",
            intField: 42,
            doubleField: 3.14,
            boolField: true,
            dateField: Date(),
            uuidField: UUID(),
            dataField: Data([0x01, 0x02, 0x03]),
            arrayField: ["a", "b", "c"],
            dictField: ["key1": 1, "key2": 2]
        )
        
        // Encode
        let encoder = BlazeRecordEncoder()
        try original.encode(to: encoder)
        let blazeRecord = encoder.getBlazeDataRecord()
        let encoded = try BlazeBinaryEncoder.encodeOptimized(blazeRecord)
        
        // Decode
        // UPDATED: Use dual-codec validation
        try assertCodecsDecodeEqual(encoded)
        
        let decodedBlazeRecord = try BlazeBinaryDecoder.decodeARM(encoded)
        let decoder = BlazeRecordDecoder(storage: decodedBlazeRecord.storage)
        let decoded = try AllTypesRecord(from: decoder)
        
        // Verify all types
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.stringField, original.stringField)
        XCTAssertEqual(decoded.intField, original.intField)
        XCTAssertEqual(decoded.doubleField, original.doubleField, accuracy: 0.001)
        XCTAssertEqual(decoded.boolField, original.boolField)
        XCTAssertEqual(decoded.dateField.timeIntervalSince1970, original.dateField.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.uuidField, original.uuidField)
        XCTAssertEqual(decoded.dataField, original.dataField)
        XCTAssertEqual(decoded.arrayField, original.arrayField)
        XCTAssertEqual(decoded.dictField, original.dictField)
    }
}

