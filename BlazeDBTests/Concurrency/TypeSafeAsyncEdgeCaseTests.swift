//
//  TypeSafeAsyncEdgeCaseTests.swift
//  BlazeDBTests
//
//  Additional async type-safe operation tests for 100% coverage.
//  Tests async type-safe CRUD, error paths, and edge cases.
//
//  Created: Final 1% Coverage Push
//

import XCTest
@testable import BlazeDBCore

// MARK: - Test Models

struct AsyncTestModel: BlazeStorable {
    var id: UUID
    var name: String
    var count: Int
    
    init(id: UUID, name: String, count: Int) {
        self.id = id
        self.name = name
        self.count = count
    }
}

final class TypeSafeAsyncEdgeCaseTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        // Force cleanup from previous test
        if let existingDB = db {
            try? await existingDB.persist()
        }
        db = nil
        
        // Clear cached encryption key
        BlazeDBClient.clearCachedKey()
        
        // Longer delay to ensure previous database is fully closed
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Create unique database file with timestamp + thread ID
        let testID = "\(UUID().uuidString)-\(Thread.current.hash)-\(Date().timeIntervalSince1970)"
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypeAsync-\(testID).blazedb")
        
        // Clean up leftover files from this exact path
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
        
        db = try BlazeDBClient(name: "type_async_test_\(testID)", fileURL: tempURL, password: "test-password-123")
        
        // CRITICAL: Verify database starts empty
        let startCount = try await db.count()
        if startCount != 0 {
            print("⚠️ CRITICAL: TypeAsync test database not empty! Has \(startCount) records. Force wiping...")
            _ = try? await db.deleteMany(where: { _ in true })
            try? await db.persist()
        }
    }
    
    override func tearDown() async throws {
        // Force persistence before cleanup
        try? await db?.persist()
        db = nil
        
        // LONGER delay for file handles
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Aggressive cleanup (try 3 times)
        if let tempURL = tempURL {
            for _ in 0..<3 {
                try? FileManager.default.removeItem(at: tempURL)
                try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
                try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
                try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
                
                if !FileManager.default.fileExists(atPath: tempURL.path) {
                    break
                }
                try? await Task.sleep(nanoseconds: 20_000_000) // 20ms between retries
            }
        }
        
        BlazeDBClient.clearCachedKey()
    }
    
    // MARK: - Async Type-Safe CRUD
    
    /// Test async insert with type-safe model
    func testAsyncInsertTypeSafe() async throws {
        print("⚡ Testing async insert type-safe...")
        
        let model = AsyncTestModel(id: UUID(), name: "Test", count: 42)
        
        let id = try await db.insert(model)
        
        XCTAssertEqual(id, model.id)
        
        let fetched = try await db.fetch(AsyncTestModel.self, id: id)
        XCTAssertEqual(fetched?.name, "Test")
        XCTAssertEqual(fetched?.count, 42)
        
        print("✅ Async insert type-safe works")
    }
    
    /// Test async fetch non-existent type-safe
    func testAsyncFetchNonExistentTypeSafe() async throws {
        print("⚡ Testing async fetch non-existent type-safe...")
        
        let randomID = UUID()
        let fetched = try await db.fetch(AsyncTestModel.self, id: randomID)
        
        XCTAssertNil(fetched, "Non-existent record should return nil")
        
        print("✅ Async fetch non-existent returns nil")
    }
    
    /// Test async fetchAll type-safe
    func testAsyncFetchAllTypeSafe() async throws {
        print("⚡ Testing async fetchAll type-safe...")
        
        // Insert multiple
        for i in 0..<5 {
            let model = AsyncTestModel(id: UUID(), name: "Model \(i)", count: i * 10)
            _ = try await db.insert(model)
        }
        
        // Fetch all as type
        let all = try await db.fetchAll(AsyncTestModel.self)
        
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(all[0].count % 10, 0)
        
        print("✅ Async fetchAll type-safe works")
    }
    
    /// Test async update type-safe
    func testAsyncUpdateTypeSafe() async throws {
        print("⚡ Testing async update type-safe...")
        
        var model = AsyncTestModel(id: UUID(), name: "Original", count: 1)
        _ = try await db.insert(model)
        
        // Update
        model.name = "Updated"
        model.count = 2
        try await db.update(model)
        
        // Verify
        let fetched = try await db.fetch(AsyncTestModel.self, id: model.id)
        XCTAssertEqual(fetched?.name, "Updated")
        XCTAssertEqual(fetched?.count, 2)
        
        print("✅ Async update type-safe works")
    }
    
    /// Test async upsert type-safe
    func testAsyncUpsertTypeSafe() async throws {
        print("⚡ Testing async upsert type-safe...")
        
        let model = AsyncTestModel(id: UUID(), name: "Upsert", count: 100)
        
        // First upsert (insert)
        let wasInsert = try await db.upsert(model)
        XCTAssertTrue(wasInsert, "First upsert should be insert")
        
        // Second upsert (update)
        let wasInsert2 = try await db.upsert(model)
        XCTAssertFalse(wasInsert2, "Second upsert should be update")
        
        print("✅ Async upsert type-safe works")
    }
    
    /// Test async insertMany type-safe
    func testAsyncInsertManyTypeSafe() async throws {
        print("⚡ Testing async insertMany type-safe...")
        
        let models = (0..<10).map { i in
            AsyncTestModel(id: UUID(), name: "Batch \(i)", count: i)
        }
        
        let ids = try await db.insertMany(models)
        
        XCTAssertEqual(ids.count, 10)
        
        // Verify all inserted
        for (index, id) in ids.enumerated() {
            let fetched = try await db.fetch(AsyncTestModel.self, id: id)
            XCTAssertEqual(fetched?.name, "Batch \(index)")
        }
        
        print("✅ Async insertMany type-safe works")
    }
}

