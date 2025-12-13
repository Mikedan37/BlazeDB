//
//  PerformanceBenchmarks.swift
//  BlazeDBTests
//
//  Performance Baselines: Microbenchmarks for insert, query, spatial, vector,
//  ordering, RLS filters, lazy decode, query planner decisions.
//  Tests only run in debug mode, never block CI pipelines.
//  Output baseline JSON to .build/test-metrics/
//
//  Created: 2025-01-XX
//

import XCTest
@testable import BlazeDB
import Foundation

final class PerformanceBenchmarks: XCTestCase {
    
    var db: BlazeDBClient!
    var tempURL: URL!
    var metricsDir: URL!
    
    override func setUp() {
        super.setUp()
        
        // Only run in debug mode
        #if !DEBUG
        XCTSkip("Performance benchmarks only run in DEBUG mode")
        #endif
        
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerformanceBench-\(testID).blazedb")
        
        // Clean up any leftover files
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            if !FileManager.default.fileExists(atPath: tempURL.path) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        do {
            db = try BlazeDBClient(name: "perf_bench_test_\(testID)", fileURL: tempURL, password: "PerformanceBenchmarkTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
        
        // Create metrics directory
        let buildDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build")
        metricsDir = buildDir.appendingPathComponent("test-metrics")
        try? FileManager.default.createDirectory(at: metricsDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Benchmark Helpers
    
    private func measure(name: String, iterations: Int = 1, block: () throws -> Void) rethrows -> (time: Double, throughput: Double?) {
        var totalTime: Double = 0
        
        for _ in 0..<iterations {
            let start = Date()
            try block()
            totalTime += Date().timeIntervalSince(start)
        }
        
        let avgTime = totalTime / Double(iterations)
        let throughput = iterations > 1 ? Double(iterations) / totalTime : nil
        
        return (avgTime, throughput)
    }
    
    private func saveMetric(name: String, time: Double, throughput: Double?, metadata: [String: Any] = [:]) {
        var metric: [String: Any] = [
            "name": name,
            "time_ms": time * 1000,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let throughput = throughput {
            metric["throughput_ops_per_sec"] = throughput
        }
        
        for (key, value) in metadata {
            metric[key] = value
        }
        
        // Save to JSON file
        let filename = "\(name.replacingOccurrences(of: " ", with: "_")).json"
        let fileURL = metricsDir.appendingPathComponent(filename)
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: metric, options: .prettyPrinted) {
            try? jsonData.write(to: fileURL)
        }
    }
    
    // MARK: - Insert Benchmarks
    
    func testBenchmark_Insert_1000() throws {
        print("\n📊 BENCHMARK: Insert 1,000 records (using insertMany)")
        
        let (time, throughput) = try measure(name: "Insert_1000", iterations: 1) {
            let records = (0..<1000).map { i in
                BlazeDataRecord([
                    "id": .uuid(UUID()),
                    "index": .int(i),
                    "name": .string("Record \(i)")
                ])
            }
            _ = try db.insertMany(records)
        }
        
        print("  Time: \(String(format: "%.3f", time * 1000))ms")
        if let throughput = throughput {
            print("  Throughput: \(String(format: "%.0f", throughput)) ops/sec")
        }
        
        saveMetric(name: "Insert_1000", time: time, throughput: throughput)
    }
    
    // MARK: - Query Benchmarks
    
    func testBenchmark_Query_Indexed() throws {
        print("\n📊 BENCHMARK: Indexed Query")
        
        // Pre-populate
        let collection = db.collection as! DynamicCollection
        try collection.createIndex(on: "status")
        
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "active" : "inactive")
            ])
        }
        _ = try db.insertMany(records)
        
        let (time, _) = try measure(name: "Query_Indexed", iterations: 10) {
            _ = try db.query()
                .where("status", equals: .string("active"))
                .execute()
        }
        
        print("  Time: \(String(format: "%.3f", time * 1000))ms (avg over 10 runs)")
        
        saveMetric(name: "Query_Indexed", time: time, throughput: nil, metadata: ["record_count": 1000])
    }
    
    // MARK: - Spatial Benchmarks
    
