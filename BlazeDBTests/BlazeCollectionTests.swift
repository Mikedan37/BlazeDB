//  BlazeCollectionTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.

// Ensure Commit conforms to Codable & Equatable:
// struct Commit: Codable, Equatable { ... }

import XCTest

@testable import BlazeDB

final class BlazeCollectionTests: XCTestCase {
    var tempURL: URL!
    var store: BlazeDB.PageStore!
    var collection: BlazeCollection<Commit>!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blz")
        
        let key = try KeyManager.getKey(from: .password("secure-test"))
        store = try BlazeDB.PageStore(fileURL: tempURL, key: key)

        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        collection = try BlazeCollection(store: store, metaURL: metaURL, key: key)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
    }

    func testInsertAndFetchCommit() throws {
        let commit = Commit(id: UUID(), createdAt: .now, message: "Initial commit", author: "Michael")
        try collection.insert(commit)

        let fetched = try collection.fetch(id: commit.id)
        print("Inserted Commit ID:", commit.id)
        print("Fetched Commit:", fetched)
        XCTAssertEqual(fetched?.message, "Initial commit")
        XCTAssertEqual(fetched?.id, commit.id)
    }
    
    func testDeleteRecord() throws {
        // 1. Insert a record and verify it exists
        let commit = Commit(id: UUID(), createdAt: .now, message: "Fix", author: "Michael")
        try collection.insert(commit)

        var fetched = try collection.fetch(id: commit.id)
        XCTAssertNotNil(fetched)
        print("Before delete fetched:", fetched)
        // 2. Delete the record

        try collection.delete(id: commit.id)
        fetched = try collection.fetch(id: commit.id)
        print("After delete fetched:", fetched)
        // 3. Verify the record is deleted
        XCTAssertNil(fetched)
        print("✅ testDeleteRecord completed")
    }
    
    
    func testUpdateRecord() throws {
        let id = UUID()
        let original = Commit(id: id, createdAt: .now, message: "Initial", author: "Michael")
        try collection.insert(original)

        var fetched = try collection.fetch(id: id)
        XCTAssertEqual(fetched?.message, "Initial")
        print("Original Commit:", original)
        print("Fetched before update:", fetched)

        let updated = Commit(id: id, createdAt: .now, message: "Updated", author: "Michael")
        print("Updated Commit:", updated)
        try collection.update(id: id, with: updated)

        fetched = try collection.fetch(id: id)
        print("Fetched after update:", fetched)
        XCTAssertEqual(fetched?.message, "Updated")
    }
}
