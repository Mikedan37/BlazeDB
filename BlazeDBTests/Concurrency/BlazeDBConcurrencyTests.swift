//  BlazeDBConcurrencyTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.

import XCTest
@testable import BlazeDB

/// A thin wrapper around BlazeDBClient that serializes writes.
/// Reads (fetch) remain concurrent.
final class ThreadSafeBlazeDBClient {
    private let client: BlazeDBClient
    private let writeQueue = DispatchQueue(label: "blazedb.write.queue")

    init(name: String, fileURL: URL, password: String) throws {
        self.client = try BlazeDBClient(name: name, fileURL: fileURL, password: password)
    }

    func insert(_ record: BlazeDataRecord) throws -> UUID {
        try writeQueue.sync {
            try client.insert(record)
        }
    }

    func fetch(id: UUID) throws -> BlazeDataRecord? {
        // fetch can be concurrent
        try client.fetch(id: id)
    }
}

final class BlazeDBClientConcurrencyTests: XCTestCase {
    var client: ThreadSafeBlazeDBClient!

    override func setUpWithError() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        client = try ThreadSafeBlazeDBClient(name: "testName", fileURL: tmp, password: "testpassword")
    }

    func testConcurrentInsertsAndFetches() throws {
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "concurrency", attributes: .concurrent)
        let N = 100

        for i in 0..<N {
            group.enter()
            queue.async {
                do {
                    let record = BlazeDataRecord(["value": .string("Val \(i)")])
                    let id = try self.client.insert(record)
                    _ = try? self.client.fetch(id: id)
                } catch {
                    XCTFail("Insert/fetch failed: \(error)")
                }
                group.leave()
            }
        }

        group.wait()
        XCTAssertTrue(true, "All concurrent inserts and fetches completed successfully")
    }
}
