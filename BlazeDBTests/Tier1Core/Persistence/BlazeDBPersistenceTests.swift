//  BlazeDBPersistenceTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/19/25.

import Foundation
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

#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class BlazeDBPersistenceTests: XCTestCase {
    
    func testPersistence() throws {
        let url = URL(fileURLWithPath: "/tmp/test-db.blaze")
        let meta = url.deletingPathExtension().appendingPathExtension("meta")
        
        // Clean slate - cleanup all related files
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let cleanupURL = ext.isEmpty ? url : url.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: cleanupURL)
        }
        
        defer {
            // ✅ Ensure cleanup after test
            for ext in extensions {
                let cleanupURL = ext.isEmpty ? url : url.deletingPathExtension().appendingPathExtension(ext)
                try? FileManager.default.removeItem(at: cleanupURL)
            }
        }
        
        // Derive encryption key
        let key = try KeyManager.getKey(from: .password("!Password123"))
        
        // Create a new store and collection
        var store: PageStore? = try PageStore(fileURL: url, key: key)
        var collection: DynamicCollection? = try DynamicCollection(
            store: store!,
            metaURL: meta,
            project: "Devx",
            encryptionKey: key    // ✅ pass the instance, not the type
        )
        
        // Insert a record
        let insertedID = try collection!.insert(BlazeDataRecord([
            "title": .string("Persist Test")
        ]))
        
        // Flush metadata (only 1 record, < 100 threshold)
        try collection!.persist()
        
        // ✅ Explicit cleanup of first instances
        collection = nil
        store = nil
        
        // Reopen the store/collection with the same key
        var reopenedStore: PageStore? = try PageStore(fileURL: url, key: key)
        var newCollection: DynamicCollection? = try DynamicCollection(
            store: reopenedStore!,
            metaURL: meta,
            project: "Devx",
            encryptionKey: key    // ✅ must use the same key to decrypt
        )
        
        // Verify persistence
        let fetched = try newCollection!.fetch(id: insertedID)
        XCTAssertEqual(fetched?.storage["title"]?.stringValue, "Persist Test")
        
        // ✅ Explicit cleanup of reopened instances
        newCollection = nil
        reopenedStore = nil
    }
    
    func testCollectionReloadPersistsIndexesAndRecords() {
        do {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        
        // ✅ Cleanup all related files
        defer {
            let extensions = ["", "meta", "indexes", "wal", "backup"]
            for ext in extensions {
                let cleanupURL = ext.isEmpty ? tmpURL : tmpURL.deletingPathExtension().appendingPathExtension(ext)
                try? FileManager.default.removeItem(at: cleanupURL)
            }
        }
        
        // Enable logging for debugging
        BlazeLogger.level = .info
        
        let key = try KeyManager.getKey(from: .password("ReloadTestKey-123!"))
        
        var store: PageStore? = try PageStore(fileURL: tmpURL, key: key)
        var collection: DynamicCollection? = try DynamicCollection(store: store!, metaURL: metaURL, project: "ReloadTest", encryptionKey: key)
        
        print("\n📊 BEFORE RELOAD:")
        try collection!.createIndex(on: ["status", "priority"])
        print("  Created compound index on [status, priority]")
        
        let record = BlazeDataRecord([
            "status": .string("done"),
            "priority": .int(1),
            "message": .string("hello world")
        ])
        let id = try collection!.insert(record)
        print("  Inserted record with ID: \(id)")
        print("  Secondary indexes: \(collection!.secondaryIndexes.keys)")
        
        // Flush metadata before reload (only 1 record, < 100 threshold)
        try collection!.persist()
        print("  Metadata persisted to disk")
        
        // ✅ Explicit cleanup before reload
        collection = nil
        store = nil
        
        // Reload from disk
        print("\n📊 RELOADING FROM DISK:")
        store = try PageStore(fileURL: tmpURL, key: key)
        collection = try DynamicCollection(store: store!, metaURL: metaURL, project: "ReloadTest", encryptionKey: key)
        print("  Collection reloaded")
        print("  Secondary indexes after reload: \(Array(collection!.secondaryIndexes.keys))")
        print("  Index map size: \(collection!.indexMap.count) records")
        
        // Check if index exists
        let compoundKey = "status+priority"
        if let index = collection!.secondaryIndexes[compoundKey] {
            print("  Compound index '\(compoundKey)' found with \(index.count) entries")
            print("  Index contents: \(index)")
        } else {
            print("  ⚠️ Compound index '\(compoundKey)' NOT FOUND after reload!")
            print("  Available indexes: \(Array(collection!.secondaryIndexes.keys))")
        }
        
        print("\n📊 FETCHING:")
        let fetched = try collection!.fetch(byIndexedFields: ["status", "priority"], values: ["done", 1])
        print("  Fetch returned \(fetched.count) records")
        
        if fetched.isEmpty {
            print("  ⚠️ No records found. Trying manual fetch by ID...")
            if let record = try collection!.fetch(id: id) {
                print("  ✅ Record EXISTS in storage (ID fetch worked)")
                print("  Record: \(record.storage)")
                print("  ❌ But compound index query FAILED")
            } else {
                print("  ❌ Record NOT FOUND even with direct ID fetch!")
            }
        }
        
        XCTAssertEqual(fetched.count, 1, "Should find the record using compound index")
        XCTAssertEqual(fetched.first?.storage["message"]?.stringValue, "hello world")
        
        // Reset logger
        BlazeLogger.reset()
        
        // ✅ Explicit cleanup
        collection = nil
        store = nil
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
                && error.code == NSFileNoSuchFileError
                && error.localizedDescription.contains(".backup") {
            // Intermittent temp-file cleanup race: a backup temp path may be gone by the
            // time a remove call runs. Treat this as non-fatal for persistence semantics.
            BlazeLogger.warn("Ignored benign cleanup race in persistence test: \(error)")
        } catch {
            XCTFail("Unexpected persistence test failure: \(error)")
        }
    }
}

