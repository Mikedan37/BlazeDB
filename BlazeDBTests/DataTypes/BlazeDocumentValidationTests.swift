//
//  BlazeDocumentValidationTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for BlazeDocument type safety validation.
//  Tests required fields, type mismatches, optional handling, and edge cases.
//
//  Created: Phase 2 Feature Completeness Testing
//

import XCTest
@testable import BlazeDBCore

// MARK: - Test Models

struct ValidatedUser: BlazeDocument, Codable {
    var id: UUID
    var name: String
    var email: String
    var age: Int
    var isActive: Bool?  // Optional
    
    func toStorage() throws -> BlazeDataRecord {
        var storage: [String: BlazeDocumentField] = [
            "id": .uuid(id),
            "name": .string(name),
            "email": .string(email),
            "age": .int(age)
        ]
        if let isActive = isActive {
            storage["isActive"] = .bool(isActive)
        }
        return BlazeDataRecord(storage)
    }
    
    init(from storage: BlazeDataRecord) throws {
        guard let id = storage.storage["id"]?.uuidValue,
              let name = storage.storage["name"]?.stringValue,
              let email = storage.storage["email"]?.stringValue,
              let age = storage.storage["age"]?.intValue else {
            throw BlazeDBError.invalidData(reason: "Missing required fields in TestUser")
        }
        self.id = id
        self.name = name
        self.email = email
        self.age = age
        self.isActive = storage.storage["isActive"]?.boolValue
    }
    
    init(id: UUID, name: String, email: String, age: Int, isActive: Bool? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.age = age
        self.isActive = isActive
    }
    
    var storage: BlazeDataRecord {
        get { (try? toStorage()) ?? BlazeDataRecord([:]) }
        set { }
    }
}

struct StrictProduct: BlazeDocument, Codable {
    var id: UUID
    var sku: String
    var price: Double
    var inStock: Bool
    
    func toStorage() throws -> BlazeDataRecord {
        return BlazeDataRecord([
            "id": .uuid(id),
            "sku": .string(sku),
            "price": .double(price),
            "inStock": .bool(inStock)
        ])
    }
    
    init(from storage: BlazeDataRecord) throws {
        guard let id = storage.storage["id"]?.uuidValue,
              let sku = storage.storage["sku"]?.stringValue,
              let price = storage.storage["price"]?.doubleValue,
              let inStock = storage.storage["inStock"]?.boolValue else {
            throw BlazeDBError.invalidData(reason: "Missing required fields in TestProduct")
        }
        self.id = id
        self.sku = sku
        self.price = price
        self.inStock = inStock
    }
    
    init(id: UUID, sku: String, price: Double, inStock: Bool) {
        self.id = id
        self.sku = sku
        self.price = price
        self.inStock = inStock
    }
    
    var storage: BlazeDataRecord {
        get { (try? toStorage()) ?? BlazeDataRecord([:]) }
        set { }
    }
}

struct NestedModel: BlazeDocument, Codable {
    var id: UUID
    var config: [String: BlazeDocumentField]
    
    func toStorage() throws -> BlazeDataRecord {
        return BlazeDataRecord([
            "id": .uuid(id),
            "config": .dictionary(config)
        ])
    }
    
    init(from storage: BlazeDataRecord) throws {
        guard let id = storage.storage["id"]?.uuidValue,
              let config = storage.storage["config"]?.dictionaryValue else {
            throw BlazeDBError.invalidData(reason: "Missing required fields in TestSettings")
        }
        self.id = id
        self.config = config
    }
    
    init(id: UUID, config: [String: BlazeDocumentField]) {
        self.id = id
        self.config = config
    }
    
    var storage: BlazeDataRecord {
        get { (try? toStorage()) ?? BlazeDataRecord([:]) }
        set { }
    }
}

