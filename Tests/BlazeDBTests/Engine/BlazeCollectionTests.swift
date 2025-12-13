//  BlazeCollectionTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
//
//  MIGRATED: Now uses BlazeDBClient + DynamicCollection instead of deprecated BlazeCollection
//  This test verifies the same functionality using the recommended API

import XCTest

@testable import BlazeDB

final class BlazeCollectionTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blazedb")
        
        db = try BlazeDBClient(name: "test", fileURL: tempURL, password: "BlazeCollectionTest123!")
    }

    override func tearDownWithError() throws {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
    }

    func testInsertAndFetchCommit() throws {
        let commit = Commit(id: UUID(), createdAt: .now, message: "Initial commit", author: "Michael")
        
        // Convert Commit (BlazeRecord) to BlazeDataRecord for insertion
        let encoder = BlazeRecordEncoder()
        try commit.encode(to: encoder)
        let record = encoder.getBlazeDataRecord()
        
        // Insert via BlazeDBClient (uses DynamicCollection internally)
        let id = try db.insert(record)
        XCTAssertEqual(id, commit.id)

        // Fetch via BlazeDBClient
        let fetchedRecord = try db.fetch(id: commit.id)
        XCTAssertNotNil(fetchedRecord)
        
        // Convert back to Commit
        let decoder = BlazeRecordDecoder(storage: fetchedRecord!.storage)
        let fetched = try Commit(from: decoder)
        
        print("Inserted Commit ID:", commit.id)
        print("Fetched Commit:", fetched)
        XCTAssertEqual(fetched.message, "Initial commit")
        XCTAssertEqual(fetched.id, commit.id)
    }
    
    func testDeleteRecord() throws {
        let commit = Commit(id: UUID(), createdAt: .now, message: "Fix", author: "Michael")
        
        // Convert and insert
        let encoder = BlazeRecordEncoder()
        try commit.encode(to: encoder)
        let record = encoder.getBlazeDataRecord()
        try db.insert(record)

        // Verify it exists
        var fetchedRecord = try db.fetch(id: commit.id)
        XCTAssertNotNil(fetchedRecord)
        print("Before delete fetched:", fetchedRecord)
        
        // Delete via BlazeDBClient
        try db.delete(id: commit.id)
        
        // Verify it's deleted
        fetchedRecord = try db.fetch(id: commit.id)
        XCTAssertNil(fetchedRecord)
        print("After delete fetched:", fetchedRecord)
        print("✅ testDeleteRecord completed")
    }
    
    func testUpdateRecord() throws {
        let id = UUID()
        let original = Commit(id: id, createdAt: .now, message: "Initial", author: "Michael")
        
        // Convert and insert
        let encoder = BlazeRecordEncoder()
        try original.encode(to: encoder)
        let record = encoder.getBlazeDataRecord()
        try db.insert(record)

        // Fetch and verify
        var fetchedRecord = try db.fetch(id: id)
        XCTAssertNotNil(fetchedRecord)
        let decoder = BlazeRecordDecoder(storage: fetchedRecord!.storage)
        var fetched = try Commit(from: decoder)
        XCTAssertEqual(fetched.message, "Initial")
        print("Original Commit:", original)
        print("Fetched before update:", fetched)

        // Update
        let updated = Commit(id: id, createdAt: .now, message: "Updated", author: "Michael")
        let updateEncoder = BlazeRecordEncoder()
        try updated.encode(to: updateEncoder)
        let updatedRecord = updateEncoder.getBlazeDataRecord()
        try db.update(id: id, with: updatedRecord)
        
        print("Updated Commit:", updated)

        // Fetch and verify update
        fetchedRecord = try db.fetch(id: id)
        XCTAssertNotNil(fetchedRecord)
        let updateDecoder = BlazeRecordDecoder(storage: fetchedRecord!.storage)
        fetched = try Commit(from: updateDecoder)
        print("Fetched after update:", fetched)
        XCTAssertEqual(fetched.message, "Updated")
    }
}

