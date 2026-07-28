//
//  BenchPayload.swift
//  BlazeDBBenchmarks
//
//  Canonical record shapes + encoded-size measurement for honest latency docs.
//

import Foundation
import BlazeDBCore

enum BenchPayload {
    /// Default core-harness row: id + index + short string (not a bulk blob).
    static let standardShapeDescription =
        "id(UUID)+index(Int)+data(String \"Record|Batch Record N\"); pageSize=4096"

    /// Fixed ASCII filler used by the payload-size sweep (UTF-8 1 byte/char).
    static let sweepPayloadField = "payload"

    static func standardRecord(index: Int, dataPrefix: String = "Record") -> BlazeDataRecord {
        BlazeDataRecord([
            "id": .uuid(UUID()),
            "index": .int(index),
            "data": .string("\(dataPrefix) \(index)"),
        ])
    }

    /// Record with an explicit payload body of `payloadBytes` ASCII bytes (plus id/index overhead).
    static func sizedRecord(index: Int, payloadBytes: Int) -> BlazeDataRecord {
        let body = String(repeating: "x", count: max(0, payloadBytes))
        return BlazeDataRecord([
            "id": .uuid(UUID()),
            "index": .int(index),
            sweepPayloadField: .string(body),
        ])
    }

    static func encodedByteCount(_ record: BlazeDataRecord) -> Int {
        (try? BlazeBinaryEncoder.encode(record).count) ?? 0
    }

    /// Median encoded size over a few sample indices (string length varies slightly with `N`).
    static func sampleStandardEncodedBytes(dataPrefix: String = "Record", samples: Int = 32) -> Int {
        var sizes: [Int] = []
        sizes.reserveCapacity(samples)
        for i in 0..<samples {
            sizes.append(encodedByteCount(standardRecord(index: i, dataPrefix: dataPrefix)))
        }
        sizes.sort()
        return sizes[sizes.count / 2]
    }

    static func sampleSizedEncodedBytes(payloadBytes: Int, samples: Int = 8) -> Int {
        var sizes: [Int] = []
        sizes.reserveCapacity(samples)
        for i in 0..<samples {
            sizes.append(encodedByteCount(sizedRecord(index: i, payloadBytes: payloadBytes)))
        }
        sizes.sort()
        return sizes[sizes.count / 2]
    }
}
