import Foundation
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif
import XCTest
@testable import BlazeDB

// Use the real PageStore from the BlazeDB module
private typealias RealPageStore = BlazeDB.PageStore

final class PageStoreBoundaryTests: XCTestCase {

    // MARK: - Helpers

    private func tmpURL(_ name: String = UUID().uuidString) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return dir.appendingPathComponent("PageStoreBoundary-\(name).db")
    }

    /// Infers the page size by writing a single non-empty page and reading the file size.
    private func inferPageSize(at url: URL, key: SymmetricKey) throws -> Int {
        let store = try RealPageStore(fileURL: url, key: key)
        // Write a single non-empty page at index 0
        try store.writePage(index: 0, plaintext: Data([0x01]))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0, "File should have grown after first page write")
        return size
    }

    // MARK: - Tests

    /// Write/read exactly (pageSize - 37) bytes — the max payload accounting for encryption overhead:
    /// header(4) + version(1) + length(4) = 9 bytes, nonce(12) = 12 bytes, tag(16) = 16 bytes, total = 37 bytes.
    func testMaxPayloadRoundTrip() throws {
        let url = tmpURL()
        let key = SymmetricKey(size: .bits256)
        let pageSize = try inferPageSize(at: url, key: key)

        let maxPayload = pageSize - 37  // Account for encryption overhead
        let data = Data(repeating: 0xAB, count: maxPayload)

        let store = try RealPageStore(fileURL: url, key: key)
        try store.writePage(index: 1, plaintext: data)
        let out = try store.readPage(index: 1)
        XCTAssertEqual(out?.count ?? 0, data.count)
        XCTAssertEqual(out, data)
    }

    /// Attempt to write (pageSize - 36) bytes — should fail because it would overflow the page (needs 37 bytes overhead).
    func testTooLargePayloadThrows() throws {
        let url = tmpURL()
        let key = SymmetricKey(size: .bits256)
        let pageSize = try inferPageSize(at: url, key: key)

        let tooLarge = pageSize - 36  // One byte less than max (which is pageSize - 37)
        let data = Data(repeating: 0xCD, count: tooLarge)

        let store = try RealPageStore(fileURL: url, key: key)
        XCTAssertThrowsError(try store.writePage(index: 1, plaintext: data), "Writing payload that exceeds page capacity must throw")
    }

    /// Zero-length payload should round-trip cleanly.
    func testZeroLengthRoundTrip() throws {
        let url = tmpURL()
        let key = SymmetricKey(size: .bits256)
        _ = try inferPageSize(at: url, key: key)

        let store = try RealPageStore(fileURL: url, key: key)
        try store.writePage(index: 1, plaintext: Data())
        let out = try store.readPage(index: 1)
        XCTAssertEqual(out?.count ?? 0, 0)
    }

    /// Append many sequential max-payload pages and verify each read plus final file size.
    func testManySequentialMaxPayloadPages() throws {
        let url = tmpURL()
        let key = SymmetricKey(size: .bits256)
        let pageSize = try inferPageSize(at: url, key: key)

        let maxPayload = pageSize - 37  // Account for encryption overhead
        let payload = Data(repeating: 0xEE, count: maxPayload)

        let store = try RealPageStore(fileURL: url, key: key)

        let count = 32
        for i in 0..<count {
            try store.writePage(index: i + 1, plaintext: payload)
        }
        for i in 0..<count {
            let out = try store.readPage(index: i + 1)
            XCTAssertEqual(out?.count ?? 0, payload.count, "Mismatch at page \(i + 1) count")
            XCTAssertEqual(out, payload, "Mismatch at page \(i + 1)")
        }

        // Validate final file size equals total pages * pageSize (1 bootstrap + count written).
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(size, (count + 1) * pageSize, "File size should reflect all written pages exactly")
    }
    
    /// Test that data ending with zeros is NOT truncated (regression test for trailing zero bug)
    func testTrailingZerosPreserved() throws {
        let url = tmpURL()
        let key = SymmetricKey(size: .bits256)
        _ = try inferPageSize(at: url, key: key)
        
        // Create data that ends with multiple zeros
        var data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        data.append(Data(repeating: 0, count: 10))  // 10 trailing zeros
        
        let store = try RealPageStore(fileURL: url, key: key)
        try store.writePage(index: 1, plaintext: data)
        let recovered = try store.readPage(index: 1)
        
        XCTAssertEqual(recovered?.count, data.count, "Trailing zeros should be preserved")
        XCTAssertEqual(recovered, data, "Entire payload including trailing zeros should match")
    }
}

