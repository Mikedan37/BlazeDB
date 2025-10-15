import Foundation
import CryptoKit

enum PageStoreError: Error {
    case invalidPageSize
    case invalidHeader
    case keyMismatch
    // other existing cases...
}

final class PageStore {
    private var keyMismatch: Bool = false
    private var storage: [Int: Data] = [:]
    private var nextIndex: Int = 0
    public let fileURL: URL = URL(fileURLWithPath: "/dev/null")

    public func deletePage(index: Int) throws {
        storage.removeValue(forKey: index)
    }

    /// Computes a stable 16-byte tag for a given symmetric key.
    private func keyTag(for key: SymmetricKey) -> Data {
        let salt = Data("BlazeDB.PageStore.KeyTag".utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: salt, using: key)
        return Data(mac).prefix(16)
    }

    /// Loads an existing key tag from disk or creates it if missing.
    /// Returns `true` if the on-disk tag matches the provided key, `false` if it exists but does not match.
    private func loadOrCreateKeyTag(at url: URL, using key: SymmetricKey) {
        let tagURL = url.appendingPathExtension("keytag")
        let expected = keyTag(for: key)
        if FileManager.default.fileExists(atPath: tagURL.path) {
            if let data = try? Data(contentsOf: tagURL) {
                // If tag exists and doesn't match, mark mismatch.
                if data != expected {
                    self.keyMismatch = true
                }
            } else {
                // Could not read; attempt to write a fresh tag (best-effort).
                try? expected.write(to: tagURL, options: .atomic)
            }
        } else {
            // First open on a fresh file: create tag.
            try? expected.write(to: tagURL, options: .atomic)
        }
    }

    public init(fileURL: URL, key: SymmetricKey) throws {
        // existing initialization code for file handles, headers, etc.

        // Validate/open key tag sidecar; if it mismatches, we allow construction but block reads/writes.
        self.loadOrCreateKeyTag(at: fileURL, using: key)
    }

    public func read(index: Int) throws -> Data {
        if keyMismatch {
            throw PageStoreError.keyMismatch
        }
        guard let data = storage[index] else {
            throw PageStoreError.invalidHeader
        }
        return data
    }

    public func write(index: Int, data: Data) throws {
        if keyMismatch {
            throw PageStoreError.keyMismatch
        }
        storage[index] = data
    }

    @discardableResult
    public func write(_ data: Data) throws -> Int {
        if keyMismatch {
            throw PageStoreError.keyMismatch
        }
        let idx = nextIndex
        nextIndex += 1
        storage[idx] = data
        return idx
    }

    // rest of PageStore implementation...
}

import XCTest
@testable import BlazeDB

// Use the real PageStore from the BlazeDB module to avoid conflicts with any local test doubles.
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

    /// Write/read exactly (pageSize - 5) bytes — the max payload once header (4) + version (1) are accounted for.
    func testMaxPayloadRoundTrip() throws {
        let url = tmpURL()
        let key = SymmetricKey(size: .bits256)
        let pageSize = try inferPageSize(at: url, key: key)

        let maxPayload = pageSize - 5
        let data = Data(repeating: 0xAB, count: maxPayload)

        let store = try RealPageStore(fileURL: url, key: key)
        try store.writePage(index: 1, plaintext: data)
        let out = try store.readPage(index: 1)
        XCTAssertEqual(out?.count ?? 0, data.count)
        XCTAssertEqual(out, data)
    }

    /// Attempt to write (pageSize - 4) bytes — should fail because it would overflow the page.
    func testTooLargePayloadThrows() throws {
        let url = tmpURL()
        let key = SymmetricKey(size: .bits256)
        let pageSize = try inferPageSize(at: url, key: key)

        let tooLarge = pageSize - 4
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

        let maxPayload = pageSize - 5
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
}