    func testBenchmark_Spatial_Query() throws {
        print("\n📊 BENCHMARK: Spatial Query")
        
        // Enable spatial index
        try db.enableSpatialIndex(on: "lat", lonField: "lon")
        
        // Pre-populate
        let records = (0..<500).map { i in
            let lat = 37.7749 + Double.random(in: -0.1...0.1)
            let lon = -122.4194 + Double.random(in: -0.1...0.1)
            
            return BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "lat": .double(lat),
                "lon": .double(lon)
            ])
        }
        _ = try db.insertMany(records)
        
        let (time, _) = try measure(name: "Spatial_Query", iterations: 10) {
            _ = try db.query()
                .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
                .execute()
        }
        
        print("  Time: \(String(format: "%.3f", time * 1000))ms (avg over 10 runs)")
        
        saveMetric(name: "Spatial_Query", time: time, throughput: nil, metadata: ["record_count": 500])
    }
    
    // MARK: - Vector Benchmarks
    
    func testBenchmark_Vector_Query() throws {
        print("\n📊 BENCHMARK: Vector Query")
        
        // Enable vector index
        try db.enableVectorIndex(fieldName: "embedding")
        
        // Pre-populate
        let records = (0..<200).map { i in
            let vector: VectorEmbedding = (0..<128).map { _ in Float.random(in: -1...1) }
            let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
            
            return BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "embedding": .data(vectorData)
            ])
        }
        _ = try db.insertMany(records)
        
        let queryVector: VectorEmbedding = (0..<128).map { _ in Float.random(in: -1...1) }
        
        let (time, _) = try measure(name: "Vector_Query", iterations: 10) {
            _ = try db.query()
                .vectorNearest(field: "embedding", to: queryVector, limit: 10)
                .execute()
        }
        
        print("  Time: \(String(format: "%.3f", time * 1000))ms (avg over 10 runs)")
        
        saveMetric(name: "Vector_Query", time: time, throughput: nil, metadata: ["record_count": 200, "vector_dim": 128])
    }
    
    // MARK: - Ordering Benchmarks
    
    func testBenchmark_Ordering_Move() throws {
        print("\n📊 BENCHMARK: Ordering Move")
        
        // Enable ordering
        try db.enableOrdering(fieldName: "orderingIndex")
        
        // Pre-populate
        let records = (0..<100).map { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "orderingIndex": .double(Double(i) * 10.0)
            ])
        }
        let ids = try db.insertMany(records)
        
        let (time, _) = try measure(name: "Ordering_Move", iterations: 10) {
            if ids.count >= 2 {
                try db.moveBefore(recordId: ids[1], beforeId: ids[0])
                try db.moveAfter(recordId: ids[1], afterId: ids[0]) // Move back
            }
        }
        
        print("  Time: \(String(format: "%.3f", time * 1000))ms (avg over 10 runs)")
        
        saveMetric(name: "Ordering_Move", time: time, throughput: nil, metadata: ["record_count": 100])
    }
    
    // MARK: - RLS Benchmarks
    
    func testBenchmark_RLS_Filter() throws {
        print("\n📊 BENCHMARK: RLS Filter")
        
        // Note: RLS implementation would need to be checked
        // This is a placeholder for when RLS is fully integrated
        
        // Pre-populate
        let records = (0..<500).map { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "userId": .string("user\(i % 10)")
            ])
        }
        _ = try db.insertMany(records)
        
        let (time, _) = try measure(name: "RLS_Filter", iterations: 10) {
            _ = try db.query()
                .where("userId", equals: .string("user1"))
                .execute()
        }
        
        print("  Time: \(String(format: "%.3f", time * 1000))ms (avg over 10 runs)")
        
        saveMetric(name: "RLS_Filter", time: time, throughput: nil, metadata: ["record_count": 500])
    }
    
    // MARK: - Lazy Decode Benchmarks
    
    func testBenchmark_LazyDecode_Projection() throws {
        print("\n📊 BENCHMARK: Lazy Decode with Projection")
        
        // Enable lazy decoding
        try db.enableLazyDecoding()
        
        // Pre-populate with large fields
        let records = (0..<200).map { i in
            let largeData = Data(repeating: UInt8(i), count: 10_000)
            return BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "name": .string("Record \(i)"),
                "largeData": .data(largeData)
            ])
        }
        _ = try db.insertMany(records)
        
        let (time, _) = try measure(name: "LazyDecode_Projection", iterations: 10) {
            _ = try db.query()
                .project("id", "name")
                .execute()
        }
        
        print("  Time: \(String(format: "%.3f", time * 1000))ms (avg over 10 runs)")
        
        saveMetric(name: "LazyDecode_Projection", time: time, throughput: nil, metadata: ["record_count": 200, "large_field_size": 10000])
    }
    
    // MARK: - Query Planner Benchmarks
    
    func testBenchmark_QueryPlanner_Decision() throws {
        print("\n📊 BENCHMARK: Query Planner Decision")
        
        // Create multiple indexes
        let collection = db.collection as! DynamicCollection
        try collection.createIndex(on: "status")
        try collection.enableSearch(on: ["title"])
        try db.enableSpatialIndex(on: "lat", lonField: "lon")
        
        // Pre-populate
        let records = (0..<300).map { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "active" : "inactive"),
                "title": .string("Record \(i)"),
                "lat": .double(37.7749 + Double.random(in: -0.1...0.1)),
                "lon": .double(-122.4194 + Double.random(in: -0.1...0.1))
            ])
        }
        _ = try db.insertMany(records)
        
        let (time, _) = try measure(name: "QueryPlanner_Decision", iterations: 10) {
            // Complex query that planner needs to optimize
            _ = try db.query()
                .where("status", equals: .string("active"))
                .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
                .execute()
        }
        
        print("  Time: \(String(format: "%.3f", time * 1000))ms (avg over 10 runs)")
        
        saveMetric(name: "QueryPlanner_Decision", time: time, throughput: nil, metadata: ["record_count": 300, "indexes": 3])
    }
}

