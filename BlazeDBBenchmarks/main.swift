//
//  main.swift
//  BlazeDBBenchmarks
//
//  Honest, reproducible benchmarks comparing BlazeDB to SQLite
//  Same hardware, same dataset, same language
//

import Foundation
import BlazeDBCore

#if canImport(SQLite3)
import SQLite3
#endif

struct BenchmarkResult: Codable {
    let name: String
    let condition: String
    let supportStatus: String
    let blazedbOpsPerSec: Double
    let blazedbAvgMs: Double?
    let blazedbP50Ms: Double?
    let blazedbP95Ms: Double?
    let blazedbP99Ms: Double?
    let sqliteOpsPerSec: Double?
    let sqliteAvgMs: Double?
    let sqliteP50Ms: Double?
    let sqliteP95Ms: Double?
    let sqliteP99Ms: Double?
    let datasetSize: Int
    let notes: String
}

struct BenchCondition {
    let id: String
    let mvccRequested: Bool
    let walRequested: Bool
    let encryptionRequested: Bool
    let mvccEffective: Bool
    let walEffective: Bool
    let encryptionEffective: Bool

    var supportStatus: String {
        let fullySupported = walRequested == walEffective && encryptionRequested == encryptionEffective
        return fullySupported ? "supported" : "partially_supported"
    }
}

func parseOnOffEnv(_ key: String, defaultValue: Bool) -> Bool {
    guard let raw = ProcessInfo.processInfo.environment[key]?.lowercased() else {
        return defaultValue
    }
    if raw == "1" || raw == "true" || raw == "on" || raw == "yes" {
        return true
    }
    if raw == "0" || raw == "false" || raw == "off" || raw == "no" {
        return false
    }
    return defaultValue
}

#if BLAZEDB_BENCHMARK_NO_ENCRYPTION
let benchmarkEncryptionEnabled = false
#else
let benchmarkEncryptionEnabled = true
#endif

let benchmarkCondition = {
    let mvccRequested = parseOnOffEnv("BLAZEDB_BENCH_MVCC", defaultValue: true)
    let walRequested = parseOnOffEnv("BLAZEDB_BENCH_WAL", defaultValue: true)
    let encryptionRequested = parseOnOffEnv("BLAZEDB_BENCH_ENCRYPTION", defaultValue: true)
    return BenchCondition(
        id: ProcessInfo.processInfo.environment["BLAZEDB_BENCH_CONDITION"] ?? "baseline",
        mvccRequested: mvccRequested,
        walRequested: walRequested,
        encryptionRequested: encryptionRequested,
        mvccEffective: mvccRequested, // TODO: Query actual MVCC state from BlazeDBClient after construction to confirm effective value
        walEffective: true,
        encryptionEffective: benchmarkEncryptionEnabled
    )
}()

func openBenchDB(name: String, fileURL: URL) throws -> BlazeDBClient {
    let db = try BlazeDBClient(name: name, fileURL: fileURL, password: "BenchPassword123!")
    db.setMVCCEnabled(benchmarkCondition.mvccEffective)
    return db
}

struct StatsSummary {
    let avgMs: Double
    let p50Ms: Double
    let p95Ms: Double
    let p99Ms: Double
}

func summarizeMs(_ samples: [Double]) -> StatsSummary? {
    guard !samples.isEmpty else { return nil }
    let sorted = samples.sorted()
    let avg = samples.reduce(0, +) / Double(samples.count)
    let p50 = sorted[sorted.count / 2]
    let p95Index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
    let p99Index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.99))
    let p95 = sorted[p95Index]
    let p99 = sorted[p99Index]
    return StatsSummary(avgMs: avg, p50Ms: p50, p95Ms: p95, p99Ms: p99)
}

func chunked<T>(_ array: [T], by size: Int) -> [[T]] {
    guard size > 0 else { return [array] }
    var chunks: [[T]] = []
    chunks.reserveCapacity((array.count + size - 1) / size)
    var index = 0
    while index < array.count {
        let end = min(index + size, array.count)
        chunks.append(Array(array[index..<end]))
        index = end
    }
    return chunks
}

#if canImport(SQLite3)
private let benchSQLiteInsertDDL =
    "CREATE TABLE IF NOT EXISTS records (id TEXT PRIMARY KEY, index_val INTEGER, data TEXT)"

func sqliteConfigureForBench(_ db: OpaquePointer?) {
    guard let db else { return }
    sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
    sqlite3_exec(db, "PRAGMA synchronous=FULL", nil, nil, nil)
}

func sqliteSeedRecords(db: OpaquePointer?, count: Int) {
    guard let db else { return }
    sqlite3_exec(db, benchSQLiteInsertDDL, nil, nil, nil)
    let insertStmt = "INSERT INTO records (id, index_val, data) VALUES (?, ?, ?)"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, insertStmt, -1, &statement, nil) == SQLITE_OK else { return }
    defer { sqlite3_finalize(statement) }
    sqlite3_exec(db, "BEGIN", nil, nil, nil)
    for i in 0..<count {
        let id = UUID().uuidString
        sqlite3_bind_text(statement, 1, id, -1, nil)
        sqlite3_bind_int(statement, 2, Int32(i))
        sqlite3_bind_text(statement, 3, "Record \(i)", -1, nil)
        sqlite3_step(statement)
        sqlite3_reset(statement)
    }
    sqlite3_exec(db, "COMMIT", nil, nil, nil)
}

func sqliteTouchDatabase(at url: URL) throws {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
        throw NSError(domain: "BlazeDBBenchmarks", code: 1, userInfo: [NSLocalizedDescriptionKey: "sqlite3_open failed"])
    }
    defer { sqlite3_close(db) }
    sqliteConfigureForBench(db)
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM records", -1, &statement, nil) == SQLITE_OK else { return }
    defer { sqlite3_finalize(statement) }
    _ = sqlite3_step(statement)
}

