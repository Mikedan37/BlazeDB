//
//  StateModelTests.swift
//  BlazeDBTests
//
//  Model-based testing: Compare BlazeDB behavior to a pure Swift Dictionary
//  as "ground truth" to detect divergence, missing rows, inconsistent values,
//  and index mismatches.
//
//  Created: 2025-01-XX
//

import XCTest
@testable import BlazeDB

final class StateModelTests: XCTestCase {
    
    var db: BlazeDBClient!
    var tempURL: URL!
    
    // Ground truth: Pure Swift Dictionary
    var groundTruth: [UUID: [String: BlazeDocumentField]] = [:]
    var groundTruthLock = NSLock()
    
    override func setUp() {
        super.setUp()
        
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StateModel-\(testID).blazedb")
        
        // Clean up any leftover files
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            if !FileManager.default.fileExists(atPath: tempURL.path) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        do {
            db = try BlazeDBClient(name: "state_model_test_\(testID)", fileURL: tempURL, password: "StateModelTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
        groundTruth = [:]
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Ground Truth Operations
    
    private func modelInsert(_ record: BlazeDataRecord) -> UUID {
        let id = record.storage["id"]?.uuidValue ?? UUID()
        groundTruthLock.lock()
        defer { groundTruthLock.unlock() }
        groundTruth[id] = record.storage
        return id
    }
    
    private func modelUpdate(id: UUID, with record: BlazeDataRecord) {
        groundTruthLock.lock()
        defer { groundTruthLock.unlock() }
        if var existing = groundTruth[id] {
            for (key, value) in record.storage {
                existing[key] = value
            }
            groundTruth[id] = existing
        }
    }
    
    private func modelDelete(id: UUID) {
        groundTruthLock.lock()
        defer { groundTruthLock.unlock() }
        groundTruth.removeValue(forKey: id)
    }
    
    private func modelFetch(id: UUID) -> [String: BlazeDocumentField]? {
        groundTruthLock.lock()
        defer { groundTruthLock.unlock() }
        return groundTruth[id]
    }
    
    private func modelFetchAll() -> [UUID: [String: BlazeDocumentField]] {
        groundTruthLock.lock()
        defer { groundTruthLock.unlock() }
        return groundTruth
    }
    
    private func modelQuery(where field: String, equals value: BlazeDocumentField) -> [UUID] {
        groundTruthLock.lock()
        defer { groundTruthLock.unlock() }
        return groundTruth.compactMap { id, record in
            record[field] == value ? id : nil
        }
    }
    
    // MARK: - Validation
    
    private func validateConsistency() throws {
        // Fetch all from BlazeDB
        let blazedbRecords = try db.fetchAll()
        let blazedbDict = Dictionary(uniqueKeysWithValues: blazedbRecords.map { record in
            (record.storage["id"]?.uuidValue ?? UUID(), record.storage)
        })
        
        // Compare to ground truth
        groundTruthLock.lock()
        let truth = groundTruth
        groundTruthLock.unlock()
        
        // Check for missing rows in BlazeDB
        for (id, truthRecord) in truth {
            guard let blazedbRecord = blazedbDict[id] else {
                XCTFail("❌ Missing row in BlazeDB: \(id)")
                continue
            }
            
            // Check for inconsistent values
            for (key, truthValue) in truthRecord {
                guard let blazedbValue = blazedbRecord[key] else {
                    XCTFail("❌ Missing field '\(key)' in BlazeDB record \(id)")
                    continue
                }
                
                if !valuesEqual(truthValue, blazedbValue) {
                    XCTFail("❌ Inconsistent value for field '\(key)' in record \(id): expected \(truthValue), got \(blazedbValue)")
                }
            }
        }
        
        // Check for extra rows in BlazeDB (shouldn't happen, but verify)
        for (id, _) in blazedbDict {
            if truth[id] == nil {
                XCTFail("❌ Extra row in BlazeDB (not in ground truth): \(id)")
            }
        }
    }
    
    private func valuesEqual(_ a: BlazeDocumentField, _ b: BlazeDocumentField) -> Bool {
        switch (a, b) {
        case (.string(let a), .string(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return abs(a - b) < 0.0001
        case (.bool(let a), .bool(let b)): return a == b
        case (.uuid(let a), .uuid(let b)): return a == b
        case (.date(let a), .date(let b)): return abs(a.timeIntervalSince(b)) < 0.001
        case (.data(let a), .data(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.dictionary(let a), .dictionary(let b)): return a == b
        default: return false
        }
    }
    
    // MARK: - Tests
    
    func testModelBased_InsertAndFetch() throws {
        print("\n🎯 MODEL-BASED: Insert and Fetch (100 operations)")
        
        for i in 0..<100 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "name": .string("Record \(i)"),
                "value": .double(Double(i) * 1.5)
            ])
            
            // Insert into both
            let truthID = modelInsert(record)
            let blazedbID = try db.insert(record)
            
            XCTAssertEqual(truthID, blazedbID, "IDs should match")
            
            // Fetch and compare
            let truthRecord = modelFetch(id: truthID)
            let blazedbRecord = try db.fetch(id: blazedbID)
            
            XCTAssertNotNil(truthRecord)
            XCTAssertNotNil(blazedbRecord)
            
            if let truth = truthRecord, let blaze = blazedbRecord {
                for (key, truthValue) in truth {
                    guard let blazeValue = blaze.storage[key] else {
                        XCTFail("Missing field '\(key)' in BlazeDB")
                        continue
                    }
                    XCTAssertTrue(valuesEqual(truthValue, blazeValue), "Field '\(key)' should match")
                }
            }
            
            if i % 20 == 0 {
                print("  Tested \(i) operations...")
            }
        }
        
        // Final consistency check
        try validateConsistency()
        print("  ✅ All 100 operations consistent!")
    }
    
    func testModelBased_UpdateOperations() throws {
        print("\n🎯 MODEL-BASED: Update Operations (50 operations)")
        
        // Insert initial records
        var ids: [UUID] = []
        for i in 0..<50 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "status": .string("pending")
            ])
            let id = try db.insert(record)
            modelInsert(record)
            ids.append(id)
        }
        
        // Update records
        for (i, id) in ids.enumerated() {
            let update = BlazeDataRecord([
                "status": .string("done"),
                "updated": .int(i * 2)
            ])
            
            try db.update(id: id, with: update)
            modelUpdate(id: id, with: update)
            
            // Verify immediately
            let truthRecord = modelFetch(id: id)
            let blazedbRecord = try db.fetch(id: id)
            
            XCTAssertNotNil(truthRecord)
            XCTAssertNotNil(blazedbRecord)
            
            if let truth = truthRecord, let blaze = blazedbRecord {
                XCTAssertEqual(truth["status"], blaze.storage["status"], "Status should match after update")
            }
        }
        
        // Final consistency check
        try validateConsistency()
        print("  ✅ All 50 updates consistent!")
    }
    
