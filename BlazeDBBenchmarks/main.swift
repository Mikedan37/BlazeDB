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
    let blazedb: Double  // operations per second
    let sqlite: Double?  // optional if SQLite not available
    let datasetSize: Int
    let notes: String
}

struct BenchmarkSuite {
    var results: [BenchmarkResult] = []
    
    mutating func run(name: String, datasetSize: Int, blazedbOps: Double, sqliteOps: Double? = nil, notes: String = "") {
        results.append(BenchmarkResult(
            name: name,
            blazedb: blazedbOps,
            sqlite: sqliteOps,
            datasetSize: datasetSize,
            notes: notes
        ))
    }
    
    func toMarkdown() -> String {
        var md = "# BlazeDB Benchmarks\n\n"
        md += "**Date:** \(Date().formatted(date: .abbreviated, time: .shortened))\n\n"
        md += "| Benchmark | BlazeDB (ops/sec) | SQLite (ops/sec) | Dataset Size | Notes |\n"
        md += "|-----------|-------------------|------------------|--------------|-------|\n"
        
        for result in results {
            let sqliteStr = result.sqlite.map { String(format: "%.0f", $0) } ?? "N/A"
            md += "| \(result.name) | \(String(format: "%.0f", result.blazedb)) | \(sqliteStr) | \(result.datasetSize) | \(result.notes) |\n"
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

func benchmarkInsertThroughput(datasetSize: Int) -> (blazedb: Double, sqlite: Double?) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    // BlazeDB benchmark
    let blazedbURL = tempDir.appendingPathComponent("blazedb_bench.db")
    let blazedbStart = Date()
    
    do {
        let db = try BlazeDBClient(name: "bench", fileURL: blazedbURL, password: "bench-password")
        
        for i in 0..<datasetSize {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string("Record \(i)")
            ])
            _ = try db.insert(record)
        }
        
        try db.persist()
        try db.close()
        
        let blazedbDuration = Date().timeIntervalSince(blazedbStart)
        let blazedbOpsPerSec = Double(datasetSize) / blazedbDuration
        
        // SQLite benchmark (if available)
        var sqliteOpsPerSec: Double? = nil
        
        #if canImport(SQLite3)
        let sqliteURL = tempDir.appendingPathComponent("sqlite_bench.db")
        var sqliteDB: OpaquePointer?
        
        if sqlite3_open(sqliteURL.path, &sqliteDB) == SQLITE_OK {
            sqlite3_exec(sqliteDB, "CREATE TABLE IF NOT EXISTS records (id TEXT PRIMARY KEY, index_val INTEGER, data TEXT)", nil, nil, nil)
            
            let sqliteStart = Date()
            let insertStmt = "INSERT INTO records (id, index_val, data) VALUES (?, ?, ?)"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(sqliteDB, insertStmt, -1, &statement, nil) == SQLITE_OK {
                for i in 0..<datasetSize {
                    let id = UUID().uuidString
                    sqlite3_bind_text(statement, 1, id, -1, nil)
                    sqlite3_bind_int(statement, 2, Int32(i))
                    sqlite3_bind_text(statement, 3, "Record \(i)", -1, nil)
                    
                    sqlite3_step(statement)
                    sqlite3_reset(statement)
                }
            }
            
            sqlite3_finalize(statement)
            sqlite3_close(sqliteDB)
            
            let sqliteDuration = Date().timeIntervalSince(sqliteStart)
            sqliteOpsPerSec = Double(datasetSize) / sqliteDuration
        }
        #endif
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
        
        return (blazedb: blazedbOpsPerSec, sqlite: sqliteOpsPerSec)
    } catch {
        print("BlazeDB benchmark failed: \(error)")
        try? FileManager.default.removeItem(at: tempDir)
        return (blazedb: 0, sqlite: nil)
    }
}

