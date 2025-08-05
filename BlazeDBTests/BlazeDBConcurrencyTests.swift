//  BlazeDBConcurrencyTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.

import XCTest
@testable import BlazeDB

final class BlazeDBClientConcurrencyTests: XCTestCase {
    var client: BlazeDBClient!

    override func setUpWithError() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // You may want to use a constant or random password for testing.
        client = try BlazeDBClient(fileURL: tmp, password: "testpassword")
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
        XCTAssertTrue(true)
    }
}