func benchmarkSQLiteColdOpen(recordCount: Int = 1000, iterations: Int = 10) -> (opsPerSec: Double, stats: StatsSummary?) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let sqliteURL = tempDir.appendingPathComponent("sqlite_cold_open.db")
    var db: OpaquePointer?
    guard sqlite3_open(sqliteURL.path, &db) == SQLITE_OK, let db else {
        return (0, nil)
    }
    sqliteConfigureForBench(db)
    sqliteSeedRecords(db: db, count: recordCount)
    sqlite3_close(db)

    var openTimesMs: [Double] = []
    openTimesMs.reserveCapacity(iterations)
    for _ in 0..<iterations {
        let start = Date()
        do {
            try sqliteTouchDatabase(at: sqliteURL)
        } catch {
            return (0, nil)
        }
        openTimesMs.append(Date().timeIntervalSince(start) * 1000.0)
    }
    let avgSec = (openTimesMs.reduce(0, +) / Double(openTimesMs.count)) / 1000.0
    return (avgSec > 0 ? 1.0 / avgSec : 0, summarizeMs(openTimesMs))
}
#endif

func benchmarkBlazeDBOpenCycles(
    recordCount: Int = 1000,
    iterations: Int = 10,
    clearSessionEachOpen: Bool
) -> (opsPerSec: Double, stats: StatsSummary?) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("open_cycles.db")
    do {
        let seed = try openBenchDB(name: "open-seed", fileURL: dbURL)
        for i in 0..<recordCount {
            _ = try seed.insert(BlazeDataRecord(["index": .int(i), "data": .string("Record \(i)")]))
        }
        try seed.persist()
        try seed.close()

        if clearSessionEachOpen {
            BlazeDBClient.clearSessionKeys(for: dbURL.path)
        }

        var openTimesMs: [Double] = []
        openTimesMs.reserveCapacity(iterations)
        for _ in 0..<iterations {
            if clearSessionEachOpen {
                BlazeDBClient.clearSessionKeys(for: dbURL.path)
            }
            let start = Date()
            let db = try openBenchDB(name: "open-bench", fileURL: dbURL)
            openTimesMs.append(Date().timeIntervalSince(start) * 1000.0)
            try db.close()
        }
        let avgSec = (openTimesMs.reduce(0, +) / Double(openTimesMs.count)) / 1000.0
        return (avgSec > 0 ? 1.0 / avgSec : 0, summarizeMs(openTimesMs))
    } catch {
        print("BlazeDB open-cycle benchmark failed: \(error)")
        return (0, nil)
    }
}

struct BenchmarkSuite {
    var results: [BenchmarkResult] = []
    
    mutating func run(
        name: String,
        datasetSize: Int,
        blazedbOpsPerSec: Double,
        blazedbStats: StatsSummary?,
        sqliteOpsPerSec: Double? = nil,
        sqliteStats: StatsSummary? = nil,
        notes: String = ""
    ) {
        var mergedNotes = notes
        if benchmarkCondition.walRequested != benchmarkCondition.walEffective {
            mergedNotes += (mergedNotes.isEmpty ? "" : " | ") + "Requested WAL=\(benchmarkCondition.walRequested ? "on" : "off"), effective=on"
        }
        if benchmarkCondition.encryptionRequested != benchmarkCondition.encryptionEffective {
            mergedNotes += (mergedNotes.isEmpty ? "" : " | ") + "Requested encryption=\(benchmarkCondition.encryptionRequested ? "on" : "off"), effective=on"
        }
        results.append(BenchmarkResult(
            name: name,
            condition: benchmarkCondition.id,
            supportStatus: benchmarkCondition.supportStatus,
            blazedbOpsPerSec: blazedbOpsPerSec,
            blazedbAvgMs: blazedbStats?.avgMs,
            blazedbP50Ms: blazedbStats?.p50Ms,
            blazedbP95Ms: blazedbStats?.p95Ms,
            blazedbP99Ms: blazedbStats?.p99Ms,
            sqliteOpsPerSec: sqliteOpsPerSec,
            sqliteAvgMs: sqliteStats?.avgMs,
            sqliteP50Ms: sqliteStats?.p50Ms,
            sqliteP95Ms: sqliteStats?.p95Ms,
            sqliteP99Ms: sqliteStats?.p99Ms,
            datasetSize: datasetSize,
            notes: mergedNotes
        ))
    }
    
    func toMarkdown() -> String {
        var md = "# BlazeDB Benchmarks\n\n"
        md += "**Date:** \(Date().formatted(date: .abbreviated, time: .shortened))\n\n"
        md += "**Condition:** `\(benchmarkCondition.id)` (`mvcc=\(benchmarkCondition.mvccEffective ? "on" : "off")`, `wal=\(benchmarkCondition.walEffective ? "on" : "off")`, `encryption=\(benchmarkCondition.encryptionEffective ? "on" : "off")`)\n\n"
        md += "> **Reading SQLite columns:** Plain SQLite (no encryption). `journal_mode=WAL`, `synchronous=FULL` on the SQLite side. BlazeDB `baseline` includes AES-256-GCM + PBKDF2 (600k) on cold open. Use condition `encryption_off_requested` (compile flag) for engine-only overhead.\n\n"
        md += "| Condition | Support | Benchmark | BlazeDB (ops/sec) | BlazeDB avg ms | BlazeDB p50 ms | BlazeDB p95 ms | BlazeDB p99 ms | SQLite (ops/sec) | SQLite avg ms | SQLite p50 ms | SQLite p95 ms | SQLite p99 ms | Dataset Size | Notes |\n"
        md += "|-----------|---------|-----------|-------------------|----------------|----------------|----------------|----------------|------------------|---------------|---------------|---------------|---------------|--------------|-------|\n"
        
        for result in results {
            let sqliteOpsStr = result.sqliteOpsPerSec.map { String(format: "%.0f", $0) } ?? "N/A"
            let blazeAvg = result.blazedbAvgMs.map { String(format: "%.3f", $0) } ?? "N/A"
            let blazeP50 = result.blazedbP50Ms.map { String(format: "%.3f", $0) } ?? "N/A"
            let blazeP95 = result.blazedbP95Ms.map { String(format: "%.3f", $0) } ?? "N/A"
            let blazeP99 = result.blazedbP99Ms.map { String(format: "%.3f", $0) } ?? "N/A"
            let sqliteAvg = result.sqliteAvgMs.map { String(format: "%.3f", $0) } ?? "N/A"
            let sqliteP50 = result.sqliteP50Ms.map { String(format: "%.3f", $0) } ?? "N/A"
            let sqliteP95 = result.sqliteP95Ms.map { String(format: "%.3f", $0) } ?? "N/A"
            let sqliteP99 = result.sqliteP99Ms.map { String(format: "%.3f", $0) } ?? "N/A"
            md += "| \(result.condition) | \(result.supportStatus) | \(result.name) | \(String(format: "%.0f", result.blazedbOpsPerSec)) | \(blazeAvg) | \(blazeP50) | \(blazeP95) | \(blazeP99) | \(sqliteOpsStr) | \(sqliteAvg) | \(sqliteP50) | \(sqliteP95) | \(sqliteP99) | \(result.datasetSize) | \(result.notes) |\n"
        }
        
        return md
    }
    
    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(results) {
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        return "{}"
    }
}

