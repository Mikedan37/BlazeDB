import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import BlazeDBCore

#if canImport(Compression)
final class CompressedPageRoundTripTests: XCTestCase {
    func testCompressedV03PageRoundTripsThroughReadPageCompressed() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tier0-CompressedRoundTrip-\(UUID().uuidString).blazedb")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: tempURL, key: key)
        defer { store.close() }

        store.enableCompression()

        // Highly compressible payload ensures v0x03 is emitted.
        let original = Data(repeating: 0x41, count: 3000)
        try store.writePageCompressed(index: 0, plaintext: original)

        let rawHandle = try FileHandle(forReadingFrom: tempURL)
        defer { try? rawHandle.close() }
        let rawPage = try XCTUnwrap(rawHandle.read(upToCount: 4096))
        XCTAssertGreaterThanOrEqual(rawPage.count, 5)
        XCTAssertEqual(rawPage[4], 0x03)

        let roundTripped = try store.readPageCompressed(index: 0)
        XCTAssertEqual(roundTripped, original)
    }
}
#endif
