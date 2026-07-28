//
//  WriteProfiler.swift
//  BlazeDBBenchmarks
//
//  Runs single insert / InsertMany / transaction puts under BLAZEDB_WRITE_PROFILE=1.
//

import Foundation
import BlazeDBCore

enum WriteProfiler {
    static let defaultRecordCount = 50

    struct Run: Codable {
        let label: String
        let path: String
        let batchSize: Int
        let wallMilliseconds: Double
        let spans: [(name: String, milliseconds: Double)]
        let bytesWritten: Int
        let writeSyscalls: Int
        let fsyncSyscalls: Int

        enum CodingKeys: String, CodingKey {
            case label, path, batchSize, wallMilliseconds, spans, bytesWritten, writeSyscalls, fsyncSyscalls
        }

        struct SpanDTO: Codable {
            let name: String
            let milliseconds: Double
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(label, forKey: .label)
            try c.encode(path, forKey: .path)
            try c.encode(batchSize, forKey: .batchSize)
            try c.encode(wallMilliseconds, forKey: .wallMilliseconds)
            try c.encode(spans.map { SpanDTO(name: $0.name, milliseconds: $0.milliseconds) }, forKey: .spans)
            try c.encode(bytesWritten, forKey: .bytesWritten)
            try c.encode(writeSyscalls, forKey: .writeSyscalls)
            try c.encode(fsyncSyscalls, forKey: .fsyncSyscalls)
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = try c.decode(String.self, forKey: .label)
            path = try c.decode(String.self, forKey: .path)
            batchSize = try c.decode(Int.self, forKey: .batchSize)
            wallMilliseconds = try c.decode(Double.self, forKey: .wallMilliseconds)
            let dtos = try c.decode([SpanDTO].self, forKey: .spans)
            spans = dtos.map { ($0.name, $0.milliseconds) }
            bytesWritten = try c.decode(Int.self, forKey: .bytesWritten)
            writeSyscalls = try c.decode(Int.self, forKey: .writeSyscalls)
            fsyncSyscalls = try c.decode(Int.self, forKey: .fsyncSyscalls)
        }

        init(
            label: String,
            path: String,
            batchSize: Int,
            wallMilliseconds: Double,
            spans: [(name: String, milliseconds: Double)],
            bytesWritten: Int,
            writeSyscalls: Int,
            fsyncSyscalls: Int
        ) {
            self.label = label
            self.path = path
            self.batchSize = batchSize
            self.wallMilliseconds = wallMilliseconds
            self.spans = spans
            self.bytesWritten = bytesWritten
            self.writeSyscalls = writeSyscalls
            self.fsyncSyscalls = fsyncSyscalls
        }
    }

    private static func makeRecord(_ i: Int) -> BlazeDataRecord {
        // Keep write-profile rows small and explicit; report encoded size in markdown.
        BenchPayload.standardRecord(index: i, dataPrefix: "write-profile")
    }

    private static func openClient(at dir: URL, password: String) throws -> BlazeDBClient {
        let url = dir.appendingPathComponent("write-profile.blazedb")
        return try BlazeDBClient(name: "write_profile", fileURL: url, password: password)
    }

    private static func capture(
        label: String,
        path: WriteProfilePath,
        batchSize: Int,
        wallMs: Double
    ) -> Run {
        let snap = WriteProfileCollector.snapshot()
        return Run(
            label: label,
            path: path.rawValue,
            batchSize: batchSize,
            wallMilliseconds: wallMs,
            spans: snap.spans.map { ($0.name, $0.milliseconds) },
            bytesWritten: snap.bytesWritten,
            writeSyscalls: snap.syscallCounts[.write] ?? 0,
            fsyncSyscalls: snap.syscallCounts[.fsync] ?? 0
        )
    }