// MARK: - Benchmark Implementations

func benchmarkInsertThroughput(datasetSize: Int) -> (blazedbOpsPerSec: Double, blazedbStats: StatsSummary?, sqliteOpsPerSec: Double?, sqliteStats: StatsSummary?) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    // BlazeDB benchmark
    let blazedbURL = tempDir.appendingPathComponent("blazedb_bench.db")
    let blazedbStart = Date()
    var blazedbDurationsMs: [Double] = []
    blazedbDurationsMs.reserveCapacity(datasetSize)
    
    do {
        let db = try openBenchDB(name: "bench", fileURL: blazedbURL)
        
        for i in 0..<datasetSize {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string("Record \(i)")
            ])
            let opStart = Date()
            _ = try db.insert(record)
            blazedbDurationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
        }
        
        try db.persist()
        try db.close()
        
        let blazedbDuration = Date().timeIntervalSince(blazedbStart)
        let blazedbOpsPerSec = Double(datasetSize) / blazedbDuration
        let blazedbStats = summarizeMs(blazedbDurationsMs)
        
        // SQLite benchmark (if available)
        var sqliteOpsPerSec: Double? = nil
        var sqliteDurationsMs: [Double] = []
        sqliteDurationsMs.reserveCapacity(datasetSize)
        
        #if canImport(SQLite3)
        let sqliteURL = tempDir.appendingPathComponent("sqlite_bench.db")
        var sqliteDB: OpaquePointer?
        
        if sqlite3_open(sqliteURL.path, &sqliteDB) == SQLITE_OK {
            sqliteConfigureForBench(sqliteDB)
            sqlite3_exec(sqliteDB, benchSQLiteInsertDDL, nil, nil, nil)
            
            let sqliteStart = Date()
            let insertStmt = "INSERT INTO records (id, index_val, data) VALUES (?, ?, ?)"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(sqliteDB, insertStmt, -1, &statement, nil) == SQLITE_OK {
                sqlite3_exec(sqliteDB, "BEGIN", nil, nil, nil)
                for i in 0..<datasetSize {
                    let opStart = Date()
                    let id = UUID().uuidString
                    sqlite3_bind_text(statement, 1, id, -1, nil)
                    sqlite3_bind_int(statement, 2, Int32(i))
                    sqlite3_bind_text(statement, 3, "Record \(i)", -1, nil)

                    sqlite3_step(statement)
                    sqlite3_reset(statement)
                    sqliteDurationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
                }
                sqlite3_exec(sqliteDB, "COMMIT", nil, nil, nil)
            }

            sqlite3_finalize(statement)
            sqlite3_close(sqliteDB)
            
            let sqliteDuration = Date().timeIntervalSince(sqliteStart)
            sqliteOpsPerSec = Double(datasetSize) / sqliteDuration
        }
        #endif
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
        
        return (
            blazedbOpsPerSec: blazedbOpsPerSec,
            blazedbStats: blazedbStats,
            sqliteOpsPerSec: sqliteOpsPerSec,
            sqliteStats: summarizeMs(sqliteDurationsMs)
        )
    } catch {
        print("BlazeDB benchmark failed: \(error)")
        try? FileManager.default.removeItem(at: tempDir)
        return (blazedbOpsPerSec: 0, blazedbStats: nil, sqliteOpsPerSec: nil, sqliteStats: nil)
    }
}

