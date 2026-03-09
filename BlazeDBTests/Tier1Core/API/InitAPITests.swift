import XCTest
@testable import BlazeDBCore

final class InitAPITests: XCTestCase {

    func testOpenAtURL() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("init-test-\(UUID().uuidString).blazedb")
        defer {
            try? FileManager.default.removeItem(at: url)
            let metaURL = url.deletingPathExtension().appendingPathExtension("meta")
            try? FileManager.default.removeItem(at: metaURL)
        }

        let db = try BlazeDBClient.open(at: url, password: "Test-Password-123!")
        let id = try db.insert(BlazeDataRecord(["k": .string("v")]))
        try db.close()

        let db2 = try BlazeDBClient.open(at: url, password: "Test-Password-123!")
        XCTAssertNotNil(try db2.fetch(id: id))
        try db2.close()
    }

    func testOpenNamedPasswordWorks() throws {
        let db = try BlazeDBClient.openForTesting(name: "init-api-test", password: "Test-Password-123!")
        defer { try? db.close() }

        let id = try db.insert(BlazeDataRecord(["k": .string("v")]))
        XCTAssertNotNil(try db.fetch(id: id))
    }
}