    static func run(recordCount: Int = defaultRecordCount) throws -> [Run] {
        setenv("BLAZEDB_WRITE_PROFILE", "1", 1)
        defer { unsetenv("BLAZEDB_WRITE_PROFILE") }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WriteProfiler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let password = "WriteProfile-Pass-123!"
        var runs: [Run] = []

        // --- single durable insert (first write) ---
        do {
            let dir = root.appendingPathComponent("single", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let db = try openClient(at: dir, password: password)
            WriteProfileCollector.reset()
            let t0 = BlazeDBDiagnostics.monotonicSeconds()
            _ = try db.insert(makeRecord(0))
            let wall = (BlazeDBDiagnostics.monotonicSeconds() - t0) * 1000.0
            runs.append(capture(label: "single_insert_first", path: .singleInsert, batchSize: 1, wallMs: wall))
            // steady-state second insert
            WriteProfileCollector.reset()
            let t1 = BlazeDBDiagnostics.monotonicSeconds()
            _ = try db.insert(makeRecord(1))
            let wall2 = (BlazeDBDiagnostics.monotonicSeconds() - t1) * 1000.0
            runs.append(capture(label: "single_insert_steady", path: .singleInsert, batchSize: 1, wallMs: wall2))
        }

        // --- InsertMany ---
        do {
            let dir = root.appendingPathComponent("many", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let db = try openClient(at: dir, password: password)
            let records = (0..<recordCount).map { makeRecord($0) }
            WriteProfileCollector.reset()
            let t0 = BlazeDBDiagnostics.monotonicSeconds()
            _ = try db.insertMany(records)
            let wall = (BlazeDBDiagnostics.monotonicSeconds() - t0) * 1000.0
            runs.append(capture(label: "insertMany_\(recordCount)", path: .insertMany, batchSize: recordCount, wallMs: wall))
        }

        // --- transaction with N puts (client transaction API) ---
        do {
            let dir = root.appendingPathComponent("txn", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let db = try openClient(at: dir, password: password)
            WriteProfileCollector.reset()
            WriteProfileCollector.beginOperation(
                WriteProfileOperation(
                    path: .transactionPuts,
                    batchSize: recordCount,
                    durabilityMode: "client_transaction",
                    recordBytes: 64,
                    steadyState: false
                )
            )
            let t0 = BlazeDBDiagnostics.monotonicSeconds()
            try db.beginTransaction()
            for i in 0..<recordCount {
                _ = try db.insert(makeRecord(10_000 + i))
            }
            try db.commitTransaction()
            let wall = (BlazeDBDiagnostics.monotonicSeconds() - t0) * 1000.0
            WriteProfileCollector.record("transaction.total", milliseconds: wall)
            WriteProfileCollector.endOperation()
            runs.append(capture(label: "transaction_puts_\(recordCount)", path: .transactionPuts, batchSize: recordCount, wallMs: wall))
        }

        return runs
    }

    static func markdownReport(_ runs: [Run]) -> String {
        let sample = BenchPayload.standardRecord(index: 0, dataPrefix: "write-profile")
        let encoded = BenchPayload.encodedByteCount(sample)
        var lines = [
            "# Write path profile",
            "",
            "Opt-in (`BLAZEDB_WRITE_PROFILE=1`). Compares single insert, InsertMany, and transaction puts.",
            "No optimization conclusions — stage attribution only.",
            "",
            "Record shape: `\(BenchPayload.standardShapeDescription)` · median encoded ≈ **\(encoded) B** (see Docs/Benchmarks/PAYLOAD_SIZE.md).",
            "Payload size changes latency, but not always linearly — fixed commit/fsync often dominates small rows.",
            "",
        ]
        for run in runs {
            lines.append("## \(run.label)")
            lines.append("")
            lines.append("path=`\(run.path)` batch=\(run.batchSize) wall=\(String(format: "%.2f", run.wallMilliseconds))ms bytes=\(run.bytesWritten) write=\(run.writeSyscalls) fsync=\(run.fsyncSyscalls)")
            lines.append("")
            if run.spans.isEmpty {
                lines.append("(no spans)")
            } else {
                let total = run.spans.reduce(0.0) { $0 + $1.milliseconds }
                lines.append("| Stage | ms | % |")
                lines.append("|-------|---:|--:|")
                for span in run.spans {
                    let pct = total > 0 ? (span.milliseconds / total) * 100.0 : 0
                    lines.append("| \(span.name) | \(String(format: "%.3f", span.milliseconds)) | \(String(format: "%.1f", pct))% |")
                }
            }
            lines.append("")
        }
        lines.append("Rule: do not optimize until one or two stages dominate wall time.")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func printSummary(_ runs: [Run]) {
        print(markdownReport(runs))
    }
}
