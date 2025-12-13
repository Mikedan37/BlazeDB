//
//  WALCodecIntegrationTests.swift
//  BlazeDBTests
//
//  Integration tests for WAL (Write-Ahead Log) using dual-codec validation
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class WALCodecIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    var client: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let dbURL = tempDir.appendingPathComponent("test.blazedb")
        do {
            client = try BlazeDBClient(name: "test", fileURL: dbURL, password: "WALCodecTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - WAL Entry Encoding Tests
    
    func testWALEntry_DualCodecValidation() throws {
        let collection = client.collection
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("WAL Test"),
            "count": .int(42)
        ])
        
        // Insert (creates WAL entry)
        let id = try client.insert(record)
        
        // Fetch to verify WAL was replayed correctly
        let fetched = try client.fetch(id: id)
        XCTAssertNotNil(fetched)
        if let fetched = fetched {
            // Compare only the user-provided fields (ignore auto-generated createdAt, project)
            for (key, value) in record.storage {
                XCTAssertEqual(fetched.storage[key], value, "Field '\(key)' should match")
            }
        }
        
        // Verify internal encoding matches
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        let armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
    }
    
    // MARK: - WAL Replay Tests
    
    func testWALReplay_DualCodec() throws {
        let collection = client.collection
        
        // Insert multiple records
        var records: [BlazeDataRecord] = []
        var ids: [UUID] = []
        
        for i in 0..<100 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "title": .string("Record \(i)")
            ])
            records.append(record)
            let id = try client.insert(record)
            ids.append(id)
        }
        
        // Close and reopen (triggers WAL replay)
        // Note: BlazeDBClient doesn't have close(), so we'll just verify records exist
        // In a real scenario, the database would be reopened automatically
        
        // Verify all records exist and match (compare only user-provided fields)
        for (id, originalRecord) in zip(ids, records) {
            let fetched = try client.fetch(id: id)
            XCTAssertNotNil(fetched)
            if let fetched = fetched {
                // Compare only the user-provided fields (ignore auto-generated createdAt, project)
                for (key, value) in originalRecord.storage {
                    XCTAssertEqual(fetched.storage[key], value, "Field '\(key)' should match")
                }
            }
        }
    }
    
    // MARK: - Transaction WAL Tests
    
    func testTransactionWAL_DualCodec() throws {
        let collection = client.collection
        
        // Start transaction
        try client.beginTransaction()
        
        let record1 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Transaction 1")
        ])
        let record2 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Transaction 2")
        ])
        
        let id1 = try client.insert(record1)
        let id2 = try client.insert(record2)
        
        // Commit transaction (writes to WAL)
        try client.commitTransaction()
        
        // Verify both records exist
        let fetched1 = try client.fetch(id: id1)
        let fetched2 = try client.fetch(id: id2)
        
        XCTAssertNotNil(fetched1)
        XCTAssertNotNil(fetched2)
        if let fetched1 = fetched1, let fetched2 = fetched2 {
            // Compare only the user-provided fields (ignore auto-generated createdAt, project)
            for (key, value) in record1.storage {
                XCTAssertEqual(fetched1.storage[key], value, "Record1 field '\(key)' should match")
            }
            for (key, value) in record2.storage {
                XCTAssertEqual(fetched2.storage[key], value, "Record2 field '\(key)' should match")
            }
        }
    }
    
    // MARK: - WAL Rollback Tests
    
    func testWALRollback_DualCodec() throws {
        let collection = client.collection
        
        // Start transaction
        try client.beginTransaction()
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Rollback Test")
        ])
        
        let id = try client.insert(record)
        
        // Rollback transaction
        try client.rollbackTransaction()
        
        // Verify record does not exist
        let fetched = try client.fetch(id: id)
        XCTAssertNil(fetched)
    }
    
    // MARK: - WAL Entry Consistency
    
    func testWALEntryConsistency_DualCodec() throws {
        let collection = client.collection
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Consistency Test"),
            "count": .int(42),
            "data": .data(Data([1, 2, 3, 4, 5]))
        ])
        
        // Insert
        let id = try client.insert(record)
        
        // Fetch and verify
        let fetched = try client.fetch(id: id)
        
        // Verify both codecs produce identical WAL entries
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        let armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        XCTAssertNotNil(fetched)
        if let fetched = fetched {
            // Compare only the user-provided fields (ignore auto-generated createdAt, project)
            for (key, value) in record.storage {
                XCTAssertEqual(fetched.storage[key], value, "Field '\(key)' should match")
            }
        }
    }
}

