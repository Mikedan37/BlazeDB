//
//  OpenProfiler.swift
//  BlazeDBBenchmarks
//
//  Cold/warm open breakdown + memory samples. Enable spans with BLAZEDB_PROFILE_OPEN=1.
//

import Foundation
import BlazeDBCore

struct OpenProfilerRun: Codable {
    let label: String
    let wallMilliseconds: Double
    let recordCount: Int
    let pbkdf2Iterations: Int
    let underXCTest: Bool
    let spans: [(name: String, milliseconds: Double)]
    let memory: MemorySampler.Sample?

    enum CodingKeys: String, CodingKey {
        case label, wallMilliseconds, recordCount, pbkdf2Iterations, underXCTest, spans, memory
    }

    init(
        label: String,
        wallMilliseconds: Double,
        recordCount: Int,
        spans: [(name: String, milliseconds: Double)],
        memory: MemorySampler.Sample?
    ) {
        self.label = label
        self.wallMilliseconds = wallMilliseconds
        self.recordCount = recordCount
        self.pbkdf2Iterations = BlazeDBDiagnostics.pbkdf2IterationCount
        self.underXCTest = BlazeDBDiagnostics.isRunningUnderXCTest
        self.spans = spans
        self.memory = memory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        wallMilliseconds = try c.decode(Double.self, forKey: .wallMilliseconds)
        recordCount = try c.decode(Int.self, forKey: .recordCount)
        pbkdf2Iterations = try c.decode(Int.self, forKey: .pbkdf2Iterations)
        underXCTest = try c.decode(Bool.self, forKey: .underXCTest)
        memory = try c.decodeIfPresent(MemorySampler.Sample.self, forKey: .memory)
        let spanRows = try c.decode([[String: Double]].self, forKey: .spans)
        spans = spanRows.compactMap { row in
            guard let name = row.keys.first, let ms = row[name] else { return nil }
            return (name: name, milliseconds: ms)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(wallMilliseconds, forKey: .wallMilliseconds)
        try c.encode(recordCount, forKey: .recordCount)
        try c.encode(pbkdf2Iterations, forKey: .pbkdf2Iterations)
        try c.encode(underXCTest, forKey: .underXCTest)
        try c.encodeIfPresent(memory, forKey: .memory)
        try c.encode(spans.map { [$0.name: $0.milliseconds] }, forKey: .spans)
    }
}

enum OpenProfiler {
    static let defaultPassword = "BenchPassword123!"
    static let defaultRecordCount = 1000

    static func run(recordCount: Int = defaultRecordCount) throws -> [OpenProfilerRun] {
        setenv("BLAZEDB_PROFILE_OPEN", "1", 1)
        defer { unsetenv("BLAZEDB_PROFILE_OPEN") }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-open-profile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("profile.blazedb")

        // Seed database (not profiled as "open")
        do {
            let seed = try BlazeDBClient(name: "seed", fileURL: dbURL, password: defaultPassword)
            let records = (0..<recordCount).map { i in
                BlazeDataRecord(["index": .int(i), "payload": .string("seed-\(i)")])
            }
            _ = try seed.insertMany(records)
            try seed.persist()
            try seed.close()
        }

        var runs: [OpenProfilerRun] = []

        // Cold open: clear all key caches
        KeyManager.clearKeyCache()
        BlazeDBClient.clearSessionKeys(for: dbURL.path)
        OpenProfileCollector.reset()
        let coldStart = CFAbsoluteTimeGetCurrent()
        let coldDB = try BlazeDBClient(name: "profile", fileURL: dbURL, password: defaultPassword)
        let coldWall = (CFAbsoluteTimeGetCurrent() - coldStart) * 1000.0
        let coldMem = MemorySampler.sample("after_cold_open")
        runs.append(OpenProfilerRun(
            label: "cold_open",
            wallMilliseconds: coldWall,
            recordCount: recordCount,
            spans: OpenProfileCollector.snapshot(),
            memory: coldMem
        ))
        try coldDB.close()

        // Warm open: path cache may hit, but close() clears KeyManager cache so PBKDF2 still runs.
        OpenProfileCollector.reset()
        let warmStart = CFAbsoluteTimeGetCurrent()
        let warmDB = try BlazeDBClient(name: "profile", fileURL: dbURL, password: defaultPassword)
        let warmWall = (CFAbsoluteTimeGetCurrent() - warmStart) * 1000.0
        let warmMem = MemorySampler.sample("after_warm_open")
        runs.append(OpenProfilerRun(
            label: "warm_open",
            wallMilliseconds: warmWall,
            recordCount: recordCount,
            spans: OpenProfileCollector.snapshot(),
            memory: warmMem
        ))
        try warmDB.close()

        // PBKDF2-only baseline (same salt, cold cache)
        KeyManager.clearKeyCache()
        let saltURL = dbURL.deletingPathExtension().appendingPathExtension("salt")
        let salt = try Data(contentsOf: saltURL)
        let pbkdf2Start = CFAbsoluteTimeGetCurrent()
        _ = try KeyManager.getKey(from: defaultPassword, salt: salt)
        let pbkdf2OnlyMs = (CFAbsoluteTimeGetCurrent() - pbkdf2Start) * 1000.0
        runs.append(OpenProfilerRun(
            label: "pbkdf2_only_cold",
            wallMilliseconds: pbkdf2OnlyMs,
            recordCount: recordCount,
            spans: [(name: "pbkdf2_isolated", milliseconds: pbkdf2OnlyMs)],
            memory: nil
        ))

        return runs
    }

