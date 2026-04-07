import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import BlazeDBCore

#if canImport(Compression)
final class PageStoreCompressionStateTests: XCTestCase {
    private var tempDir: URL!
    private let testKey = SymmetricKey(size: .bits256)

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-compression-state-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCompressionStateHasNoStaticTableLeak() throws {
        XCTAssertEqual(PageStore._compressionStateTableCountForTests(), 0)

        var store: PageStore? = try PageStore(
            fileURL: tempDir.appendingPathComponent("state.db"),
            key: testKey
        )
        try XCTUnwrap(store).enableCompression()

        // Explicitly close and release to ensure deinit path is exercised.
        try XCTUnwrap(store).close()
        store = nil

        XCTAssertEqual(
            PageStore._compressionStateTableCountForTests(),
            0,
            "Compression state should be instance-scoped with no static table retention"
        )
    }

    func testCompressedWriteUsesWALDurabilityPath() throws {
        let dbURL = tempDir.appendingPathComponent("durable-compressed.db")
        let store = try PageStore(fileURL: dbURL, key: testKey, walMode: .legacy)
        defer { store.close() }

        store.enableCompression()
        let payload = Data(repeating: 0x41, count: 3000) // Compressible (>1KB)

        try store.writePageCompressed(index: 0, plaintext: payload)

        let walStats = try XCTUnwrap(store.walStats())
        XCTAssertGreaterThan(
            walStats.logFileSize,
            0,
            "Compressed writes must append to WAL before main-file write"
        )

        let readBack = try store.readPageCompressed(index: 0)
        XCTAssertEqual(readBack, payload)
    }
}
#endif
