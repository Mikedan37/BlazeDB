import XCTest
@testable import BlazeDBAndroidBridge

final class BlazeDBAndroidBridgeLiveQueryTests: XCTestCase {
    private static let callback: blazedb_bridge_live_query_cb = { _, _ in }

    func testLiveQueryCanBorrowExistingSessionWithoutClosingIt() {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-bridge-live-query-\(UUID().uuidString)")
            .appendingPathExtension("blazedb")
        defer { removeDatabaseFiles(for: dbURL) }

        let handle = withCString(dbURL.path, "correct horse battery staple") { path, password in
            blazedb_bridge_open(path, password)
        }
        XCTAssertGreaterThan(handle, 0)
        defer { blazedb_bridge_close(handle) }

        let liveHandle = blazedb_bridge_live_query_start_for_handle(
            handle,
            Self.callback,
            nil
        )
        XCTAssertGreaterThan(liveHandle, 0)

        blazedb_bridge_live_query_stop(liveHandle)

        let putResult = withCString("todo", #"{"title":"still-open"}"#) { kind, json in
            blazedb_bridge_put_json(handle, kind, json)
        }
        XCTAssertEqual(putResult, 0, "Stopping a borrowed live query must not close the DB session")
    }

    private func withCString<T>(
        _ first: String,
        _ second: String,
        _ body: (UnsafePointer<CChar>, UnsafePointer<CChar>) -> T
    ) -> T {
        first.withCString { firstPtr in
            second.withCString { secondPtr in
                body(firstPtr, secondPtr)
            }
        }
    }

    private func removeDatabaseFiles(for url: URL) {
        let suffixes = [
            "",
            ".meta",
            ".wal",
            ".salt",
            ".tmp",
            ".backup",
            ".lock",
        ]
        for suffix in suffixes {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}
