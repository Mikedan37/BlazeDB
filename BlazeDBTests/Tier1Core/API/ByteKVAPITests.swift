import Foundation
import XCTest
@testable import BlazeDBCore

final class ByteKVAPITests: XCTestCase {
    private var db: BlazeDBClient!
    private var url: URL!

    override func setUpWithError() throws {
        url = makeTempURL(name: "byte-kv")
        db = try BlazeDBClient.open(at: url, password: "DemoPass123!")
    }

    override func tearDownWithError() throws {
        try? db?.close()
        db = nil
        cleanupBlazeDBFiles(at: url)
    }

    func testPutGetRoundTrip() throws {
        let payload = Data("hello-manager".utf8)
        try db.put(key: "job:42", value: payload)
        let got = try db.get(key: "job:42")
        XCTAssertEqual(got, payload)
    }

    func testEmptyValueRoundTrip() throws {
        try db.put(key: "empty", value: Data())
        let got = try db.get(key: "empty")
        XCTAssertEqual(got, Data())
    }

    func testBinaryValueExactBytes() throws {
        let payload = Data([0x00, 0xFF, 0x01, 0x7F, 0x80])
        try db.put(key: "bin", value: payload)
        XCTAssertEqual(try db.get(key: "bin"), payload)
    }

    func testOverwrite() throws {
        try db.put(key: "k", value: Data("a".utf8))
        try db.put(key: "k", value: Data("b".utf8))
        XCTAssertEqual(try db.get(key: "k"), Data("b".utf8))
    }

    func testDeleteThenNotFound() throws {
        try db.put(key: "job:42", value: Data([1, 2, 3]))
        try db.delete(key: "job:42")
        XCTAssertNil(try db.get(key: "job:42"))
        // Idempotent
        try db.delete(key: "job:42")
    }

    func testMissingKeyReturnsNil() throws {
        XCTAssertNil(try db.get(key: "missing"))
    }

    func testEmptyKeyRejected() throws {
        XCTAssertThrowsError(try db.put(key: "", value: Data([1]))) { error in
            guard case BlazeDBError.invalidInput = error else {
                return XCTFail("expected invalidInput, got \(error)")
            }
        }
    }

    func testOwnershipSmokeSequence() throws {
        try db.put(key: "job:42", value: Data("one".utf8))
        XCTAssertEqual(try db.get(key: "job:42"), Data("one".utf8))
        XCTAssertEqual(try db.get(key: "job:42"), Data("one".utf8))
        try db.delete(key: "job:42")
        XCTAssertNil(try db.get(key: "job:42"))
    }
}