    func testModelBased_DeleteOperations() throws {
        print("\n🎯 MODEL-BASED: Delete Operations (30 operations)")
        
        // Insert records
        var ids: [UUID] = []
        for i in 0..<30 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i)
            ])
            let id = try db.insert(record)
            modelInsert(record)
            ids.append(id)
        }
        
        // Delete every other record
        for (i, id) in ids.enumerated() where i % 2 == 0 {
            try db.delete(id: id)
            modelDelete(id: id)
            
            // Verify deleted
            let truthRecord = modelFetch(id: id)
            let blazedbRecord = try db.fetch(id: id)
            
            XCTAssertNil(truthRecord, "Ground truth should not have deleted record")
            XCTAssertNil(blazedbRecord, "BlazeDB should not have deleted record")
        }
        
        // Final consistency check
        try validateConsistency()
        print("  ✅ All deletes consistent!")
    }
    
    func testModelBased_QueryOperations() throws {
        print("\n🎯 MODEL-BASED: Query Operations (100 operations)")
        
        // Insert records with various statuses
        for i in 0..<100 {
            let status = i % 3 == 0 ? "open" : (i % 3 == 1 ? "closed" : "pending")
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "status": .string(status),
                "priority": .int(i % 5)
            ])
            let id = try db.insert(record)
            modelInsert(record)
        }
        
        // Query by status
        let statuses = ["open", "closed", "pending"]
        for status in statuses {
            let truthIDs = modelQuery(where: "status", equals: .string(status))
            
            let blazedbResults = try db.query()
                .where("status", equals: .string(status))
                .execute()
            let blazedbIDs = Set(try blazedbResults.records.compactMap { $0.storage["id"]?.uuidValue })
            let truthIDSet = Set(truthIDs)
            
            XCTAssertEqual(blazedbIDs.count, truthIDSet.count, "Query for '\(status)' should return same count")
            XCTAssertEqual(blazedbIDs, truthIDSet, "Query for '\(status)' should return same IDs")
        }
        
        // Final consistency check
        try validateConsistency()
        print("  ✅ All queries consistent!")
    }
    
    func testModelBased_MixedOperations() throws {
        print("\n🎯 MODEL-BASED: Mixed Operations (200 operations)")
        
        var ids: [UUID] = []
        
        for i in 0..<200 {
            let op = i % 4
            
            switch op {
            case 0: // Insert
                let record = BlazeDataRecord([
                    "id": .uuid(UUID()),
                    "index": .int(i),
                    "value": .int(i * 2)
                ])
                let id = try db.insert(record)
                modelInsert(record)
                ids.append(id)
                
            case 1: // Update (if we have records)
                if !ids.isEmpty, let randomID = ids.randomElement() {
                    let update = BlazeDataRecord(["value": .int(i * 3)])
                    try db.update(id: randomID, with: update)
                    modelUpdate(id: randomID, with: update)
                }
                
            case 2: // Delete (if we have records)
                if !ids.isEmpty, let randomID = ids.randomElement() {
                    try db.delete(id: randomID)
                    modelDelete(id: randomID)
                    ids.removeAll { $0 == randomID }
                }
                
            case 3: // Query
                let truthCount = modelFetchAll().count
                let blazedbCount = try db.count()
                XCTAssertEqual(blazedbCount, truthCount, "Count should match after operation \(i)")
                
            default:
                break
            }
            
            // Validate consistency every 20 operations
            if i % 20 == 0 {
                try validateConsistency()
                print("  Validated consistency at operation \(i)...")
            }
        }
        
        // Final consistency check
        try validateConsistency()
        print("  ✅ All 200 mixed operations consistent!")
    }
    
    func testModelBased_IndexMismatchDetection() throws {
        print("\n🎯 MODEL-BASED: Index Mismatch Detection")
        
        // Create index
        let collection = db.collection as! DynamicCollection
        try collection.createIndex(on: "status")
        
        // Insert records
        for i in 0..<50 {
            let status = i % 2 == 0 ? "active" : "inactive"
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "status": .string(status)
            ])
            let id = try db.insert(record)
            modelInsert(record)
        }
        
        // Query using index
        let activeTruth = modelQuery(where: "status", equals: .string("active"))
        let activeBlaze = try collection.fetch(byIndexedField: "status", value: "active")
        let activeBlazeIDs = Set(activeBlaze.compactMap { $0.storage["id"]?.uuidValue })
        let activeTruthSet = Set(activeTruth)
        
        XCTAssertEqual(activeBlazeIDs.count, activeTruthSet.count, "Index query should match ground truth count")
        XCTAssertEqual(activeBlazeIDs, activeTruthSet, "Index query should match ground truth IDs")
        
        // Final consistency check
        try validateConsistency()
        print("  ✅ Index matches ground truth!")
    }
}