func benchmarkReadThroughput(datasetSize: Int) -> (blazedb: Double, sqlite: Double?) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    // Setup: Insert data first
    let blazedbURL = tempDir.appendingPathComponent("blazedb_read.db")
    var insertedIDs: [UUID] = []
    
    do {
        let db = try BlazeDBClient(name: "read-bench", fileURL: blazedbURL, password: "bench-password")
        
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
        let reopenedDB = try BlazeDBClient(name: "read-bench", fileURL: blazedbURL, password: "bench-password")
        let blazedbStart = Date()
        
        for id in insertedIDs {
            _ = try reopenedDB.fetch(id: id)
        }
        
        let blazedbDuration = Date().timeIntervalSince(blazedbStart)
        let blazedbOpsPerSec = Double(datasetSize) / blazedbDuration
        
        try reopenedDB.close()
        
        // SQLite read benchmark (if available)
        let sqliteOpsPerSec: Double? = nil
        
        #if canImport(SQLite3)
        // SQLite setup would go here
        // For now, skip SQLite read benchmark
        #endif
        
        try? FileManager.default.removeItem(at: tempDir)
        
        return (blazedb: blazedbOpsPerSec, sqlite: sqliteOpsPerSec)
    } catch {
        print("Read benchmark failed: \(error)")
        try? FileManager.default.removeItem(at: tempDir)
        return (blazedb: 0, sqlite: nil)
    }
}

func benchmarkColdOpen() -> (blazedb: Double, sqlite: Double?) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    // Setup: Create database with data
    let blazedbURL = tempDir.appendingPathComponent("cold_open.db")
    
    do {
        let db = try BlazeDBClient(name: "cold-open", fileURL: blazedbURL, password: "bench-password")
        
        // Insert some data
        for i in 0..<1000 {
            let record = BlazeDataRecord(["index": .int(i), "data": .string("Record \(i)")])
            _ = try db.insert(record)
        }
        
        try db.persist()
        try db.close()
        
        // BlazeDB cold open benchmark
        var openTimes: [TimeInterval] = []
        
        for _ in 0..<10 {
            let start = Date()
            let db = try BlazeDBClient(name: "cold-open", fileURL: blazedbURL, password: "bench-password")
            let duration = Date().timeIntervalSince(start)
            openTimes.append(duration)
            try db.close()
        }
        
        let avgOpenTime = openTimes.reduce(0, +) / Double(openTimes.count)
        let opensPerSec = 1.0 / avgOpenTime
        
        try? FileManager.default.removeItem(at: tempDir)
        
        return (blazedb: opensPerSec, sqlite: nil)
    } catch {
        print("Cold open benchmark failed: \(error)")
        try? FileManager.default.removeItem(at: tempDir)
        return (blazedb: 0, sqlite: nil)
    }
}

// MARK: - Main

print("=== BlazeDB Benchmarks ===\n")
print("Running benchmarks...\n")

var suite = BenchmarkSuite()

// Benchmark 1: Insert throughput (small records)
print("1. Insert throughput (1,000 records)...")
let insert1k = benchmarkInsertThroughput(datasetSize: 1000)
suite.run(
    name: "Insert (1K records)",
    datasetSize: 1000,
    blazedbOps: insert1k.blazedb,
    sqliteOps: insert1k.sqlite,
    notes: "Small records, sequential insert"
)

// Benchmark 2: Insert throughput (medium records)
print("2. Insert throughput (10,000 records)...")
let insert10k = benchmarkInsertThroughput(datasetSize: 10000)
suite.run(
    name: "Insert (10K records)",
    datasetSize: 10000,
    blazedbOps: insert10k.blazedb,
    sqliteOps: insert10k.sqlite,
    notes: "Medium records, sequential insert"
)

// Benchmark 3: Read throughput
print("3. Read throughput (1,000 records)...")
let read1k = benchmarkReadThroughput(datasetSize: 1000)
suite.run(
    name: "Read (1K records)",
    datasetSize: 1000,
    blazedbOps: read1k.blazedb,
    sqliteOps: read1k.sqlite,
    notes: "Indexed reads by UUID"
)

// Benchmark 4: Cold open
print("4. Cold open time...")
let coldOpen = benchmarkColdOpen()
suite.run(
    name: "Cold open",
    datasetSize: 1000,
    blazedbOps: coldOpen.blazedb,
    sqliteOps: coldOpen.sqlite,
    notes: "Average of 10 opens (opens/sec)"
)

print("\n=== Benchmark Results ===\n")
print(suite.toMarkdown())

// Save results
let benchmarksDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Docs/Benchmarks")

try? FileManager.default.createDirectory(at: benchmarksDir, withIntermediateDirectories: true)

let markdownFile = benchmarksDir.appendingPathComponent("RESULTS.md")
let jsonFile = benchmarksDir.appendingPathComponent("results.json")

try? suite.toMarkdown().write(to: markdownFile, atomically: true, encoding: .utf8)
try? suite.toJSON().write(to: jsonFile, atomically: true, encoding: .utf8)

print("\nResults saved to:")
print("  - \(markdownFile.path)")
print("  - \(jsonFile.path)")
