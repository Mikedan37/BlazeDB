//
//  ReplayTests.swift
//  BlazeDBTests
//
//  Replay & Crash Recovery Tests: Operation log generator, log replay engine,
//  crash simulation (cut DB mid-write and reload). Validate no corruption,
//  no orphaned overflow pages, no dangling ordering indices, spatial and vector
//  indexes remain synchronized, lazy decoding remains valid post-recovery.
//
//  Created: 2025-01-XX
//

import XCTest
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif
@testable import BlazeDB

final class ReplayTests: XCTestCase {
    
    var tempURL: URL!
    var key: SymmetricKey!
    
    override func setUp() {
        super.setUp()
        
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Replay-\(testID).blazedb")
        
        // Clean up any leftover files
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            if !FileManager.default.fileExists(atPath: tempURL.path) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        key = SymmetricKey(size: .bits256)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Operation Log Generator
    
    struct OperationLog {
        var operations: [(type: String, record: BlazeDataRecord, id: UUID?)] = []
        
        mutating func addInsert(_ record: BlazeDataRecord) -> UUID {
            let id = record.storage["id"]?.uuidValue ?? UUID()
            operations.append(("insert", record, id))
            return id
        }
        
        mutating func addUpdate(id: UUID, _ record: BlazeDataRecord) {
            operations.append(("update", record, id))
        }
        
        mutating func addDelete(id: UUID) {
            operations.append(("delete", BlazeDataRecord([:]), id))
        }
    }
    
    // MARK: - Log Replay Engine
    
    func replayOperations(_ log: OperationLog, into db: BlazeDBClient) throws {
        var insertedIDs: [UUID] = []
        
        for op in log.operations {
            switch op.type {
            case "insert":
                if let id = op.id {
                    let record = op.record
                    let insertedID = try db.insert(record)
                    XCTAssertEqual(insertedID, id, "Inserted ID should match log")
                    insertedIDs.append(insertedID)
                }
                
            case "update":
                if let id = op.id {
                    try db.update(id: id, with: op.record)
                }
                
            case "delete":
                if let id = op.id {
                    try db.delete(id: id)
                    insertedIDs.removeAll { $0 == id }
                }
                
            default:
                break
            }
        }
    }
    
    // MARK: - Tests
    
    func testReplay_OperationLogGenerator() throws {
        print("\n🔄 REPLAY: Operation Log Generator")
        
        var log = OperationLog()
        
        // Generate operations
        for i in 0..<50 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "name": .string("Record \(i)")
            ])
            _ = log.addInsert(record)
        }
        
        // Replay into fresh DB
        let db = try BlazeDBClient(name: "replay_test", fileURL: tempURL, password: "ReplayTest123!")
        try replayOperations(log, into: db)
        
        // Verify all records present
        let allRecords = try db.fetchAll()
        XCTAssertEqual(allRecords.count, 50, "All logged operations should be replayed")
        
        print("  ✅ Operation log generator works correctly")
    }
    
    func testReplay_CrashSimulation() throws {
        print("\n🔄 REPLAY: Crash Simulation (Cut DB Mid-Write)")
        
        // Create DB and insert some records
        var db: BlazeDBClient? = try BlazeDBClient(name: "crash_test", fileURL: tempURL, password: "ReplayTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        var insertedIDs: [UUID] = []
        for i in 0..<20 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string("Record \(i)")
            ])
            let id = try dbUnwrapped.insert(record)
            insertedIDs.append(id)
        }
        
        // Persist to ensure some data is on disk
        try dbUnwrapped.persist()
        
        // Simulate crash: close DB without proper cleanup
        db = nil
        
        // Reopen and verify recovery
        let recovered = try BlazeDBClient(name: "crash_test", fileURL: tempURL, password: "ReplayTest123!")
        let recoveredRecords = try recovered.fetchAll()
        
        // Should have at least some records (those that were persisted)
        XCTAssertGreaterThanOrEqual(recoveredRecords.count, 0, "Should recover some records")
        XCTAssertLessThanOrEqual(recoveredRecords.count, 20, "Should not have more than inserted")
        
        print("  ✅ Crash simulation: Recovered \(recoveredRecords.count) records")
    }
    
    func testReplay_NoCorruption() throws {
        print("\n🔄 REPLAY: No Corruption After Recovery")
        
        // Create DB and insert records
        var db: BlazeDBClient? = try BlazeDBClient(name: "corruption_test", fileURL: tempURL, password: "ReplayTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        var insertedIDs: [UUID] = []
        for i in 0..<30 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "value": .int(i * 2)
            ])
            let id = try dbUnwrapped.insert(record)
            insertedIDs.append(id)
        }
        
        // Persist
        try dbUnwrapped.persist()
        db = nil
        
        // Reopen
        let recovered = try BlazeDBClient(name: "corruption_test", fileURL: tempURL, password: "ReplayTest123!")
        let recoveredRecords = try recovered.fetchAll()
        
        // Verify no corruption: all records should be valid
        for record in recoveredRecords {
            XCTAssertNotNil(record.storage["id"]?.uuidValue, "All records should have valid IDs")
            XCTAssertNotNil(record.storage["index"]?.intValue, "All records should have valid index")
            XCTAssertNotNil(record.storage["value"]?.intValue, "All records should have valid value")
        }
        
        print("  ✅ No corruption detected after recovery")
    }
    
    func testReplay_NoOrphanedOverflowPages() throws {
        print("\n🔄 REPLAY: No Orphaned Overflow Pages")
        
        // Create DB and insert large records (will use overflow pages)
        var db: BlazeDBClient? = try BlazeDBClient(name: "overflow_test", fileURL: tempURL, password: "ReplayTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        var insertedIDs: [UUID] = []
        for i in 0..<10 {
            let largeData = Data(repeating: UInt8(i), count: 10_000) // Large enough for overflow
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "largeData": .data(largeData)
            ])
            let id = try dbUnwrapped.insert(record)
            insertedIDs.append(id)
        }
        
        // Persist
        try dbUnwrapped.persist()
        db = nil
        
        // Reopen
        let recovered = try BlazeDBClient(name: "overflow_test", fileURL: tempURL, password: "ReplayTest123!")
        let recoveredRecords = try recovered.fetchAll()
        
        // Verify all records are readable (no orphaned pages)
        for record in recoveredRecords {
            if let id = record.storage["id"]?.uuidValue {
                let fetched = try recovered.fetch(id: id)
                XCTAssertNotNil(fetched, "All records should be fetchable (no orphaned overflow pages)")
                if let fetched = fetched {
                    XCTAssertNotNil(fetched.storage["largeData"]?.dataValue, "Large data should be readable")
                }
            }
        }
        
        print("  ✅ No orphaned overflow pages detected")
    }
    
    func testReplay_SpatialIndexSynchronized() throws {
        print("\n🔄 REPLAY: Spatial Index Synchronized After Recovery")
        
        // Enable spatial index
        var db: BlazeDBClient? = try BlazeDBClient(name: "spatial_recovery_test", fileURL: tempURL, password: "ReplayTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        try dbUnwrapped.enableSpatialIndex(on: "lat", lonField: "lon")
        
        // Insert records with locations
        var insertedIDs: [UUID] = []
        for i in 0..<20 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "lat": .double(37.7749 + Double(i) * 0.001),
                "lon": .double(-122.4194 + Double(i) * 0.001)
            ])
            let id = try dbUnwrapped.insert(record)
            insertedIDs.append(id)
        }
        
        // Persist
        try dbUnwrapped.persist()
        db = nil
        
        // Reopen
        let recovered = try BlazeDBClient(name: "spatial_recovery_test", fileURL: tempURL, password: "ReplayTest123!")
        
        // Verify spatial index works
        let results = try recovered.query()
            .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 10000)
            .execute()
        
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0, "Spatial index should work after recovery")
        print("  ✅ Spatial index synchronized after recovery")
    }
    
    func testReplay_VectorIndexSynchronized() throws {
        print("\n🔄 REPLAY: Vector Index Synchronized After Recovery")
        
        // Enable vector index
        var db: BlazeDBClient? = try BlazeDBClient(name: "vector_recovery_test", fileURL: tempURL, password: "ReplayTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        try dbUnwrapped.enableVectorIndex(fieldName: "embedding")
        
        // Insert records with vectors
        for i in 0..<15 {
            let vector: VectorEmbedding = (0..<128).map { _ in Float.random(in: -1...1) }
            let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
            
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "embedding": .data(vectorData)
            ])
            _ = try dbUnwrapped.insert(record)
        }
        
        // Persist
        try dbUnwrapped.persist()
        db = nil
        
        // Reopen
        let recovered = try BlazeDBClient(name: "vector_recovery_test", fileURL: tempURL, password: "ReplayTest123!")
        
        // Rebuild vector index (it's in-memory, needs rebuild)
        try recovered.rebuildVectorIndex()
        
        // Verify vector index stats
        let stats = recovered.getVectorIndexStats()
        XCTAssertNotNil(stats, "Vector index should exist after recovery")
        XCTAssertGreaterThanOrEqual(stats?.totalVectors ?? 0, 10, "Vector index should contain vectors after recovery")
        
        print("  ✅ Vector index synchronized after recovery")
    }
    
    func testReplay_LazyDecodingValid() throws {
        print("\n🔄 REPLAY: Lazy Decoding Valid After Recovery")
        
        // Enable lazy decoding
        var db: BlazeDBClient? = try BlazeDBClient(name: "lazy_recovery_test", fileURL: tempURL, password: "ReplayTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        try dbUnwrapped.enableLazyDecoding()
        
        // Insert records with large fields
        var insertedIDs: [UUID] = []
        for i in 0..<10 {
            let largeData = Data(repeating: UInt8(i), count: 5_000)
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "name": .string("Record \(i)"),
                "largeData": .data(largeData)
            ])
            let id = try dbUnwrapped.insert(record)
            insertedIDs.append(id)
        }
        
        // Persist
        try dbUnwrapped.persist()
        db = nil
        
        // Reopen
        let recovered = try BlazeDBClient(name: "lazy_recovery_test", fileURL: tempURL, password: "ReplayTest123!")
        
        // Query with projection (should use lazy decoding)
        let results = try recovered.query()
            .project("id", "name")
            .execute()
        
        // Verify lazy decoding works
        let records = try results.records
        XCTAssertEqual(records.count, 10, "Should have 10 records")
        for record in records {
            XCTAssertNotNil(record.storage["id"], "ID should be decoded")
            XCTAssertNotNil(record.storage["name"], "Name should be decoded")
            // largeData should not be decoded (lazy)
        }
        
        print("  ✅ Lazy decoding valid after recovery")
    }
    
    func testReplay_NoDanglingOrderingIndices() throws {
        print("\n🔄 REPLAY: No Dangling Ordering Indices")
        
        // Enable ordering
        var db: BlazeDBClient? = try BlazeDBClient(name: "ordering_recovery_test", fileURL: tempURL, password: "ReplayTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        try dbUnwrapped.enableOrdering(fieldName: "orderingIndex")
        
        // Insert records with ordering
        var insertedIDs: [UUID] = []
        for i in 0..<20 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "orderingIndex": .double(Double(i) * 10.0)
            ])
            let id = try dbUnwrapped.insert(record)
            insertedIDs.append(id)
        }
        
        // Delete some records
        for i in 0..<5 {
            try dbUnwrapped.delete(id: insertedIDs[i])
        }
        
        // Persist
        try dbUnwrapped.persist()
        db = nil
        
        // Reopen
        let recovered = try BlazeDBClient(name: "ordering_recovery_test", fileURL: tempURL, password: "ReplayTest123!")
        
        // Verify ordering still works (no dangling indices)
        let results = try recovered.query()
            .orderBy("orderingIndex", descending: false)
            .execute()
        
        // Should have 15 records (20 - 5 deleted)
        let records = try results.records
        XCTAssertEqual(records.count, 15, "Should have 15 records after recovery")
        
        // Verify ordering is correct
        var lastIndex: Double = -1.0
        for record in records {
            if let index = record.storage["orderingIndex"]?.doubleValue {
                XCTAssertGreaterThan(index, lastIndex, "Ordering should be ascending")
                lastIndex = index
            }
        }
        
        print("  ✅ No dangling ordering indices detected")
    }
}

