//
//  PayloadSizeSweep.swift
//  BlazeDBBenchmarks
//
//  BLAZEDB_BENCH_MODE=payload_size_sweep — latency vs payload size.
//

import Foundation
import BlazeDBCore

enum PayloadSizeSweep {
    /// Default sweep points (bytes of ASCII payload field body).
    static let defaultPayloadBytes: [Int] = [
        256, 1_024, 4_096, 16_384, 65_536, 262_144, 1_048_576, 4_194_304,
    ]

    struct Row: Codable {
        let requestedPayloadBytes: Int
        let encodedPayloadBytes: Int
        let inserts: Int
        let blazedbAvgMs: Double
        let blazedbP50Ms: Double
        let blazedbP95Ms: Double
        let blazedbP99Ms: Double
        let blazedbOpsPerSec: Double
        let path: String
        let notes: String
    }

    private static func insertCount(forPayloadBytes bytes: Int) -> Int {
        // Keep large payloads tractable; small ones get more samples for percentiles.
        switch bytes {
        case ..<4_096: return 200
        case ..<65_536: return 100
        case ..<1_048_576: return 40
        default: return 12
        }
    }

    static func run(
        payloadSizes: [Int] = defaultPayloadBytes,
        path: String = "durable_insert"
    ) throws -> [Row] {
        var rows: [Row] = []
        for size in payloadSizes {
            let n = insertCount(forPayloadBytes: size)
            let encoded = BenchPayload.sampleSizedEncodedBytes(payloadBytes: size)
            print("  payload=\(size) B (encoded≈\(encoded) B), inserts=\(n), path=\(path)...")

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("PayloadSweep-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let dbURL = tempDir.appendingPathComponent("sweep.blazedb")
            let db = try openBenchDB(name: "payload-sweep", fileURL: dbURL)
            var durationsMs: [Double] = []
            durationsMs.reserveCapacity(n)

            let wallStart = Date()
            switch path {
            case "insertMany_batch":
                let batchSize = min(50, n)
                var batch: [BlazeDataRecord] = []
                batch.reserveCapacity(batchSize)
                for i in 0..<n {
                    batch.append(BenchPayload.sizedRecord(index: i, payloadBytes: size))
                    if batch.count == batchSize || i == n - 1 {
                        let opStart = benchMonotonicNowMs()
                        _ = try db.insertMany(batch)
                        durationsMs.append(benchMonotonicNowMs() - opStart)
                        batch.removeAll(keepingCapacity: true)
                    }
                }
                try db.persist()
            case "transaction_puts":
                try db.beginTransaction()
                for i in 0..<n {
                    let record = BenchPayload.sizedRecord(index: i, payloadBytes: size)
                    let opStart = benchMonotonicNowMs()
                    _ = try db.insert(record)
                    durationsMs.append(benchMonotonicNowMs() - opStart)
                }
                try db.commitTransaction()
            case "update":
                // Seed full-size rows, then rewrite the payload field (same encoded size).
                var ids: [UUID] = []
                ids.reserveCapacity(n)
                for i in 0..<n {
                    let id = try db.insert(BenchPayload.sizedRecord(index: i, payloadBytes: size))
                    ids.append(id)
                }
                try db.persist()
                for (i, id) in ids.enumerated() {
                    // Flip filler so the update is not a no-op encode of identical bytes.
                    let body = String(repeating: i % 2 == 0 ? "y" : "z", count: max(0, size))
                    let updated = BlazeDataRecord([
                        "id": .uuid(id),
                        "index": .int(i),
                        BenchPayload.sweepPayloadField: .string(body),
                    ])
                    let opStart = benchMonotonicNowMs()
                    try db.update(id: id, with: updated)
                    durationsMs.append(benchMonotonicNowMs() - opStart)
                }
                try db.persist()
            default: // durable_insert — per-row insert + final persist (matches core harness)
                for i in 0..<n {
                    let record = BenchPayload.sizedRecord(index: i, payloadBytes: size)
                    let opStart = benchMonotonicNowMs()
                    _ = try db.insert(record)
                    durationsMs.append(benchMonotonicNowMs() - opStart)
                }
                try db.persist()
            }
            try db.close()
            let wallSec = Date().timeIntervalSince(wallStart)
            let stats = summarizeMs(durationsMs)
            rows.append(
                Row(
                    requestedPayloadBytes: size,
                    encodedPayloadBytes: encoded,
                    inserts: n,
                    blazedbAvgMs: stats?.avgMs ?? 0,
                    blazedbP50Ms: stats?.p50Ms ?? 0,
                    blazedbP95Ms: stats?.p95Ms ?? 0,
                    blazedbP99Ms: stats?.p99Ms ?? 0,
                    blazedbOpsPerSec: wallSec > 0 ? Double(n) / wallSec : 0,
                    path: path,
                    notes: "ASCII payload field; encoded includes BlazeBinary overhead + id/index"
                )
            )
        }
        return rows
    }

    static func markdownReport(_ rows: [Row]) -> String {
        var md = """
        # Payload size sweep

        _Generated by `BLAZEDB_BENCH_MODE=payload_size_sweep`._

        Small durable inserts are often dominated by **fixed commit/fsync cost**, not byte copies.
        Larger payloads increase encoding, AES-GCM work, pages touched, and bytes written — but not
        linearly (a 1 MB write is not ~1000× a 1 KB write).

        Page size is **4096** bytes. See `Docs/Benchmarks/PAYLOAD_SIZE.md`.

        | Requested payload B | Encoded B | Path | N | ops/s | avg ms | p50 | p95 | p99 |
        |---:|---:|---|---:|---:|---:|---:|---:|---:|

        """
        for r in rows {
            md += "| \(r.requestedPayloadBytes) | \(r.encodedPayloadBytes) | \(r.path) | \(r.inserts) | "
            md += String(format: "%.1f | %.3f | %.3f | %.3f | %.3f |\n",
                         r.blazedbOpsPerSec, r.blazedbAvgMs, r.blazedbP50Ms, r.blazedbP95Ms, r.blazedbP99Ms)
        }
        md += "\n"
        return md
    }
}
