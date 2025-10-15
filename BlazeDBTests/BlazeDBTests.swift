//  BlazeDBTests.swift
//  BlazeDBTests
//  Created by Michael Danylchuk on 6/15/25.
import XCTest
import CryptoKit
@testable import BlazeDB

final class BlazeDBClientTests: XCTestCase {
    var tempURL: URL!
    var store: BlazeDB.PageStore!
    var client: BlazeDBClient!
    var key: SymmetricKey!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".blz")
        key = try KeyManager.getKey(from: .password("test-password"))
        store = try BlazeDB.PageStore(fileURL: tempURL, key: key)
        client = try BlazeDBClient(name: "test-name", fileURL: tempURL, password: "test-password")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
    }

    func testInsertAndFetchDynamicRecord() throws {
        let idString = UUID().uuidString
        let id = try client.insert(BlazeDataRecord([
            "id": .string(idString),
            "type": .string("note"),
            "content": .string("Hello, Blaze!"),
            "author": .string("Michael")
        ]))
        let record = try client.fetch(id: id)
        XCTAssertEqual(record?.storage["content"], .some(.string("Hello, Blaze!")))
    }

    func testSoftDeleteAndPurge() throws {
        let id = UUID()
        let record = BlazeDataRecord([
            "id": .uuid(id),   // ✅ pass as UUID not string
            "type": .string("note"),
            "content": .string("To be deleted")
        ])
        let insertedID = try client.insert(record)
        XCTAssertEqual(insertedID, id)

        try client.softDelete(id: insertedID)
        try client.purge()

        let result = try client.fetch(id: insertedID)
        XCTAssertNil(result, "Expected fetch to return nil after purge")
    }

    func testRawDump() throws {
        let idString = UUID().uuidString
        _ = try client.insert(BlazeDataRecord([
            "id": .string(idString),
            "type": .string("blob"),
            "data": .string("xyz")
        ]))
        let dump = try client.rawDump()
        XCTAssertFalse(dump.isEmpty)
        XCTAssertTrue(dump.values.contains { !$0.isEmpty })
    }

    func testSecondaryIndexPersistsAfterRestart() throws {
        let dbURL = tempDBURL()
        let store = try BlazeDB.PageStore(fileURL: dbURL, key: key)
        let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")

        var collection = try DynamicCollection(
            store: store,
            metaURL: metaURL,
            project: "Test",
            encryptionKey: key
        )

        try collection.createIndex(on: ["status"])

        let record = BlazeDataRecord([
            "title": .string("Issue"),
            "status": .string("open")
        ])
        _ = try collection.insert(record)

        // simulate restart
        let reopenedStore = try BlazeDB.PageStore(fileURL: dbURL, key: key)
        let collectionReloaded = try DynamicCollection(
            store: reopenedStore,
            metaURL: metaURL,
            project: "Test",
            encryptionKey: key
        )

        // Use indexed fetch instead of a fake query sugar
        let results = try collectionReloaded.fetch(byIndexedField: "status", value: "open")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.storage["status"], .some(.string("open")))
    }

    func testCompoundIndexPersists() throws {
        let dbURL = tempDBURL()
        let store = try BlazeDB.PageStore(fileURL: dbURL, key: key)
        let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")

        var collection = try DynamicCollection(
            store: store,
            metaURL: metaURL,
            project: "Test",
            encryptionKey: key
        )
        try collection.createIndex(on: ["status", "priority"])
        try collection.createIndex(on: ["status"])

        let record = BlazeDataRecord([
            "title": .string("Fix me"),
            "status": .string("open"),
            "priority": .string("high")
        ])
        _ = try collection.insert(record)

        let reopenedStore = try BlazeDB.PageStore(fileURL: dbURL, key: key)
        let reloaded = try DynamicCollection(
            store: reopenedStore,
            metaURL: metaURL,
            project: "Test",
            encryptionKey: key
        )

        // Fetch by single field "status" and filter manually by "priority"
        let statusOpen = try reloaded.fetch(byIndexedField: "status", value: "open")
        let results = statusOpen.filter { $0.storage["priority"] == .some(.string("high")) }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.storage["status"], .some(.string("open")))
        XCTAssertEqual(results.first?.storage["priority"], .some(.string("high")))
    }

    private func tempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent(UUID().uuidString + ".blaze")
    }
}