func benchmarkReadThroughput(datasetSize: Int) -> (blazedbOpsPerSec: Double, blazedbStats: StatsSummary?, sqliteOpsPerSec: Double?, sqliteStats: StatsSummary?) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    // Setup: Insert data first
    let blazedbURL = tempDir.appendingPathComponent("blazedb_read.db")
    var insertedIDs: [UUID] = []
    
    do {
        let db = try openBenchDB(name: "read-bench", fileURL: blazedbURL)
        
        for i in 0..<datasetSize {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string("Record \(i)")
            ])
            let id = try db.insert(record)
            insertedIDs.append(id)
        }
        
        try db.persist()
        try db.close()
        
        // BlazeDB read benchmark
        let reopenedDB = try openBenchDB(name: "read-bench", fileURL: blazedbURL)
        let blazedbStart = Date()
        var blazedbDurationsMs: [Double] = []
        blazedbDurationsMs.reserveCapacity(datasetSize)
        
        for id in insertedIDs {
            let opStart = Date()
            _ = try reopenedDB.fetch(id: id)
            blazedbDurationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
        }
        
        let blazedbDuration = Date().timeIntervalSince(blazedbStart)
        let blazedbOpsPerSec = Double(datasetSize) / blazedbDuration
        let blazedbStats = summarizeMs(blazedbDurationsMs)
        
        try reopenedDB.close()
        
        // SQLite read benchmark (WAL + FULL synchronous, same 1K rows)
        var sqliteOpsPerSec: Double? = nil
        var sqliteDurationsMs: [Double] = []
        sqliteDurationsMs.reserveCapacity(datasetSize)

        #if canImport(SQLite3)
        let sqliteURL = tempDir.appendingPathComponent("sqlite_read.db")
        var sqliteDB: OpaquePointer?
        if sqlite3_open(sqliteURL.path, &sqliteDB) == SQLITE_OK {
            sqliteConfigureForBench(sqliteDB)
            sqlite3_exec(sqliteDB, benchSQLiteInsertDDL, nil, nil, nil)
            var sqliteIDs: [String] = []
            let insertStmt = "INSERT INTO records (id, index_val, data) VALUES (?, ?, ?)"
            var insertStatement: OpaquePointer?
            if sqlite3_prepare_v2(sqliteDB, insertStmt, -1, &insertStatement, nil) == SQLITE_OK {
                sqlite3_exec(sqliteDB, "BEGIN", nil, nil, nil)
                for i in 0..<datasetSize {
                    let id = UUID().uuidString
                    sqliteIDs.append(id)
                    sqlite3_bind_text(insertStatement, 1, id, -1, nil)
                    sqlite3_bind_int(insertStatement, 2, Int32(i))
                    sqlite3_bind_text(insertStatement, 3, "Record \(i)", -1, nil)
                    sqlite3_step(insertStatement)
                    sqlite3_reset(insertStatement)
                }
                sqlite3_exec(sqliteDB, "COMMIT", nil, nil, nil)
            }
            sqlite3_finalize(insertStatement)

            let selectStmt = "SELECT index_val, data FROM records WHERE id = ?"
            var selectStatement: OpaquePointer?
            if sqlite3_prepare_v2(sqliteDB, selectStmt, -1, &selectStatement, nil) == SQLITE_OK {
                let sqliteStart = Date()
                for id in sqliteIDs {
                    let opStart = Date()
                    sqlite3_bind_text(selectStatement, 1, id, -1, nil)
                    _ = sqlite3_step(selectStatement)
                    sqlite3_reset(selectStatement)
                    sqliteDurationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
                }
                let sqliteDuration = Date().timeIntervalSince(sqliteStart)
                sqliteOpsPerSec = Double(datasetSize) / sqliteDuration
            }
            sqlite3_finalize(selectStatement)
            sqlite3_close(sqliteDB)
        }
        #endif
        
        try? FileManager.default.removeItem(at: tempDir)
        
        return (
            blazedbOpsPerSec: blazedbOpsPerSec,
            blazedbStats: blazedbStats,
            sqliteOpsPerSec: sqliteOpsPerSec,
            sqliteStats: summarizeMs(sqliteDurationsMs)
        )
    } catch {
        print("Read benchmark failed: \(error)")
        try? FileManager.default.removeItem(at: tempDir)
        return (blazedbOpsPerSec: 0, blazedbStats: nil, sqliteOpsPerSec: nil, sqliteStats: nil)
    }
}

func benchmarkColdOpen() -> (blazedbOpsPerSec: Double, blazedbStats: StatsSummary?, sqliteOpsPerSec: Double?, sqliteStats: StatsSummary?) {
    let cold = benchmarkBlazeDBOpenCycles(recordCount: 1000, iterations: 10, clearSessionEachOpen: true)
    #if canImport(SQLite3)
    let sqlite = benchmarkSQLiteColdOpen(recordCount: 1000, iterations: 10)
    return (cold.opsPerSec, cold.stats, sqlite.opsPerSec, sqlite.stats)
    #else
    return (cold.opsPerSec, cold.stats, nil, nil)
    #endif
}

func benchmarkWarmReopen() -> (blazedbOpsPerSec: Double, blazedbStats: StatsSummary?, sqliteOpsPerSec: Double?, sqliteStats: StatsSummary?) {
    let warm = benchmarkBlazeDBOpenCycles(recordCount: 1000, iterations: 10, clearSessionEachOpen: false)
    return (warm.opsPerSec, warm.stats, nil, nil)
}

func benchmarkInsertManyThroughput(datasetSize: Int, batchSize: Int = 100) -> (blazedbOpsPerSec: Double, blazedbStats: StatsSummary?, sqliteOpsPerSec: Double?, sqliteStats: StatsSummary?) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let records = (0..<datasetSize).map { i in
        BlazeDataRecord([
            "id": .uuid(UUID()),
            "index": .int(i),
            "data": .string("Batch Record \(i)")
        ])
    }
    let recordBatches = chunked(records, by: batchSize)
    var blazedbBatchDurationsMs: [Double] = []
    blazedbBatchDurationsMs.reserveCapacity(recordBatches.count)

    do {
        let blazedbURL = tempDir.appendingPathComponent("blazedb_insertmany.db")
        let db = try openBenchDB(name: "insertmany-bench", fileURL: blazedbURL)
        let blazedbStart = Date()

        for batch in recordBatches {
            let opStart = Date()
            _ = try db.insertMany(batch)
            blazedbBatchDurationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
        }

        try db.persist()
        try db.close()
        let blazedbDuration = Date().timeIntervalSince(blazedbStart)
        let blazedbOpsPerSec = Double(datasetSize) / blazedbDuration
        let blazedbStats = summarizeMs(blazedbBatchDurationsMs)

        var sqliteOpsPerSec: Double? = nil
        var sqliteBatchDurationsMs: [Double] = []
        sqliteBatchDurationsMs.reserveCapacity(recordBatches.count)

        #if canImport(SQLite3)
        let sqliteURL = tempDir.appendingPathComponent("sqlite_insertmany.db")
        var sqliteDB: OpaquePointer?
        if sqlite3_open(sqliteURL.path, &sqliteDB) == SQLITE_OK {
            sqliteConfigureForBench(sqliteDB)
            sqlite3_exec(sqliteDB, benchSQLiteInsertDDL, nil, nil, nil)
            let insertStmt = "INSERT INTO records (id, index_val, data) VALUES (?, ?, ?)"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(sqliteDB, insertStmt, -1, &statement, nil) == SQLITE_OK {
                let sqliteStart = Date()
                for batch in recordBatches {
                    let batchStart = Date()
                    sqlite3_exec(sqliteDB, "BEGIN", nil, nil, nil)
                    for _ in batch {
                        let id = UUID().uuidString
                        sqlite3_bind_text(statement, 1, id, -1, nil)
                        sqlite3_bind_int(statement, 2, Int32.random(in: 0...Int32.max))
                        sqlite3_bind_text(statement, 3, "Batch Record", -1, nil)
                        sqlite3_step(statement)
                        sqlite3_reset(statement)
                    }
                    sqlite3_exec(sqliteDB, "COMMIT", nil, nil, nil)
                    sqliteBatchDurationsMs.append(Date().timeIntervalSince(batchStart) * 1000.0)
                }
                let sqliteDuration = Date().timeIntervalSince(sqliteStart)
                sqliteOpsPerSec = Double(datasetSize) / sqliteDuration
            }
            sqlite3_finalize(statement)
            sqlite3_close(sqliteDB)
        }
        #endif

        try? FileManager.default.removeItem(at: tempDir)
        return (
            blazedbOpsPerSec: blazedbOpsPerSec,
            blazedbStats: blazedbStats,
            sqliteOpsPerSec: sqliteOpsPerSec,
            sqliteStats: summarizeMs(sqliteBatchDurationsMs)
        )
    } catch {
        print("InsertMany benchmark failed: \(error)")
        try? FileManager.default.removeItem(at: tempDir)
        return (blazedbOpsPerSec: 0, blazedbStats: nil, sqliteOpsPerSec: nil, sqliteStats: nil)
    }
}

