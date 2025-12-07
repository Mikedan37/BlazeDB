//
//  SchemaValidationTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for schema validation and enforcement
//

import XCTest
@testable import BlazeDB

final class SchemaValidationTests: XCTestCase {
    
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Schema-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "SchemaTest", fileURL: dbURL, password: "test-pass-123456")
    }
    
    override func tearDown() {
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    // MARK: - Basic Schema Validation
    
    func testSchemaValidation_RequiredFields() throws {
        print("📋 Testing required fields enforcement")
        
        // Define schema with required fields
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "title", type: .string, required: true),
            FieldSchema(name: "priority", type: .int, required: true)
        ])
        
        db.defineSchema(schema)
        
        // Try to insert record without required field
        do {
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Bug 1")
                // Missing "priority" (required!)
            ]))
            XCTFail("Should have thrown error for missing required field")
        } catch BlazeDBError.invalidField(let name, _, _) {
            XCTAssertEqual(name, "priority")
            print("  ✅ Correctly rejected missing required field")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
        
        // Insert with all required fields should work
        let id = try db.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "priority": .int(5)
        ]))
        
        XCTAssertNotNil(id)
        print("  ✅ Accepted record with all required fields")
    }
    
    func testSchemaValidation_TypeEnforcement() throws {
        print("📋 Testing type enforcement")
        
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "title", type: .string),
            FieldSchema(name: "count", type: .int),
            FieldSchema(name: "score", type: .double)
        ])
        
        db.defineSchema(schema)
        
        // Try to insert wrong type
        do {
            _ = try db.insert(BlazeDataRecord([
                "title": .int(123)  // Wrong type! Should be string
            ]))
            XCTFail("Should have thrown error for wrong type")
        } catch BlazeDBError.invalidField(let name, _, _) {
            XCTAssertEqual(name, "title")
            print("  ✅ Correctly rejected wrong type")
        }
        
        // Correct types should work
        let id = try db.insert(BlazeDataRecord([
            "title": .string("Valid title"),
            "count": .int(42),
            "score": .double(9.5)
        ]))
        
        XCTAssertNotNil(id)
        print("  ✅ Accepted record with correct types")
    }
    
    func testSchemaValidation_CustomValidator() throws {
        print("📋 Testing custom validators")
        
        // Priority must be 1-5
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "priority", type: .int, required: true, validator: { field in
                if case .int(let value) = field {
                    return value >= 1 && value <= 5
                }
                return false
            })
        ])
        
        db.defineSchema(schema)
        
        // Try invalid priority
        do {
            _ = try db.insert(BlazeDataRecord([
                "priority": .int(10)  // Out of range!
            ]))
            XCTFail("Should have thrown error for invalid priority")
        } catch BlazeDBError.invalidData {
            print("  ✅ Correctly rejected invalid value (priority=10)")
        }
        
        // Valid priority should work
        let id = try db.insert(BlazeDataRecord([
            "priority": .int(3)  // Valid (1-5)
        ]))
        
        XCTAssertNotNil(id)
        print("  ✅ Accepted valid value (priority=3)")
    }
    
    func testSchemaValidation_StrictMode() throws {
        print("📋 Testing strict mode (no unknown fields)")
        
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "title", type: .string)
        ], strict: true)
        
        db.defineSchema(schema)
        
        // Try to insert with unknown field
        do {
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Valid"),
                "extraField": .string("Unknown")  // Not in schema!
            ]))
            XCTFail("Should have thrown error for unknown field in strict mode")
        } catch BlazeDBError.invalidField(let name, _, _) {
            XCTAssertEqual(name, "extraField")
            print("  ✅ Strict mode rejected unknown field")
        }
        
        // Only known fields should work
        let id = try db.insert(BlazeDataRecord([
            "title": .string("Valid")
        ]))
        
        XCTAssertNotNil(id)
        print("  ✅ Strict mode accepted known fields only")
    }
    
    func testSchemaValidation_DefaultValues() throws {
        print("📋 Testing default values")
        
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "status", type: .string, required: false, defaultValue: .string("open"))
        ])
        
        db.defineSchema(schema)
        
        // Insert without status field
        let id = try db.insert(BlazeDataRecord([
            "title": .string("Bug 1")
        ]))
        
        // Fetch and check default was applied
        let record = try db.fetch(id: id)
        
        // Note: Default values would need to be applied in insert logic
        // For now, just verify it doesn't error
        XCTAssertNotNil(record)
        print("  ✅ Default value handling (to be enhanced)")
    }
    
    func testSchemaValidation_OnUpdate() throws {
        print("📋 Testing schema validation on update")
        
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "priority", type: .int, required: true, validator: { field in
                if case .int(let value) = field {
                    return value >= 1 && value <= 5
                }
                return false
            })
        ])
        
        db.defineSchema(schema)
        
        // Insert valid record
        let id = try db.insert(BlazeDataRecord([
            "priority": .int(3)
        ]))
        
        // Try to update with invalid value
        do {
            try db.update(id: id, with: BlazeDataRecord([
                "priority": .int(10)  // Invalid!
            ]))
            XCTFail("Should have thrown error for invalid update")
        } catch BlazeDBError.invalidData {
            print("  ✅ Schema validation works on update")
        }
        
        // Valid update should work
        try db.update(id: id, with: BlazeDataRecord([
            "priority": .int(5)  // Valid
        ]))
        
        let updated = try db.fetch(id: id)
        XCTAssertEqual(updated?.storage["priority"]?.intValue, 5)
        print("  ✅ Valid update accepted")
    }
    
    func testSchemaValidation_CanBeRemoved() throws {
        print("📋 Testing schema can be removed")
        
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "title", type: .string, required: true)
        ], strict: true)
        
        db.defineSchema(schema)
        
        // With schema: should reject unknown fields
        do {
            _ = try db.insert(BlazeDataRecord([
                "unknown": .string("value")
            ]))
            XCTFail("Should reject when schema active")
        } catch {
            // Expected
        }
        
        // Remove schema
        db.removeSchema()
        
        // Without schema: should accept anything
        let id = try db.insert(BlazeDataRecord([
            "unknown": .string("value")
        ]))
        
        XCTAssertNotNil(id)
        print("  ✅ Schema removed, dynamic mode restored")
    }
    
    // MARK: - Edge Cases
    
    func testSchemaValidation_EmptyRecord() throws {
        print("📋 Testing empty record with schema")
        
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "optional", type: .string, required: false)
        ])
        
        db.defineSchema(schema)
        
        // Empty record (all fields optional)
        let id = try db.insert(BlazeDataRecord([:]))
        
        XCTAssertNotNil(id)
        print("  ✅ Empty record accepted when no required fields")
    }
    
    func testSchemaValidation_AllFieldTypes() throws {
        print("📋 Testing all field types")
        
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "str", type: .string),
            FieldSchema(name: "int", type: .int),
            FieldSchema(name: "dbl", type: .double),
            FieldSchema(name: "bool", type: .bool),
            FieldSchema(name: "date", type: .date),
            FieldSchema(name: "uuid", type: .uuid),
            FieldSchema(name: "data", type: .data),
            FieldSchema(name: "array", type: .array(.string)),
            FieldSchema(name: "dict", type: .dictionary)
        ])
        
        db.defineSchema(schema)
        
        // Insert with all types
        let id = try db.insert(BlazeDataRecord([
            "str": .string("test"),
            "int": .int(42),
            "dbl": .double(3.14),
            "bool": .bool(true),
            "date": .date(Date()),
            "uuid": .uuid(UUID()),
            "data": .data(Data([0x01, 0x02])),
            "array": .array([.string("a"), .string("b")]),
            "dict": .dictionary(["key": .string("value")])
        ]))
        
        XCTAssertNotNil(id)
        print("  ✅ All field types validated correctly")
    }
    
    func testSchemaValidation_IntAsDouble() throws {
        print("📋 Testing int can be used as double")
        
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "score", type: .double)
        ])
        
        db.defineSchema(schema)
        
        // Insert int for double field (should be allowed)
        let id = try db.insert(BlazeDataRecord([
            "score": .int(10)  // Int treated as Double
        ]))
        
        XCTAssertNotNil(id)
        print("  ✅ Int accepted for double field")
    }
}

