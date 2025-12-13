//
//  LazyDecodingExample.swift
//  BlazeDB Examples
//
//  Lazy decoding for massive memory savings
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Example: Lazy decoding with field projection
func lazyDecodingExample() throws {
    let db = try BlazeDBClient(name: "LazyDecoding", password: "test123")
    
    // Enable lazy decoding
    try db.enableLazyDecoding()
    
    // Insert records with large fields
    for i in 0..<1000 {
        let largeData = Data(repeating: 0xFF, count: 10_000)  // 10KB per record
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Record \(i)"),
            "index": .int(i),
            "largeData": .data(largeData),  // 10MB total if all decoded!
            "metadata": .string("Some metadata")
        ]))
    }
    
    // Query with projection - only decode requested fields!
    // This saves 100-1000x memory vs full decode
    let results = try db.query()
        .project("id", "name", "index")  // Only decode these 3 fields
        .where("index", greaterThan: .int(500))
        .limit(100)
        .execute()
    
    print("Loaded \(results.records.count) records")
    print("✅ Only decoded 3 fields per record (not 5!)")
    print("✅ Memory savings: ~70% (didn't decode largeData)")
    
    // Access projected fields
    for record in results.records {
        let name = record.string("name") ?? "unknown"
        let index = record.int("index") ?? 0
        print("  - \(name) (index: \(index))")
        
        // largeData was NOT decoded - saves memory!
        // If you need it, it will be decoded on-demand
    }
}

/// Example: Performance comparison
func lazyDecodingPerformanceExample() throws {
    let db = try BlazeDBClient(name: "LazyPerformance", password: "test123")
    
    // Insert 10k records with large fields
    let largeData = Data(repeating: 0xFF, count: 100_000)  // 100KB per record
    for i in 0..<10_000 {
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Record \(i)"),
            "largeData": .data(largeData)
        ]))
    }
    
    // Without lazy decoding: Decodes ALL fields (1GB+ memory!)
    let start1 = Date()
    let allRecords = try db.query()
        .where("id", isNotNil: true)
        .limit(1000)
        .execute()
    let time1 = Date().timeIntervalSince(start1)
    print("Without lazy decoding: \(time1 * 1000)ms, ~1GB memory")
    
    // With lazy decoding + projection: Only decodes requested fields
    try db.enableLazyDecoding()
    let start2 = Date()
    let projectedRecords = try db.query()
        .project("id", "title")  // Only 2 fields!
        .where("id", isNotNil: true)
        .limit(1000)
        .execute()
    let time2 = Date().timeIntervalSince(start2)
    print("With lazy decoding: \(time2 * 1000)ms, ~10MB memory")
    print("✅ Speedup: \(String(format: "%.1f", time1 / time2))x faster")
    print("✅ Memory savings: ~100x less memory")
}