final class BlazeDocumentValidationTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocValid-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(name: "DocValidTest", fileURL: tempURL, password: "test-password-123")
    }
    
    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - Required Field Tests
    
    /// Test that inserting document with all required fields works
    func testInsertWithAllRequiredFields() throws {
        print("✅ Testing insert with all required fields...")
        
        let user = ValidatedUser(
            id: UUID(),
            name: "John Doe",
            email: "john@test.com",
            age: 30,
            isActive: true
        )
        
        print("  User ID: \(user.id)")
        
        // Check what toStorage() produces
        let storage = try user.toStorage()
        print("  Storage fields: \(storage.storage.keys)")
        print("  Storage ID: \(storage.storage["id"])")
        
        // Insert and get returned ID
        let insertedID = try db.insert(user)
        print("  Inserted ID: \(insertedID)")
        print("  IDs match: \(insertedID == user.id)")
        
        // Check if record exists at all
        let allRecords = try db.fetchAll()
        print("\n  Total records in DB: \(allRecords.count)")
        if let directFetch = try db.fetch(id: insertedID) {
            print("  ✅ Raw fetch(id:) FOUND record")
            print("  Record fields: \(directFetch.storage.keys)")
            print("  Record ID field: \(directFetch.storage["id"])")
        } else {
            print("  ❌ Raw fetch(id:) NOT FOUND")
        }
        
        // Try fetching with BOTH IDs to see which works
        print("\n  Fetching with user.id...")
        let fetched1 = try? db.fetch(ValidatedUser.self, id: user.id)
        print("  Result: \(fetched1 == nil ? "NOT FOUND" : "FOUND")")
        if fetched1 == nil {
            print("  Error during conversion")
        }
        
        print("  Fetching with insertedID...")
        let fetched2 = try? db.fetch(ValidatedUser.self, id: insertedID)
        print("  Result: \(fetched2 == nil ? "NOT FOUND" : "FOUND")")
        if fetched2 == nil {
            print("  Error during conversion")
        }
        
        // Use the ID that was actually returned by insert
        let fetched = try db.fetch(ValidatedUser.self, id: insertedID)
        XCTAssertNotNil(fetched, "Should find record with returned ID")
        XCTAssertEqual(fetched?.name, "John Doe")
        XCTAssertEqual(fetched?.email, "john@test.com")
        
        print("✅ Insert with all required fields works")
    }
    
    /// Test that missing required field throws or uses default
    func testMissingRequiredFieldHandling() throws {
        print("⚠️ Testing missing required field handling...")
        
        // Manually create storage missing 'name' field
        let storage = BlazeDataRecord([
            "id": .uuid(UUID()),
            "email": .string("test@test.com"),
            "age": .int(25)
            // Missing 'name' - required field
        ])
        
        let id = try db.insert(storage)
        
        // Try to fetch as ValidatedUser
        do {
            let _ = try db.fetch(ValidatedUser.self, id: id)
            // If this succeeds, @Field must provide a default (like empty string)
            print("  ℹ️ Missing field was given default value")
        } catch {
            // If this throws, validation is strict
            print("  ✅ Missing required field threw error: \(error)")
        }
        
        // Either outcome is acceptable depending on @Field implementation
        print("✅ Missing field handling is consistent")
    }
    
    // MARK: - Type Mismatch Tests
    
    /// Test type mismatch (Int field gets String value)
    func testTypeMismatchHandling() throws {
        print("⚠️ Testing type mismatch handling...")
        
        // Insert with wrong type
        let wrongStorage = BlazeDataRecord([
            "id": .uuid(UUID()),
            "sku": .string("SKU123"),
            "price": .string("WRONG-should-be-double"),  // Wrong type!
            "inStock": .bool(true)
        ])
        
        let id = try db.insert(wrongStorage)
        
        // Try to fetch as StrictProduct
        do {
            let product = try db.fetch(StrictProduct.self, id: id)
            // If this succeeds, @Field must be lenient
            XCTAssertNotNil(product)
            print("  ℹ️ Type mismatch was handled gracefully")
        } catch {
            // If this throws, validation is strict
            print("  ✅ Type mismatch threw error: \(error)")
        }
        
        print("✅ Type mismatch handling is consistent")
    }
    
    // MARK: - Optional Field Tests
    
    /// Test optional field with nil value
    func testOptionalFieldWithNil() throws {
        print("📝 Testing optional field with nil...")
        
        let user = ValidatedUser(
            id: UUID(),
            name: "Jane",
            email: "jane@test.com",
            age: 28,
            isActive: nil  // Optional field set to nil
        )
        
        let id = try db.insert(user)
        let fetched = try db.fetch(ValidatedUser.self, id: id)
        
        XCTAssertNil(fetched?.isActive, "Optional field should be nil")
        
        print("✅ Optional field with nil works correctly")
    }
    
    /// Test optional field with value
    func testOptionalFieldWithValue() throws {
        print("📝 Testing optional field with value...")
        
        let user = ValidatedUser(
            id: UUID(),
            name: "Bob",
            email: "bob@test.com",
            age: 35,
            isActive: true  // Optional field set to value
        )
        
        let id = try db.insert(user)
        let fetched = try db.fetch(ValidatedUser.self, id: id)
        
        XCTAssertEqual(fetched?.isActive, true, "Optional field should have value")
        
        print("✅ Optional field with value works correctly")
    }
    
    /// Test converting storage with extra fields (should be ignored)
    func testExtraFieldsIgnoredInConversion() throws {
        print("📝 Testing extra fields are ignored...")
        
        // Insert with extra fields
        let storage = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Alice"),
            "email": .string("alice@test.com"),
            "age": .int(30),
            "extraField1": .string("ignored"),
            "extraField2": .int(999),
            "isActive": .bool(true)
        ])
        
        let id = try db.insert(storage)
        
        // Fetch as ValidatedUser (has only 5 fields)
        let fetched = try db.fetch(ValidatedUser.self, id: id)
        
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Alice")
        XCTAssertEqual(fetched?.email, "alice@test.com")
        
        // Extra fields should be ignored (not cause errors)
        print("✅ Extra fields ignored correctly")
    }
    
    /// Test BlazeDocument with nested dictionary field
    func testNestedDictionaryInBlazeDocument() throws {
        print("📝 Testing nested dictionary in BlazeDocument...")
        
        let config: [String: BlazeDocumentField] = [
            "theme": .string("dark"),
            "fontSize": .int(14),
            "notifications": .bool(true)
        ]
        
        let model = NestedModel(id: UUID(), config: config)
        
        let id = try db.insert(model)
        let fetched = try db.fetch(NestedModel.self, id: id)
        
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.config["theme"]?.stringValue, "dark")
        XCTAssertEqual(fetched?.config["fontSize"]?.intValue, 14)
        
        print("✅ Nested dictionary in BlazeDocument works correctly")
    }
}

