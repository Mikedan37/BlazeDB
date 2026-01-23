//
//  ArrayDictionaryEdgeTests.swift
//  BlazeDBTests
//
//  Comprehensive edge case tests for Array and Dictionary data types.
//  Tests nested structures, empty values, large arrays, Unicode keys, and complex queries.
//
//  Created: Phase 2 Feature Completeness Testing
//

import XCTest
@testable import BlazeDBCore

final class ArrayDictionaryEdgeTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArrayDict-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(name: "ArrayDictTest", fileURL: tempURL, password: "test-password-123")
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        super.tearDown()
    }
    
    // MARK: - Nested Array Tests
    
    /// Test nested arrays (array of arrays)
    func testNestedArrays() throws {
        print("📦 Testing nested arrays...")
        
        let nestedArray: BlazeDocumentField = .array([
            .array([.int(1), .int(2), .int(3)]),
            .array([.int(4), .int(5), .int(6)]),
            .array([.int(7), .int(8), .int(9)])
        ])
        
        let id = try db.insert(BlazeDataRecord([
            "matrix": nestedArray,
            "name": .string("2D Array")
        ]))
        
        print("  Inserted record with nested arrays")
        
        // Fetch and verify structure preserved
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
        
        if case let .array(outerArray)? = fetched?.storage["matrix"] {
            XCTAssertEqual(outerArray.count, 3, "Should have 3 inner arrays")
            
            if case let .array(firstInner) = outerArray[0] {
                XCTAssertEqual(firstInner.count, 3)
                XCTAssertEqual(firstInner[0], .int(1))
            } else {
                XCTFail("First element should be array")
            }
        } else {
            XCTFail("Should have nested array")
        }
        
        print("✅ Nested arrays work correctly")
    }
    
    /// Test deeply nested dictionaries
    func testDeepNestedDictionaries() throws {
        print("📦 Testing deeply nested dictionaries...")
        
        let deepDict: BlazeDocumentField = .dictionary([
            "level1": .dictionary([
                "level2": .dictionary([
                    "level3": .dictionary([
                        "level4": .string("deep value"),
                        "number": .int(42)
                    ])
                ])
            ])
        ])
        
        let id = try db.insert(BlazeDataRecord([
            "structure": deepDict,
            "type": .string("nested")
        ]))
        
        print("  Inserted record with 4-level nested dictionary")
        
        // Fetch and verify
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
        
        // Navigate to deep value
        if case let .dictionary(l1)? = fetched?.storage["structure"],
           case let .dictionary(l2) = l1["level1"],
           case let .dictionary(l3) = l2["level2"],
           case let .dictionary(l4) = l3["level3"],
           case let .string(value) = l4["level4"] {
            XCTAssertEqual(value, "deep value", "Should preserve deep nested value")
        } else {
            XCTFail("Deep dictionary structure not preserved")
        }
        
        print("✅ Deep nested dictionaries work correctly")
    }
    
    /// Test mixed array/dictionary structures
    func testMixedArrayDictionaryStructures() throws {
        print("📦 Testing mixed array/dictionary structures...")
        
        let mixedStructure: BlazeDocumentField = .array([
            .dictionary(["name": .string("Alice"), "age": .int(30)]),
            .dictionary(["name": .string("Bob"), "age": .int(25)]),
            .array([.string("tag1"), .string("tag2"), .string("tag3")])
        ])
        
        let id = try db.insert(BlazeDataRecord([
            "data": mixedStructure,
            "type": .string("mixed")
        ]))
        
        print("  Inserted mixed array/dictionary structure")
        
        // Fetch and verify
        let fetched = try db.fetch(id: id)
        
        if case let .array(items)? = fetched?.storage["data"] {
            XCTAssertEqual(items.count, 3)
            
            // First two should be dictionaries
            if case .dictionary = items[0] { } else { XCTFail("First should be dict") }
            if case .dictionary = items[1] { } else { XCTFail("Second should be dict") }
            
            // Third should be array
            if case let .array(tags) = items[2] {
                XCTAssertEqual(tags.count, 3)
            } else {
                XCTFail("Third should be array")
            }
        } else {
            XCTFail("Should have mixed structure")
        }
        
        print("✅ Mixed array/dictionary structures work correctly")
    }
    
    // MARK: - Empty Collection Tests
    
    /// Test empty arrays in queries
    func testEmptyArrayInQuery() throws {
        print("📦 Testing empty arrays in queries...")
        
        let emptyArray: BlazeDocumentField = .array([])
        
        _ = try db.insert(BlazeDataRecord([
            "name": .string("EmptyList"),
            "items": emptyArray
        ]))
        _ = try db.insert(BlazeDataRecord([
            "name": .string("HasItems"),
            "items": .array([.int(1), .int(2)])
        ]))
        
        // Query for empty arrays
        let results = try db.query()
            .where("items", equals: emptyArray)
            .execute()
            .records
        
        XCTAssertEqual(results.count, 1, "Should find empty array record")
        if !results.isEmpty {
            XCTAssertEqual(results[0].storage["name"]?.stringValue, "EmptyList")
        }
        
        print("✅ Empty array queries work correctly")
    }
    
    /// Test empty dictionaries
    func testEmptyDictionaryHandling() throws {
        print("📦 Testing empty dictionaries...")
        
        let emptyDict: BlazeDocumentField = .dictionary([:])
        
        let id = try db.insert(BlazeDataRecord([
            "name": .string("Empty"),
            "metadata": emptyDict
        ]))
        
        let fetched = try db.fetch(id: id)
        
        if case let .dictionary(dict)? = fetched?.storage["metadata"] {
            XCTAssertTrue(dict.isEmpty, "Dictionary should be empty")
        } else {
            XCTFail("Should have empty dictionary")
        }
        
        print("✅ Empty dictionaries work correctly")
    }
    
    // MARK: - Large Collection Tests
    
    /// Test large arrays (400 elements - within page size limit)
    func testLargeArrayPerformance() throws {
        // ⚠️ NOTE: Single records are limited to page size (4096 bytes)
        // 1000 integers = ~9000 bytes (exceeds page limit!)
        // 400 integers = ~3600 bytes (fits comfortably within 4059 byte limit)
        
        print("📦 Testing large arrays (400 elements)...")
        
        // Create array with 400 elements (fits within page size limit)
        let largeArray = BlazeDocumentField.array(
            (0..<400).map { .int($0) }
        )
        
        let startTime = Date()
        let id = try db.insert(BlazeDataRecord([
            "name": .string("LargeArray"),
            "data": largeArray
        ]))
        let insertDuration = Date().timeIntervalSince(startTime)
        
        print("  Inserted 400-element array in \(String(format: "%.3f", insertDuration))s")
        
        // Fetch and verify
        let fetchStart = Date()
        let fetched = try db.fetch(id: id)
        let fetchDuration = Date().timeIntervalSince(fetchStart)
        
        print("  Fetched 400-element array in \(String(format: "%.3f", fetchDuration))s")
        
        if case let .array(items)? = fetched?.storage["data"] {
            XCTAssertEqual(items.count, 400, "Should have all 400 elements")
            XCTAssertEqual(items[0], .int(0))
            XCTAssertEqual(items[399], .int(399))
        } else {
            XCTFail("Should have large array")
        }
        
        // Performance check
        XCTAssertLessThan(insertDuration, 0.5, "Large array insert should be fast")
        XCTAssertLessThan(fetchDuration, 0.5, "Large array fetch should be fast")
        
        print("✅ Large arrays work efficiently")
    }
    
    /// Test dictionary with many keys (100+)
    func testLargeDictionaryWithManyKeys() throws {
        print("📦 Testing dictionary with 100+ keys...")
        
        // Create dictionary with 100 keys
        var largeDict: [String: BlazeDocumentField] = [:]
        for i in 0..<100 {
            largeDict["key\(i)"] = .int(i * 10)
        }
        
        let id = try db.insert(BlazeDataRecord([
            "name": .string("LargeDict"),
            "data": .dictionary(largeDict)
        ]))
        
        print("  Inserted dictionary with 100 keys")
        
        // Fetch and verify
        let fetched = try db.fetch(id: id)
        
        if case let .dictionary(dict)? = fetched?.storage["data"] {
            XCTAssertEqual(dict.count, 100, "Should have all 100 keys")
            XCTAssertEqual(dict["key0"], .int(0))
            XCTAssertEqual(dict["key99"], .int(990))
        } else {
            XCTFail("Should have large dictionary")
        }
        
        print("✅ Large dictionaries work correctly")
    }
    
    // MARK: - Unicode and Special Characters
    
    /// Test dictionary with Unicode keys
    func testUnicodeKeysInDictionaries() throws {
        print("📦 Testing Unicode keys in dictionaries...")
        
        let unicodeDict: BlazeDocumentField = .dictionary([
            "名前": .string("Tanaka"),  // Japanese
            "возраст": .int(25),        // Russian
            "🔥emoji": .bool(true),      // Emoji
            "key with spaces": .string("value"),
            "key\nwith\nnewlines": .int(42)
        ])
        
        let id = try db.insert(BlazeDataRecord([
            "data": unicodeDict
        ]))
        
        print("  Inserted dictionary with Unicode keys")
        
        // Fetch and verify all keys preserved
        let fetched = try db.fetch(id: id)
        
        if case let .dictionary(dict)? = fetched?.storage["data"] {
            XCTAssertEqual(dict.count, 5, "Should have all 5 keys")
            XCTAssertEqual(dict["名前"]?.stringValue, "Tanaka")
            XCTAssertEqual(dict["возраст"]?.intValue, 25)
            XCTAssertEqual(dict["🔥emoji"]?.boolValue, true)
            XCTAssertEqual(dict["key with spaces"]?.stringValue, "value")
            XCTAssertEqual(dict["key\nwith\nnewlines"]?.intValue, 42)
        } else {
            XCTFail("Should have Unicode key dictionary")
        }
        
        print("✅ Unicode keys in dictionaries work correctly")
    }
    
    /// Test array with various Unicode strings
    func testArrayWithUnicodeStrings() throws {
        print("📦 Testing arrays with Unicode strings...")
        
        let unicodeArray: BlazeDocumentField = .array([
            .string("Hello 世界"),
            .string("Привет мир"),
            .string("🔥🚀💎"),
            .string("العربية"),
            .string("עברית")
        ])
        
        let id = try db.insert(BlazeDataRecord([
            "languages": unicodeArray
        ]))
        
        let fetched = try db.fetch(id: id)
        
        if case let .array(items)? = fetched?.storage["languages"] {
            XCTAssertEqual(items.count, 5)
            XCTAssertEqual(items[0].stringValue, "Hello 世界")
            XCTAssertEqual(items[2].stringValue, "🔥🚀💎")
        } else {
            XCTFail("Should have Unicode array")
        }
        
        print("✅ Unicode in arrays works correctly")
    }
    
    // MARK: - Compound Index with Complex Types
    
    /// Test that arrays/dictionaries fallback correctly in compound indexes
    func testArrayDictionaryInCompoundIndexFallback() throws {
        print("📦 Testing array/dict fallback in compound indexes...")
        
        let collection = db.collection
        
        // Create compound index that includes array field
        try collection.createIndex(on: ["status", "tags"])
        
        _ = try db.insert(BlazeDataRecord([
            "status": .string("active"),
            "tags": .array([.string("urgent"), .string("bug")]),  // Should fallback to ""
            "title": .string("Test")
        ]))
        
        print("  Inserted record with array in compound index field")
        
        // Fetch by compound index (array should have been normalized to "")
        let results = try collection.fetch(byIndexedFields: ["status", "tags"], 
                                          values: ["active", ""])
        
        // Should find the record (array was normalized to "")
        XCTAssertGreaterThanOrEqual(results.count, 1, "Should find record with array fallback")
        
        print("✅ Array/dictionary fallback in compound indexes works")
    }
}

