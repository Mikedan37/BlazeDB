import Foundation
import XCTest
import BlazeDBC
@testable import BlazeDBCore

/// Exercises the stable C ABI via the Swift @_cdecl entry points.
final class BlazeDBCSmokeTests: XCTestCase {
    func testOpenPutGetFreeDeleteClose() throws {
        let url = makeTempURL(name: "c-abi-smoke")
        defer { cleanupBlazeDBFiles(at: url) }

        let path = url.path
        let password = "DemoPass123!"

        let db = path.withCString { pathC in
            password.withCString { passC in
                blazedb_open(pathC, passC)
            }
        }
        XCTAssertNotNil(db, "blazedb_open should succeed")
        defer { blazedb_close(db) }

        let key = "job:42"
        let payload = Array("hello-bytes".utf8)

        let putRC = key.withCString { keyC in
            payload.withUnsafeBytes { raw in
                blazedb_put(db, keyC, raw.baseAddress, payload.count)
            }
        }
        XCTAssertEqual(putRC, 0, "BLAZEDB_OK")

        // get → free → get → free
        for _ in 0..<2 {
            var data: UnsafeMutableRawPointer?
            var length = 0
            let getRC = key.withCString { keyC in
                blazedb_get(db, keyC, &data, &length)
            }
            XCTAssertEqual(getRC, 0)
            XCTAssertEqual(length, payload.count)
            XCTAssertNotNil(data)
            if let data {
                let bytes = Array(UnsafeBufferPointer(
                    start: data.assumingMemoryBound(to: UInt8.self),
                    count: length
                ))
                XCTAssertEqual(bytes, payload)
                blazedb_free(data)
            }
        }

        let delRC = key.withCString { keyC in blazedb_delete(db, keyC) }
        XCTAssertEqual(delRC, 0)

        var data: UnsafeMutableRawPointer?
        var length = 0
        let missingRC = key.withCString { keyC in
            blazedb_get(db, keyC, &data, &length)
        }
        XCTAssertEqual(missingRC, 1, "BLAZEDB_NOT_FOUND")
        XCTAssertNil(data)
        XCTAssertEqual(length, 0)
    }

    func testOpenRejectsNullAndEmptyPassword() {
        let url = makeTempURL(name: "c-abi-auth")
        defer { cleanupBlazeDBFiles(at: url) }
        let path = url.path

        XCTAssertNil(path.withCString { blazedb_open($0, nil) })
        XCTAssertNil(path.withCString { pathC in
            "".withCString { blazedb_open(pathC, $0) }
        })
    }
}