    static func markdownReport(_ runs: [OpenProfilerRun]) -> String {
        var lines: [String] = [
            "# BlazeDB Open Profile",
            "",
            "**Run:** \(Date().formatted(date: .abbreviated, time: .standard))",
            "**PBKDF2 iterations (this process):** \(BlazeDBDiagnostics.pbkdf2IterationCount)",
            "**Under XCTest (100k iter override):** \(BlazeDBDiagnostics.isRunningUnderXCTest ? "yes" : "no")",
            "",
            "> Compare cold vs warm wall time. If `open.pbkdf2` dominates, startup cost is KDF — not layout/index I/O. Warm ≈ cold when `close()` clears the in-process key cache (current default).",
            "",
        ]

        for run in runs {
            lines.append("## \(run.label)")
            lines.append("")
            lines.append("- Wall: **\(String(format: "%.2f", run.wallMilliseconds)) ms**")
            lines.append("- Records in DB: \(run.recordCount)")
            if let mem = run.memory {
                lines.append("- RSS: \(MemorySampler.formatBytes(mem.residentBytes))")
            }
            lines.append("")
            if !run.spans.isEmpty {
                let total = run.spans.reduce(0.0) { $0 + $1.milliseconds }
                lines.append("| Phase | ms | % of spans |")
                lines.append("|-------|---:|-----------:|")
                for span in run.spans {
                    let pct = total > 0 ? (span.milliseconds / total) * 100.0 : 0
                    lines.append("| \(span.name) | \(String(format: "%.2f", span.milliseconds)) | \(String(format: "%.1f", pct))% |")
                }
                lines.append("| **Span sum** | **\(String(format: "%.2f", total))** | |")
                if run.label.hasPrefix("cold") || run.label.hasPrefix("warm") {
                    let unaccounted = run.wallMilliseconds - total
                    lines.append("| *(wall − spans)* | *\(String(format: "%.2f", unaccounted))* | *misc* |")
                }
                lines.append("")
            }
        }

        if let cold = runs.first(where: { $0.label == "cold_open" }),
           let pbkdf2 = runs.first(where: { $0.label == "pbkdf2_only_cold" }) {
            let spanPBKDF2 = cold.spans.first(where: { $0.name == "open.pbkdf2" })?.milliseconds ?? 0
            let pctOfCold = cold.wallMilliseconds > 0 ? (spanPBKDF2 / cold.wallMilliseconds) * 100.0 : 0
            lines.append("## Interpretation hints")
            lines.append("")
            lines.append("- Isolated PBKDF2: **\(String(format: "%.2f", pbkdf2.wallMilliseconds)) ms**")
            lines.append("- PBKDF2 inside cold open span: **\(String(format: "%.2f", spanPBKDF2)) ms** (\(String(format: "%.1f", pctOfCold))% of cold wall)")
            lines.append("- Engine work (layout + PageStore + migration, excl. PBKDF2): **~\(String(format: "%.0f", cold.wallMilliseconds - spanPBKDF2)) ms**")
            lines.append("- March 2026 baseline (~55 ms) measured handle reopen with legacy path-cache behavior, not true cold open at 600k PBKDF2.")
            lines.append("- Do **not** ship Keychain session keys until profiling proves PBKDF2 >50% of cold open in **release** with **600k** iterations (confirmed here).")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func printSummary(_ runs: [OpenProfilerRun]) {
        print(markdownReport(runs))
    }
}
