//  BlazeDBPersistanceTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/19/25.

import Foundation
import XCTest
import CryptoKit

@testable import BlazeDB

final class BlazeDBPersistenceTests: XCTestCase {
    
    func testPersistence() throws {
        let url = URL(fileURLWithPath: "/tmp/test-db.blaze")
        let meta = url.deletingPathExtension().appendingPathExtension("meta")
        
        // Clean slate
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: meta)
        
        // Derive encryption key
        let key = try KeyManager.getKey(from: .password("!Password123"))
        
        // Create a new store and collection
        let store: BlazeDB.PageStore = try BlazeDB.PageStore(fileURL: url, key: key)
        let collection = try DynamicCollection(
            store: store,
            metaURL: meta,
            project: "Devx",
            encryptionKey: key    // ✅ pass the instance, not the type
        )
        
        // Insert a record
        let insertedID = try collection.insert(BlazeDataRecord([
            "title": .string("Persist Test")
        ]))
        
        // Ensure writes are flushed
        Thread.sleep(forTimeInterval: 0.1)
        
        // Reopen the store/collection with the same key
        let reopenedStore: BlazeDB.PageStore = try BlazeDB.PageStore(fileURL: url, key: key)
        let newCollection = try DynamicCollection(
            store: reopenedStore,
            metaURL: meta,
            project: "Devx",
            encryptionKey: key    // ✅ must use the same key to decrypt
        )
        
        // Verify persistence
        let fetched = try newCollection.fetch(id: insertedID)
        XCTAssertEqual(fetched?.storage["title"]?.stringValue, "Persist Test")
    }
    
    func testCollectionReloadPersistsIndexesAndRecords() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        
        let key = try KeyManager.getKey(from: .password("reload-test-key"))
        
        var store: BlazeDB.PageStore = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        var collection = try DynamicCollection(store: store, metaURL: metaURL, project: "ReloadTest", encryptionKey: key)
        
        try collection.createIndex(on: ["status", "priority"])
        let record = BlazeDataRecord([
            "status": .string("done"),
            "priority": .int(1),
            "message": .string("hello world")
        ])
        _ = try collection.insert(record)
        // Force save of layout and indexes before reload
        try collection.saveLayout()
        Thread.sleep(forTimeInterval: 0.05)
        
        // Reload from disk
        store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        collection = try DynamicCollection(store: store, metaURL: metaURL, project: "ReloadTest", encryptionKey: key)
        
        let fetched = try collection.fetch(byIndexedFields: ["status", "priority"], values: ["done", 1])
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.storage["message"]?.stringValue, "hello world")
        
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
}