func benchmarkInsertManyProfile(
    datasetSize: Int,
    batchSize: Int,
    persistEveryBatch: Bool
) -> (blazedbOpsPerSec: Double, blazedbStats: StatsSummary?, sqliteOpsPerSec: Double?, sqliteStats: StatsSummary?) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let records = (0..<datasetSize).map { i in
        BlazeDataRecord([
            "id": .uuid(UUID()),
            "index": .int(i),
            "data": .string("Batch Record \(i)")
        ])
    }
    let recordBatches = chunked(records, by: batchSize)
    var blazedbBatchDurationsMs: [Double] = []
    blazedbBatchDurationsMs.reserveCapacity(recordBatches.count)

    do {
        let blazedbURL = tempDir.appendingPathComponent("blazedb_insertmany_profile.db")
        let db = try openBenchDB(name: "insertmany-profile-bench", fileURL: blazedbURL)
        let blazedbStart = Date()

        for batch in recordBatches {
            let opStart = Date()
            _ = try db.insertMany(batch)
            if persistEveryBatch {
                try db.persist()
            }
            blazedbBatchDurationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
        }

        if !persistEveryBatch {
            try db.persist()
        }
        try db.close()
        let blazedbDuration = Date().timeIntervalSince(blazedbStart)
        let blazedbOpsPerSec = Double(datasetSize) / blazedbDuration
        let blazedbStats = summarizeMs(blazedbBatchDurationsMs)

        var sqliteOpsPerSec: Double? = nil
        var sqliteBatchDurationsMs: [Double] = []
        sqliteBatchDurationsMs.reserveCapacity(recordBatches.count)

        #if canImport(SQLite3)
        let sqliteURL = tempDir.appendingPathComponent("sqlite_insertmany_profile.db")
        var sqliteDB: OpaquePointer?
        if sqlite3_open(sqliteURL.path, &sqliteDB) == SQLITE_OK {
            sqliteConfigureForBench(sqliteDB)
            sqlite3_exec(sqliteDB, benchSQLiteInsertDDL, nil, nil, nil)
            let insertStmt = "INSERT INTO records (id, index_val, data) VALUES (?, ?, ?)"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(sqliteDB, insertStmt, -1, &statement, nil) == SQLITE_OK {
                let sqliteStart = Date()
                for batch in recordBatches {
                    let batchStart = Date()
                    sqlite3_exec(sqliteDB, "BEGIN", nil, nil, nil)
                    for _ in batch {
                        let id = UUID().uuidString
                        sqlite3_bind_text(statement, 1, id, -1, nil)
                        sqlite3_bind_int(statement, 2, Int32.random(in: 0...Int32.max))
                        sqlite3_bind_text(statement, 3, "Batch Record", -1, nil)
                        sqlite3_step(statement)
                        sqlite3_reset(statement)
                    }
                    sqlite3_exec(sqliteDB, "COMMIT", nil, nil, nil)
                    sqliteBatchDurationsMs.append(Date().timeIntervalSince(batchStart) * 1000.0)
                }
                let sqliteDuration = Date().timeIntervalSince(sqliteStart)
                sqliteOpsPerSec = Double(datasetSize) / sqliteDuration
            }
            sqlite3_finalize(statement)
            sqlite3_close(sqliteDB)
        }
        #endif

        try? FileManager.default.removeItem(at: tempDir)
        return (
            blazedbOpsPerSec: blazedbOpsPerSec,
            blazedbStats: blazedbStats,
            sqliteOpsPerSec: sqliteOpsPerSec,
            sqliteStats: summarizeMs(sqliteBatchDurationsMs)
        )
    } catch {
        print("InsertMany profile benchmark failed: \(error)")
        try? FileManager.default.removeItem(at: tempDir)
        return (blazedbOpsPerSec: 0, blazedbStats: nil, sqliteOpsPerSec: nil, sqliteStats: nil)
    }
}

