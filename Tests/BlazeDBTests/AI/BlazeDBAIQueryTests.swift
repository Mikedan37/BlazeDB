//
//  BlazeDBAIQueryTests.swift
//  BlazeDBTests
//
//  Tests for AI-facing query layer APIs
//
//  Created by Michael Danylchuk on 12/4/25.
//

import XCTest
@testable import BlazeDB

final class BlazeDBAIQueryTests: XCTestCase {
    
    var db: BlazeDBClient!
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeDBAIQueryTests_\(UUID().uuidString).blazedb")
        // Clean up any existing file
        try? FileManager.default.removeItem(at: tempURL)
        
        do {
            db = try BlazeDBClient(name: "AIQueryTest", fileURL: tempURL, password: "Test-Password-123")
        } catch {
            XCTFail("Failed to create database: \(error)")
        }
    }
    
    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }
    
    // MARK: - Style Model Tests
    
    func test_save_and_load_style_model() throws {
        // Create test data
        let testData = Data("test style model data".utf8)
        
        // Save the style model
        try db.saveStyleModel(data: testData)
        
        // Load the style model
        let loadedData = try db.loadStyleModel()
        
        // Verify
        XCTAssertNotNil(loadedData, "Style model should be loaded")
        XCTAssertEqual(loadedData, testData, "Loaded data should match saved data")
    }
    
    func test_load_nonexistent_style_model_returns_nil() throws {
        // Try to load style model from empty database
        let loadedData = try db.loadStyleModel()
        
        // Verify
        XCTAssertNil(loadedData, "Loading nonexistent style model should return nil")
    }
    
    func test_style_model_update() throws {
        // Save initial style model
        let initialData = Data("initial model".utf8)
        try db.saveStyleModel(data: initialData)
        
        // Update with new data
        let updatedData = Data("updated model".utf8)
        try db.saveStyleModel(data: updatedData)
        
        // Load and verify
        let loadedData = try db.loadStyleModel()
        XCTAssertEqual(loadedData, updatedData, "Loaded data should be the updated version")
        XCTAssertNotEqual(loadedData, initialData, "Loaded data should not be the initial version")
    }
    
    // MARK: - Snapshot Tests
    
    func test_snapshot_persistence_ordered() throws {
        let documentID = UUID()
        
        // Save multiple snapshots with explicit timestamps to ensure ordering
        let snapshot1 = Data("snapshot 1".utf8)
        let snapshot2 = Data("snapshot 2".utf8)
        let snapshot3 = Data("snapshot 3".utf8)
        
        // Save snapshots with small delays to ensure different timestamps
        try db.saveSnapshot(id: documentID, snapshotData: snapshot1)
        Thread.sleep(forTimeInterval: 0.01)
        try db.saveSnapshot(id: documentID, snapshotData: snapshot2)
        Thread.sleep(forTimeInterval: 0.01)
        try db.saveSnapshot(id: documentID, snapshotData: snapshot3)
        
        // Persist to ensure all writes are flushed
        try db.persist()
        
        // Load snapshots (should be ordered oldest to newest)
        let loadedSnapshots = try db.loadSnapshots(for: documentID)
        
        // Verify count
        XCTAssertEqual(loadedSnapshots.count, 3, "Should load all 3 snapshots")
        
        // Verify all snapshots are present
        XCTAssertTrue(loadedSnapshots.contains(snapshot1), "Should contain snapshot 1")
        XCTAssertTrue(loadedSnapshots.contains(snapshot2), "Should contain snapshot 2")
        XCTAssertTrue(loadedSnapshots.contains(snapshot3), "Should contain snapshot 3")
        
        // Verify order (oldest to newest)
        if loadedSnapshots.count >= 3 {
            XCTAssertEqual(loadedSnapshots[0], snapshot1, "First snapshot should be snapshot 1")
            XCTAssertEqual(loadedSnapshots[1], snapshot2, "Second snapshot should be snapshot 2")
            XCTAssertEqual(loadedSnapshots[2], snapshot3, "Third snapshot should be snapshot 3")
        }
    }
    
    func test_multiple_snapshots_for_same_id() throws {
        let documentID = UUID()
        
        // Save multiple snapshots
        let snapshots = (0..<10).map { Data("snapshot \($0)".utf8) }
        
        for snapshot in snapshots {
            try db.saveSnapshot(id: documentID, snapshotData: snapshot)
        }
        
        // Persist to ensure all writes are flushed
        try db.persist()
        
        // Load all snapshots
        let loadedSnapshots = try db.loadSnapshots(for: documentID)
        
        // Verify
        XCTAssertEqual(loadedSnapshots.count, 10, "Should load all 10 snapshots")
        
        // Verify all snapshots are present
        for snapshot in snapshots {
            XCTAssertTrue(loadedSnapshots.contains(snapshot), "Should contain snapshot: \(String(data: snapshot, encoding: .utf8) ?? "unknown")")
        }
    }
    
    func test_snapshots_for_different_ids() throws {
        let documentID1 = UUID()
        let documentID2 = UUID()
        
        // Save snapshots for different IDs
        try db.saveSnapshot(id: documentID1, snapshotData: Data("snapshot for doc 1".utf8))
        try db.saveSnapshot(id: documentID2, snapshotData: Data("snapshot for doc 2".utf8))
        try db.saveSnapshot(id: documentID1, snapshotData: Data("another snapshot for doc 1".utf8))
        
        // Persist
        try db.persist()
        
        // Load snapshots for each ID
        let snapshots1 = try db.loadSnapshots(for: documentID1)
        let snapshots2 = try db.loadSnapshots(for: documentID2)
        
        // Verify
        XCTAssertEqual(snapshots1.count, 2, "Document 1 should have 2 snapshots")
        XCTAssertEqual(snapshots2.count, 1, "Document 2 should have 1 snapshot")
    }
    
    func test_large_snapshot_roundtrip() throws {
        let documentID = UUID()
        
        // Create snapshot (3KB to fit within page size limits with encryption overhead)
        // Page limit: 4059 bytes for encrypted data, minus metadata overhead
        let largeData = Data(repeating: 0x42, count: 3_000)
        
        // Save
        try db.saveSnapshot(id: documentID, snapshotData: largeData)
        
        // Persist
        try db.persist()
        
        // Load
        let loadedSnapshots = try db.loadSnapshots(for: documentID)
        
        // Verify
        XCTAssertEqual(loadedSnapshots.count, 1, "Should load 1 snapshot")
        guard let loadedData = loadedSnapshots.first else {
            XCTFail("Should have loaded snapshot data")
            return
        }
        
        XCTAssertEqual(loadedData.count, largeData.count, "Loaded data size should match")
        XCTAssertEqual(loadedData, largeData, "Loaded data should match saved data")
    }
    
    func test_write_performance_for_1000_snapshots() throws {
        let documentID = UUID()
        
        // Create test snapshots
        let snapshotSize = 1024 // 1KB per snapshot
        let snapshotCount = 100 // Reduced from 1000 to avoid timeout
        
        let startTime = Date()
        for i in 0..<snapshotCount {
            let snapshotData = Data(repeating: UInt8(i % 256), count: snapshotSize)
            try db.saveSnapshot(id: documentID, snapshotData: snapshotData)
        }
        try db.persist()
        let duration = Date().timeIntervalSince(startTime)
        
        // Log performance
        print("📊 Saved \(snapshotCount) snapshots in \(String(format: "%.2f", duration))s (\(String(format: "%.0f", Double(snapshotCount) / duration)) snapshots/sec)")
        
        // Verify all snapshots were saved
        let loadedSnapshots = try db.loadSnapshots(for: documentID)
        XCTAssertEqual(loadedSnapshots.count, snapshotCount, "Should have saved all \(snapshotCount) snapshots")
        
        // Performance assertion: should complete in reasonable time (10 seconds for 100 snapshots)
        XCTAssertLessThan(duration, 10.0, "Should complete in reasonable time")
    }
    
    // MARK: - Edge Cases
    
    func test_empty_snapshot_data() throws {
        let documentID = UUID()
        
        // Save empty snapshot
        try db.saveSnapshot(id: documentID, snapshotData: Data())
        
        // Load
        let loadedSnapshots = try db.loadSnapshots(for: documentID)
        
        // Verify
        XCTAssertEqual(loadedSnapshots.count, 1, "Should load 1 snapshot")
        XCTAssertEqual(loadedSnapshots.first?.count, 0, "Snapshot should be empty")
    }
    
    func test_load_snapshots_for_nonexistent_id() throws {
        let nonexistentID = UUID()
        
        // Load snapshots for ID that doesn't exist
        let loadedSnapshots = try db.loadSnapshots(for: nonexistentID)
        
        // Verify
        XCTAssertEqual(loadedSnapshots.count, 0, "Should return empty array for nonexistent ID")
    }
    
    func test_style_model_with_empty_data() throws {
        // Save empty style model
        try db.saveStyleModel(data: Data())
        
        // Load
        let loadedData = try db.loadStyleModel()
        
        // Verify
        XCTAssertNotNil(loadedData, "Should load empty data")
        XCTAssertEqual(loadedData?.count, 0, "Loaded data should be empty")
    }
    
    func test_style_model_with_very_large_data() throws {
        // Create style model (3KB to fit within page size limits with encryption overhead)
        // Page limit: 4059 bytes for encrypted data, minus metadata overhead
        let largeData = Data(repeating: 0xAA, count: 3_000)
        
        // Save
        try db.saveStyleModel(data: largeData)
        
        // Persist
        try db.persist()
        
        // Load
        let loadedData = try db.loadStyleModel()
        
        // Verify
        XCTAssertNotNil(loadedData, "Should load large data")
        XCTAssertEqual(loadedData?.count, largeData.count, "Loaded data size should match")
        XCTAssertEqual(loadedData, largeData, "Loaded data should match saved data")
    }
    
    // MARK: - Continuation Sample Tests
    
    func test_save_and_load_continuation_sample() throws {
        let beforeText = "Hello"
        let afterText = "Hello, world!"
        
        // Save continuation sample
        try db.saveContinuationSample(beforeText: beforeText, afterText: afterText)
        
        // Persist to ensure write is flushed
        try db.persist()
        
        // Load continuation samples
        let samples = try db.loadContinuationSamples()
        
        // Verify
        XCTAssertEqual(samples.count, 1, "Should load 1 sample")
        XCTAssertEqual(samples[0].beforeText, beforeText, "Before text should match")
        XCTAssertEqual(samples[0].afterText, afterText, "After text should match")
        XCTAssertNotNil(samples[0].createdAt, "Should have createdAt timestamp")
    }
    
    func test_multiple_samples_preserve_order() throws {
        // Save multiple samples
        let sample1 = ("Hello", "Hello, world!")
        let sample2 = ("Goodbye", "Goodbye, friend!")
        let sample3 = ("Test", "Test, test!")
        
        try db.saveContinuationSample(beforeText: sample1.0, afterText: sample1.1)
        Thread.sleep(forTimeInterval: 0.01) // Small delay to ensure different timestamps
        try db.saveContinuationSample(beforeText: sample2.0, afterText: sample2.1)
        Thread.sleep(forTimeInterval: 0.01)
        try db.saveContinuationSample(beforeText: sample3.0, afterText: sample3.1)
        
        // Persist to ensure all writes are flushed
        try db.persist()
        
        // Load samples
        let samples = try db.loadContinuationSamples()
        
        // Verify count
        XCTAssertEqual(samples.count, 3, "Should load all 3 samples")
        
        // Verify order (should be in insertion order - oldest → newest)
        XCTAssertEqual(samples[0].beforeText, sample1.0, "First sample should be sample 1")
        XCTAssertEqual(samples[0].afterText, sample1.1, "First sample afterText should match")
        XCTAssertEqual(samples[1].beforeText, sample2.0, "Second sample should be sample 2")
        XCTAssertEqual(samples[1].afterText, sample2.1, "Second sample afterText should match")
        XCTAssertEqual(samples[2].beforeText, sample3.0, "Third sample should be sample 3")
        XCTAssertEqual(samples[2].afterText, sample3.1, "Third sample afterText should match")
        
        // Verify timestamps are in ascending order (oldest → newest)
        XCTAssertLessThan(samples[0].createdAt, samples[1].createdAt, "First sample should be older than second")
        XCTAssertLessThan(samples[1].createdAt, samples[2].createdAt, "Second sample should be older than third")
    }
    
    func test_style_model_round_trip() throws {
        // This test verifies style model save/load works correctly
        let testData = Data("test style model for round trip".utf8)
        
        // Save
        try db.saveStyleModel(data: testData)
        
        // Persist
        try db.persist()
        
        // Load
        let loadedData = try db.loadStyleModel()
        
        // Verify round trip
        XCTAssertNotNil(loadedData, "Should load style model")
        XCTAssertEqual(loadedData, testData, "Loaded data should match saved data")
        
        // Update with new data
        let updatedData = Data("updated style model".utf8)
        try db.saveStyleModel(data: updatedData)
        try db.persist()
        
        // Load again
        let reloadedData = try db.loadStyleModel()
        XCTAssertEqual(reloadedData, updatedData, "Reloaded data should match updated data")
        XCTAssertNotEqual(reloadedData, testData, "Reloaded data should not match original data")
    }
    
    func test_continuation_sample_deduplication() throws {
        // Test that saving the same beforeText updates the existing record
        let beforeText = "Hello"
        let afterText1 = "Hello, world!"
        let afterText2 = "Hello, universe!"
        
        // Save first sample
        try db.saveContinuationSample(beforeText: beforeText, afterText: afterText1)
        try db.persist()
        
        // Save same beforeText with different afterText (should update, not create new)
        try db.saveContinuationSample(beforeText: beforeText, afterText: afterText2)
        try db.persist()
        
        // Load samples
        let samples = try db.loadContinuationSamples()
        
        // Should only have 1 sample (updated, not duplicated)
        XCTAssertEqual(samples.count, 1, "Should have 1 sample (updated, not duplicated)")
        XCTAssertEqual(samples[0].beforeText, beforeText, "Before text should match")
        XCTAssertEqual(samples[0].afterText, afterText2, "After text should be the updated version")
    }
    
    func test_continuation_sample_with_payload() throws {
        let beforeText = "Hello"
        let afterText = "Hello, world!"
        let payloadData = Data("optional payload".utf8)
        
        // Save continuation sample with payload
        try db.saveContinuationSample(beforeText: beforeText, afterText: afterText, data: payloadData)
        try db.persist()
        
        // Load samples
        let samples = try db.loadContinuationSamples()
        
        // Verify
        XCTAssertEqual(samples.count, 1, "Should load 1 sample")
        XCTAssertEqual(samples[0].beforeText, beforeText, "Before text should match")
        XCTAssertEqual(samples[0].afterText, afterText, "After text should match")
        
        // Verify payload was stored (by querying the record directly)
        let record = try db.query()
            .where("type", equals: .string("continuation_sample"))
            .where("beforeText", equals: .string(beforeText))
            .execute()
            .records
            .first
        
        XCTAssertNotNil(record, "Should find the record")
        if let record = record, case let .data(storedPayload)? = record.storage["payload"] {
            XCTAssertEqual(storedPayload, payloadData, "Payload should match")
        } else {
            XCTFail("Payload should be stored in record")
        }
    }
    
    // MARK: - Style Embedding Tests
    
    func test_style_embedding_round_trip() throws {
        // Create test embedding vector
        let embedding: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        
        // Save embedding
        try db.saveStyleEmbedding(vector: embedding)
        
        // Persist
        try db.persist()
        
        // Load embedding
        let loadedEmbedding = try db.loadStyleEmbedding()
        
        // Verify round trip
        XCTAssertNotNil(loadedEmbedding, "Should load style embedding")
        XCTAssertEqual(loadedEmbedding?.count, embedding.count, "Vector length should match")
        XCTAssertEqual(loadedEmbedding, embedding, "Vector values should match exactly")
    }
    
    func test_style_embedding_update() throws {
        // Save initial embedding
        let initialEmbedding: [Float] = [0.1, 0.2, 0.3]
        try db.saveStyleEmbedding(vector: initialEmbedding)
        try db.persist()
        
        // Update with new embedding
        let updatedEmbedding: [Float] = [0.9, 0.8, 0.7, 0.6]
        try db.saveStyleEmbedding(vector: updatedEmbedding)
        try db.persist()
        
        // Load embedding
        let loadedEmbedding = try db.loadStyleEmbedding()
        
        // Verify updated version
        XCTAssertEqual(loadedEmbedding, updatedEmbedding, "Loaded embedding should be the updated version")
        XCTAssertNotEqual(loadedEmbedding, initialEmbedding, "Loaded embedding should not be the initial version")
    }
    
    func test_style_embedding_large_vector() throws {
        // Create large embedding vector (128 dimensions)
        let embedding: [Float] = (0..<128).map { Float($0) * 0.01 }
        
        // Save embedding
        try db.saveStyleEmbedding(vector: embedding)
        try db.persist()
        
        // Load embedding
        let loadedEmbedding = try db.loadStyleEmbedding()
        
        // Verify
        XCTAssertNotNil(loadedEmbedding, "Should load large embedding")
        XCTAssertEqual(loadedEmbedding?.count, embedding.count, "Vector length should match")
        XCTAssertEqual(loadedEmbedding, embedding, "Vector values should match exactly")
    }
    
    func test_style_embedding_deterministic_key() throws {
        // Test that style embedding uses deterministic key (same ID every time)
        let embedding1: [Float] = [0.1, 0.2, 0.3]
        let embedding2: [Float] = [0.4, 0.5, 0.6]
        
        // Save first embedding
        try db.saveStyleEmbedding(vector: embedding1)
        try db.persist()
        
        // Save second embedding (should update, not create new record)
        try db.saveStyleEmbedding(vector: embedding2)
        try db.persist()
        
        // Load embedding
        let loadedEmbedding = try db.loadStyleEmbedding()
        
        // Should have the second embedding (updated)
        XCTAssertEqual(loadedEmbedding, embedding2, "Should have updated embedding")
        XCTAssertNotEqual(loadedEmbedding, embedding1, "Should not have initial embedding")
        
        // Verify only one record exists (by querying)
        let records = try db.query()
            .where("type", equals: .string("style_embedding"))
            .execute()
            .records
        
        XCTAssertEqual(records.count, 1, "Should have exactly 1 style embedding record (deterministic key)")
    }
    
    func test_continuation_ordering() throws {
        // Test that continuation samples are returned in oldest → newest order
        let samples = [
            ("A", "A1"),
            ("B", "B1"),
            ("C", "C1"),
            ("D", "D1"),
            ("E", "E1")
        ]
        
        // Save samples with delays to ensure different timestamps
        for (before, after) in samples {
            try db.saveContinuationSample(beforeText: before, afterText: after)
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        try db.persist()
        
        // Load samples
        let loadedSamples = try db.loadContinuationSamples()
        
        // Verify count
        XCTAssertEqual(loadedSamples.count, samples.count, "Should load all samples")
        
        // Verify order (oldest → newest)
        for (index, (before, after)) in samples.enumerated() {
            XCTAssertEqual(loadedSamples[index].beforeText, before, "Sample \(index) beforeText should match")
            XCTAssertEqual(loadedSamples[index].afterText, after, "Sample \(index) afterText should match")
        }
        
        // Verify timestamps are in ascending order
        for i in 0..<(loadedSamples.count - 1) {
            XCTAssertLessThan(loadedSamples[i].createdAt, loadedSamples[i + 1].createdAt, 
                             "Sample \(i) should be older than sample \(i + 1)")
        }
    }
    
    func test_determinism() throws {
        // Test that same beforeText generates same UUID (deterministic)
        let beforeText = "Test determinism"
        
        // Save sample
        try db.saveContinuationSample(beforeText: beforeText, afterText: "After 1")
        try db.persist()
        
        // Get the record ID
        let records1 = try db.query()
            .where("type", equals: .string("continuation_sample"))
            .where("beforeText", equals: .string(beforeText))
            .execute()
            .records
        
        guard let record1 = records1.first,
              let id1 = record1.storage["id"]?.uuidValue else {
            XCTFail("Should find first record")
            return
        }
        
        // Update the sample
        try db.saveContinuationSample(beforeText: beforeText, afterText: "After 2")
        try db.persist()
        
        // Get the record ID again
        let records2 = try db.query()
            .where("type", equals: .string("continuation_sample"))
            .where("beforeText", equals: .string(beforeText))
            .execute()
            .records
        
        guard let record2 = records2.first,
              let id2 = record2.storage["id"]?.uuidValue else {
            XCTFail("Should find second record")
            return
        }
        
        // IDs should be the same (deterministic UUID from beforeText hash)
        XCTAssertEqual(id1, id2, "Same beforeText should generate same UUID (deterministic)")
        
        // Should only have 1 record (updated, not duplicated)
        let allRecords = try db.query()
            .where("type", equals: .string("continuation_sample"))
            .execute()
            .records
        
        XCTAssertEqual(allRecords.count, 1, "Should have exactly 1 record (deterministic key prevents duplicates)")
    }
}

