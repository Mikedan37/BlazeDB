//
//  VectorBinaryRoundTripTests.swift
//  BlazeDBTests — vector components survive encode, fetch, and reopen
//
//  BlazeBinary stores each vector component as big-endian IEEE-754 binary32.
//  A record written with [1.0, -2.5, 0] must come back as those values.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class VectorBinaryRoundTripTests: XCTestCase {
    private let components: [Double] = [1.0, -2.5, 0.0, 0.5]

    func testEncodeDecodePreservesFloat32VectorComponents() throws {
        let record = BlazeDataRecord(["embedding": .vector(components)])
        let standard = try BlazeBinaryEncoder.encode(record)
        let optimized = try BlazeBinaryEncoder.encodeOptimized(record)
        let arm = try BlazeBinaryEncoder.encodeARM(record)

        XCTAssertEqual(standard, optimized)
        XCTAssertEqual(standard, arm)
        let oneAsFloat32: [UInt8] = [0x0A, 0x00, 0x00, 0x00, 0x04, 0x3F, 0x80, 0x00, 0x00]
        XCTAssertNotNil(
            standard.range(of: Data(oneAsFloat32)),
            "1.0 must be stored as big-endian float32 0x3F800000"
        )

        for encoded in [standard, arm] {
            let decoded = try BlazeBinaryDecoder.decode(encoded)
            let decodedARM = try BlazeBinaryDecoder.decodeARM(encoded)
            XCTAssertEqual(vector(in: decoded), components)
            XCTAssertEqual(vector(in: decodedARM), components)
        }
    }

    func testEncodeDecodePreservesEmptyVector() throws {
        let record = BlazeDataRecord(["embedding": .vector([])])
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        XCTAssertEqual(vector(in: decoded), [])
    }

    func testInsertFetchAndReopenPreservesVector() throws {
        let password = UUID().uuidString + "aA1!"
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VectorRoundTrip-\(UUID().uuidString).blazedb")
        defer {
            let base = dbURL.deletingPathExtension()
            for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
                try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
            }
            try? FileManager.default.removeItem(at: dbURL)
        }

        let db = try BlazeDBClient(name: "VectorRoundTrip", fileURL: dbURL, password: password)
        let id = try db.insert(BlazeDataRecord([
            "title": .string("note"),
            "embedding": .vector(components)
        ]))
        XCTAssertEqual(vector(in: try db.fetch(id: id)), components)
        try db.close()

        let reopened = try BlazeDBClient(name: "VectorRoundTrip", fileURL: dbURL, password: password)
        defer { try? reopened.close() }
        XCTAssertEqual(vector(in: try reopened.fetch(id: id)), components)
    }

    private func vector(in record: BlazeDataRecord?) -> [Double] {
        guard case .vector(let values) = record?.storage["embedding"] else {
            XCTFail("expected a vector field")
            return []
        }
        return values
    }
}