func benchmarkDeleteManyThroughput(datasetSize: Int, batchSize: Int = 100) -> (blazedbOpsPerSec: Double, blazedbStats: StatsSummary?, sqliteOpsPerSec: Double?, sqliteStats: StatsSummary?) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    do {
        let blazedbURL = tempDir.appendingPathComponent("blazedb_deletemany.db")
        let db = try openBenchDB(name: "deletemany-bench", fileURL: blazedbURL)
        let records = (0..<datasetSize).map { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string("Delete Record \(i)")
            ])
        }
        let ids = try db.insertMany(records)
        try db.persist()
        let idBatches = chunked(ids, by: batchSize)

        var blazedbBatchDurationsMs: [Double] = []
        blazedbBatchDurationsMs.reserveCapacity(idBatches.count)
        let blazedbStart = Date()
        for batch in idBatches {
            let opStart = Date()
            _ = try db.deleteMany(ids: batch)
            blazedbBatchDurationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
        }
        try db.persist()
        try db.close()
        let blazedbDuration = Date().timeIntervalSince(blazedbStart)
        let blazedbOpsPerSec = Double(datasetSize) / blazedbDuration
        let blazedbStats = summarizeMs(blazedbBatchDurationsMs)

        var sqliteOpsPerSec: Double? = nil
        var sqliteBatchDurationsMs: [Double] = []
        sqliteBatchDurationsMs.reserveCapacity(idBatches.count)

        #if canImport(SQLite3)
        let sqliteURL = tempDir.appendingPathComponent("sqlite_deletemany.db")
        var sqliteDB: OpaquePointer?
        if sqlite3_open(sqliteURL.path, &sqliteDB) == SQLITE_OK {
            sqliteConfigureForBench(sqliteDB)
            sqlite3_exec(sqliteDB, benchSQLiteInsertDDL, nil, nil, nil)
            let insertStmt = "INSERT INTO records (id, index_val, data) VALUES (?, ?, ?)"
            var insertStatement: OpaquePointer?
            var sqliteIDs: [String] = []
            if sqlite3_prepare_v2(sqliteDB, insertStmt, -1, &insertStatement, nil) == SQLITE_OK {
                sqlite3_exec(sqliteDB, "BEGIN", nil, nil, nil)
                for i in 0..<datasetSize {
                    let id = UUID().uuidString
                    sqliteIDs.append(id)
                    sqlite3_bind_text(insertStatement, 1, id, -1, nil)
                    sqlite3_bind_int(insertStatement, 2, Int32(i))
                    sqlite3_bind_text(insertStatement, 3, "Delete Record", -1, nil)
                    sqlite3_step(insertStatement)
                    sqlite3_reset(insertStatement)
                }
                sqlite3_exec(sqliteDB, "COMMIT", nil, nil, nil)
            }
            sqlite3_finalize(insertStatement)

            let sqliteIDBatches = chunked(sqliteIDs, by: batchSize)
            let sqliteStart = Date()
            for batch in sqliteIDBatches {
                let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
                let deleteSQL = "DELETE FROM records WHERE id IN (\(placeholders))"
                var deleteStmt: OpaquePointer?
                let batchStart = Date()
                if sqlite3_prepare_v2(sqliteDB, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK {
                    for (idx, id) in batch.enumerated() {
                        sqlite3_bind_text(deleteStmt, Int32(idx + 1), id, -1, nil)
                    }
                    sqlite3_step(deleteStmt)
                }
                sqlite3_finalize(deleteStmt)
                sqliteBatchDurationsMs.append(Date().timeIntervalSince(batchStart) * 1000.0)
            }
            let sqliteDuration = Date().timeIntervalSince(sqliteStart)
            sqliteOpsPerSec = Double(datasetSize) / sqliteDuration
            sqlite3_close(sqliteDB)
        }
        #endif

        try? FileManager.default.removeItem(at: tempDir)
        return (
            blazedbOpsPerSec: blazedbOpsPerSec,
            blazedbStats: blazedbStats,
            sqliteOpsPerSec: sqliteOpsPerSec,
            sqliteStats: summarizeMs(sqliteBatchDurationsMs)
        )
    } catch {
        print("DeleteMany benchmark failed: \(error)")
        try? FileManager.default.removeItem(at: tempDir)
        return (blazedbOpsPerSec: 0, blazedbStats: nil, sqliteOpsPerSec: nil, sqliteStats: nil)
    }
}

func benchmarkDeleteManyProfile(
    datasetSize: Int,
    batchSize: Int,
    persistEveryBatch: Bool
) -> (blazedbOpsPerSec: Double, blazedbStats: StatsSummary?, sqliteOpsPerSec: Double?, sqliteStats: StatsSummary?) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    do {
        let blazedbURL = tempDir.appendingPathComponent("blazedb_deletemany_profile.db")
        let db = try openBenchDB(name: "deletemany-profile-bench", fileURL: blazedbURL)
        let records = (0..<datasetSize).map { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string("Delete Record \(i)")
            ])
        }
        let ids = try db.insertMany(records)
        try db.persist()
        let idBatches = chunked(ids, by: batchSize)

        var blazedbBatchDurationsMs: [Double] = []
        blazedbBatchDurationsMs.reserveCapacity(idBatches.count)
        let blazedbStart = Date()
        for batch in idBatches {
            let opStart = Date()
            _ = try db.deleteMany(ids: batch)
            if persistEveryBatch {
                try db.persist()
            }
            blazedbBatchDurationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
        }
        if !persistEveryBatch {
            try db.persist()
        }
        try db.close()
        let blazedbDuration = Date().timeIntervalSince(blazedbStart)
        let blazedbOpsPerSec = Double(datasetSize) / blazedbDuration
        let blazedbStats = summarizeMs(blazedbBatchDurationsMs)

        var sqliteOpsPerSec: Double? = nil
        var sqliteBatchDurationsMs: [Double] = []
        sqliteBatchDurationsMs.reserveCapacity(idBatches.count)

        #if canImport(SQLite3)
        let sqliteURL = tempDir.appendingPathComponent("sqlite_deletemany_profile.db")
        var sqliteDB: OpaquePointer?
        if sqlite3_open(sqliteURL.path, &sqliteDB) == SQLITE_OK {
            sqliteConfigureForBench(sqliteDB)
            sqlite3_exec(sqliteDB, benchSQLiteInsertDDL, nil, nil, nil)
            let insertStmt = "INSERT INTO records (id, index_val, data) VALUES (?, ?, ?)"
            var insertStatement: OpaquePointer?
            var sqliteIDs: [String] = []
            if sqlite3_prepare_v2(sqliteDB, insertStmt, -1, &insertStatement, nil) == SQLITE_OK {
                sqlite3_exec(sqliteDB, "BEGIN", nil, nil, nil)
                for i in 0..<datasetSize {
                    let id = UUID().uuidString
                    sqliteIDs.append(id)
                    sqlite3_bind_text(insertStatement, 1, id, -1, nil)
                    sqlite3_bind_int(insertStatement, 2, Int32(i))
                    sqlite3_bind_text(insertStatement, 3, "Delete Record", -1, nil)
                    sqlite3_step(insertStatement)
                    sqlite3_reset(insertStatement)
                }
                sqlite3_exec(sqliteDB, "COMMIT", nil, nil, nil)
            }
            sqlite3_finalize(insertStatement)

            let sqliteIDBatches = chunked(sqliteIDs, by: batchSize)
            let sqliteStart = Date()
            for batch in sqliteIDBatches {
                let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
                let deleteSQL = "DELETE FROM records WHERE id IN (\(placeholders))"
                var deleteStmt: OpaquePointer?
                let batchStart = Date()
                if sqlite3_prepare_v2(sqliteDB, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK {
                    for (idx, id) in batch.enumerated() {
                        sqlite3_bind_text(deleteStmt, Int32(idx + 1), id, -1, nil)
                    }
                    sqlite3_step(deleteStmt)
                }
                sqlite3_finalize(deleteStmt)
                sqliteBatchDurationsMs.append(Date().timeIntervalSince(batchStart) * 1000.0)
            }
            let sqliteDuration = Date().timeIntervalSince(sqliteStart)
            sqliteOpsPerSec = Double(datasetSize) / sqliteDuration
            sqlite3_close(sqliteDB)
        }
        #endif

        try? FileManager.default.removeItem(at: tempDir)
        return (
            blazedbOpsPerSec: blazedbOpsPerSec,
            blazedbStats: blazedbStats,
            sqliteOpsPerSec: sqliteOpsPerSec,
            sqliteStats: summarizeMs(sqliteBatchDurationsMs)
        )
    } catch {
        print("DeleteMany profile benchmark failed: \(error)")
        try? FileManager.default.removeItem(at: tempDir)
        return (blazedbOpsPerSec: 0, blazedbStats: nil, sqliteOpsPerSec: nil, sqliteStats: nil)
    }
}

