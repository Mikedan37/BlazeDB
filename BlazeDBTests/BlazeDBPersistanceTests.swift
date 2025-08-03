//  BlazeDBPersistanceTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/19/25.

import Foundation
import XCTest

@testable import BlazeDB


final class BlazeDBPersistanceTests: XCTestCase {
    
    func testPersistence() throws {
        let url = URL(fileURLWithPath: "/tmp/test-db.blaze")
        let meta = url.deletingPathExtension().appendingPathExtension("meta")

        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: meta)

        let key = try KeyManager.getKey(from: .password("!Password123"))
        let store = try PageStore(fileURL: url)

        let collection = try DynamicCollection(store: store, metaURL: meta, project: "Devx")
        let insertedID = try collection.insert(BlazeDataRecord([
            "title": .string("Persist Test")
        ]))

        // 👇 Ensure file writes are completed
        Thread.sleep(forTimeInterval: 0.1)
        let reopenedStore = try PageStore(fileURL: url)
        let newCollection = try DynamicCollection(store: reopenedStore, metaURL: meta, project: "Devx")

        let fetched = try newCollection.fetch(id: insertedID)
        XCTAssertEqual(fetched?.storage["title"], .string("Persist Test"))
    }
}
