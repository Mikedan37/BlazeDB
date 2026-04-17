//
//  BlazeBinaryMisalignedSliceTests.swift
//  BlazeDB
//
//  Regression guard for GitHub #30: binary decode must not assume the backing
//  buffer starts at a scalar-aligned address (Linux traps on misaligned raw loads).

import XCTest
import Foundation
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class BlazeBinaryMisalignedSliceTests: XCTestCase {

    func testDecodeBlazeBinaryFromOneBytePaddedSubdataDoesNotTrap() throws {
        let record = BlazeDataRecord([
            "label": .string("misaligned-slice"),
            "n": .int(42),
        ])
        let encoded = try BlazeBinaryEncoder.encode(record)
        XCTAssertGreaterThanOrEqual(encoded.count, 8, "need full BlazeBinary header")

        let padded = Data([0x00]) + encoded
        let slice = padded.subdata(in: 1..<padded.count)
        XCTAssertEqual(slice.count, encoded.count)

        let decoded = try BlazeBinaryDecoder.decode(slice)
        XCTAssertEqual(decoded.string("label", default: ""), "misaligned-slice")
        XCTAssertEqual(decoded.int("n", default: 0), 42)
    }
}