// MARK: - Main

let benchMode = ProcessInfo.processInfo.environment["BLAZEDB_BENCH_MODE"] ?? "throughput"

if benchMode == "open_profile" {
    print("=== BlazeDB Open Profiler ===\n")
    do {
        let recordCount = Int(ProcessInfo.processInfo.environment["BLAZEDB_OPEN_PROFILE_RECORDS"] ?? "") ?? OpenProfiler.defaultRecordCount
        let runs = try OpenProfiler.run(recordCount: recordCount)
        OpenProfiler.printSummary(runs)

        let outDir = ProcessInfo.processInfo.environment["BLAZEDB_OPEN_PROFILE_OUT"]
            ?? "benchmark_results/open_profile"
        let outURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(outDir)
        try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
        let mdPath = outURL.appendingPathComponent("open_profile.md")
        let jsonPath = outURL.appendingPathComponent("open_profile.json")
        try OpenProfiler.markdownReport(runs).write(to: mdPath, atomically: true, encoding: .utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(runs).write(to: jsonPath)
        print("\nSaved:")
        print("  - \(mdPath.path)")
        print("  - \(jsonPath.path)")
    } catch {
        print("Open profile failed: \(error)")
        exit(1)
    }
    exit(0)
}

print("=== BlazeDB Benchmarks ===\n")
print("Running benchmarks...\n")

var suite = BenchmarkSuite()

// Benchmark 1: Insert throughput (small records)
print("1. Insert throughput (1,000 records)...")
let insert1k = benchmarkInsertThroughput(datasetSize: 1000)
suite.run(
    name: "Insert (1K records)",
    datasetSize: 1000,
    blazedbOpsPerSec: insert1k.blazedbOpsPerSec,
    blazedbStats: insert1k.blazedbStats,
    sqliteOpsPerSec: insert1k.sqliteOpsPerSec,
    sqliteStats: insert1k.sqliteStats,
    notes: "Small records, sequential insert"
)

// Benchmark 2: Insert throughput (medium records)
print("2. Insert throughput (10,000 records)...")
let insert10k = benchmarkInsertThroughput(datasetSize: 10000)
suite.run(
    name: "Insert (10K records)",
    datasetSize: 10000,
    blazedbOpsPerSec: insert10k.blazedbOpsPerSec,
    blazedbStats: insert10k.blazedbStats,
    sqliteOpsPerSec: insert10k.sqliteOpsPerSec,
    sqliteStats: insert10k.sqliteStats,
    notes: "Medium records, sequential insert"
)

// Benchmark 3: Read throughput
print("3. Read throughput (1,000 records)...")
let read1k = benchmarkReadThroughput(datasetSize: 1000)
suite.run(
    name: "Read (1K records)",
    datasetSize: 1000,
    blazedbOpsPerSec: read1k.blazedbOpsPerSec,
    blazedbStats: read1k.blazedbStats,
    sqliteOpsPerSec: read1k.sqliteOpsPerSec,
    sqliteStats: read1k.sqliteStats,
    notes: "Indexed reads by UUID"
)

// Benchmark 4: Batch insert throughput
print("4. InsertMany throughput (10,000 records, batch 100)...")
let insertMany10k = benchmarkInsertManyThroughput(datasetSize: 10000, batchSize: 100)
suite.run(
    name: "InsertMany (10K records, batch 100)",
    datasetSize: 10000,
    blazedbOpsPerSec: insertMany10k.blazedbOpsPerSec,
    blazedbStats: insertMany10k.blazedbStats,
    sqliteOpsPerSec: insertMany10k.sqliteOpsPerSec,
    sqliteStats: insertMany10k.sqliteStats,
    notes: "Throughput in records/sec; latency stats are per insertMany(batch)"
)

// Benchmark 5: Batch delete throughput
print("5. DeleteMany throughput (10,000 records, batch 100)...")
let deleteMany10k = benchmarkDeleteManyThroughput(datasetSize: 10000, batchSize: 100)
suite.run(
    name: "DeleteMany (10K records, batch 100)",
    datasetSize: 10000,
    blazedbOpsPerSec: deleteMany10k.blazedbOpsPerSec,
    blazedbStats: deleteMany10k.blazedbStats,
    sqliteOpsPerSec: deleteMany10k.sqliteOpsPerSec,
    sqliteStats: deleteMany10k.sqliteStats,
    notes: "Throughput in records/sec; latency stats are per deleteMany(batch)"
)

// Benchmark 6: InsertMany durable profile
print("6. InsertMany durable profile (10,000 records, batch 100, persist per batch)...")
let insertManyDurable = benchmarkInsertManyProfile(datasetSize: 10000, batchSize: 100, persistEveryBatch: true)
suite.run(
    name: "InsertMany (durable profile, batch 100)",
    datasetSize: 10000,
    blazedbOpsPerSec: insertManyDurable.blazedbOpsPerSec,
    blazedbStats: insertManyDurable.blazedbStats,
    sqliteOpsPerSec: insertManyDurable.sqliteOpsPerSec,
    sqliteStats: insertManyDurable.sqliteStats,
    notes: "Persist after every batch; throughput in records/sec; latency is per insertMany(batch)+persist"
)

// Benchmark 7: InsertMany max-throughput profile
print("7. InsertMany max-throughput profile (10,000 records, batch 1000, single persist)...")
let insertManyMax = benchmarkInsertManyProfile(datasetSize: 10000, batchSize: 1000, persistEveryBatch: false)
suite.run(
    name: "InsertMany (max profile, batch 1000)",
    datasetSize: 10000,
    blazedbOpsPerSec: insertManyMax.blazedbOpsPerSec,
    blazedbStats: insertManyMax.blazedbStats,
    sqliteOpsPerSec: insertManyMax.sqliteOpsPerSec,
    sqliteStats: insertManyMax.sqliteStats,
    notes: "Single persist at end; larger batches for peak throughput; latency is per insertMany(batch)"
)

// Benchmark 8: DeleteMany durable profile
print("8. DeleteMany durable profile (10,000 records, batch 100, persist per batch)...")
let deleteManyDurable = benchmarkDeleteManyProfile(datasetSize: 10000, batchSize: 100, persistEveryBatch: true)
suite.run(
    name: "DeleteMany (durable profile, batch 100)",
    datasetSize: 10000,
    blazedbOpsPerSec: deleteManyDurable.blazedbOpsPerSec,
    blazedbStats: deleteManyDurable.blazedbStats,
    sqliteOpsPerSec: deleteManyDurable.sqliteOpsPerSec,
    sqliteStats: deleteManyDurable.sqliteStats,
    notes: "Persist after every batch; throughput in records/sec; latency is per deleteMany(batch)+persist"
)

// Benchmark 9: DeleteMany max-throughput profile
print("9. DeleteMany max-throughput profile (10,000 records, batch 1000, single persist)...")
let deleteManyMax = benchmarkDeleteManyProfile(datasetSize: 10000, batchSize: 1000, persistEveryBatch: false)
suite.run(
    name: "DeleteMany (max profile, batch 1000)",
    datasetSize: 10000,
    blazedbOpsPerSec: deleteManyMax.blazedbOpsPerSec,
    blazedbStats: deleteManyMax.blazedbStats,
    sqliteOpsPerSec: deleteManyMax.sqliteOpsPerSec,
    sqliteStats: deleteManyMax.sqliteStats,
    notes: "Single persist at end; larger batches for peak throughput; latency is per deleteMany(batch)"
)

// Benchmark 10: Cold open (PBKDF2 every time)
print("10. Cold open (session cleared each reopen)...")
let coldOpen = benchmarkColdOpen()
suite.run(
    name: "Cold open (PBKDF2 each reopen)",
    datasetSize: 1000,
    blazedbOpsPerSec: coldOpen.blazedbOpsPerSec,
    blazedbStats: coldOpen.blazedbStats,
    sqliteOpsPerSec: coldOpen.sqliteOpsPerSec,
    sqliteStats: coldOpen.sqliteStats,
    notes: "10 cycles; BlazeDB clears session before each open (600k PBKDF2). SQLite: open+COUNT (WAL, no encryption)"
)

// Benchmark 11: Warm reopen (process session cache)
print("11. Warm reopen (session cache)...")
let warmOpen = benchmarkWarmReopen()
suite.run(
    name: "Warm reopen (session cache)",
    datasetSize: 1000,
    blazedbOpsPerSec: warmOpen.blazedbOpsPerSec,
    blazedbStats: warmOpen.blazedbStats,
    sqliteOpsPerSec: warmOpen.sqliteOpsPerSec,
    sqliteStats: warmOpen.sqliteStats,
            notes: "10 close/reopen cycles without clearSessionKeys(); BlazeDB skips PBKDF2 when session valid. SQLite N/A (no session concept)"
)

print("\n=== Benchmark Results ===\n")
print(suite.toMarkdown())

// Save results
let markdownOut = ProcessInfo.processInfo.environment["BLAZEDB_BENCH_RESULTS_MD"] ?? "Docs/Benchmarks/RESULTS.md"
let jsonOut = ProcessInfo.processInfo.environment["BLAZEDB_BENCH_RESULTS_JSON"] ?? "Docs/Benchmarks/results.json"
let markdownFile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(markdownOut)
let jsonFile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(jsonOut)

try? FileManager.default.createDirectory(at: markdownFile.deletingLastPathComponent(), withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: jsonFile.deletingLastPathComponent(), withIntermediateDirectories: true)

try? suite.toMarkdown().write(to: markdownFile, atomically: true, encoding: .utf8)
try? suite.toJSON().write(to: jsonFile, atomically: true, encoding: .utf8)

print("\nResults saved to:")
print("  - \(markdownFile.path)")
print("  - \(jsonFile.path)")
