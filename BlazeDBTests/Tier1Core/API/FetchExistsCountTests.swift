import XCTest
@testable import BlazeDBCore

final class FetchExistsCountTests: XCTestCase {

    private var dbNames: [String] = []

    override func tearDown() {
        super.tearDown()
        let tmp = FileManager.default.temporaryDirectory
        for name in dbNames {
            try? FileManager.default.removeItem(
                at: tmp.appendingPathComponent("\(name).blazedb")
            )
            try? FileManager.default.removeItem(
                at: tmp.appendingPathComponent("\(name).meta")
            )
        }
    }

    private func openDB(_ label: String) throws -> BlazeDBClient {
        let name = "fec-\(label)"
        dbNames.append(name)
        return try BlazeDBClient.openForTesting(name: name, password: "Test-FEC-123!")
    }

    // MARK: - fetchRequired

    func testFetchRequiredReturnsRecordWhenExists() throws {
        let db = try openDB("fetchReq1")
        defer { try? db.close() }

        let id = try db.insert(BlazeDataRecord(["k": .string("v")]))
        let record = try db.fetchRequired(id: id)
        XCTAssertEqual(record.storage["k"]?.stringValue, "v")
    }

    func testFetchRequiredThrowsRecordNotFoundWhenAbsent() throws {
        let db = try openDB("fetchReq2")
        defer { try? db.close() }

        let fakeID = UUID()
        XCTAssertThrowsError(try db.fetchRequired(id: fakeID)) { error in
            guard let blazeError = error as? BlazeDBError else {
                XCTFail("Expected BlazeDBError, got \(error)")
                return
            }
            if case .recordNotFound(let id, _, _) = blazeError {
                XCTAssertEqual(id, fakeID)
            } else {
                XCTFail("Expected .recordNotFound, got \(blazeError)")
            }
        }
    }

    // MARK: - exists

    func testExistsReturnsTrueWhenPresent() throws {
        let db = try openDB("exists1")
        defer { try? db.close() }

        let id = try db.insert(BlazeDataRecord(["k": .string("v")]))
        XCTAssertTrue(try db.exists(id: id))
    }

    func testExistsReturnsFalseWhenAbsent() throws {
        let db = try openDB("exists2")
        defer { try? db.close() }

        XCTAssertFalse(try db.exists(id: UUID()))
    }

    // MARK: - count

    func testCountReturnsRecordCount() throws {
        let db = try openDB("count1")
        defer { try? db.close() }

        XCTAssertEqual(try db.count(), 0)
        _ = try db.insert(BlazeDataRecord(["k": .string("a")]))
        _ = try db.insert(BlazeDataRecord(["k": .string("b")]))
        XCTAssertEqual(try db.count(), 2)
    }

    func testCountAfterDelete() throws {
        let db = try openDB("count2")
        defer { try? db.close() }

        let id = try db.insert(BlazeDataRecord(["k": .string("a")]))
        _ = try db.insert(BlazeDataRecord(["k": .string("b")]))
        XCTAssertEqual(try db.count(), 2)

        try db.delete(id: id)
        XCTAssertEqual(try db.count(), 1)
    }
}
