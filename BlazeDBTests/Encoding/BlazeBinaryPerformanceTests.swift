//
//  BlazeBinaryPerformanceTests.swift
//  BlazeDBTests
//
//  Performance benchmarks: BlazeBinary vs JSON
//

import XCTest
@testable import BlazeDBCore

final class BlazeBinaryPerformanceTests: XCTestCase {
    
    // MARK: - Encoding Performance
    
    func testPerformance_Encode_BlazeBinary() {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Performance test record"),
            "description": .string("This is a test description for benchmarking"),
            "priority": .int(3),
            "status": .string("open"),
            "createdAt": .date(Date()),
            "userId": .uuid(UUID())
        ])
        
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<1000 {
                _ = try? BlazeBinaryEncoder.encode(record)
            }
        }
    }
    
    func testPerformance_Encode_JSON() {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Performance test record"),
            "description": .string("This is a test description for benchmarking"),
            "priority": .int(3),
            "status": .string("open"),
            "createdAt": .date(Date()),
            "userId": .uuid(UUID())
        ])
        
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<1000 {
                _ = try? JSONEncoder().encode(record)
            }
        }
    }
    
    // MARK: - Decoding Performance
    
    func testPerformance_Decode_BlazeBinary() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Performance test"),
            "value": .int(42)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<1000 {
                _ = try? BlazeBinaryDecoder.decode(encoded)
            }
        }
    }
    
    func testPerformance_Decode_JSON() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Performance test"),
            "value": .int(42)
        ])
        
        let encoded = try JSONEncoder().encode(record)
        
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<1000 {
                _ = try? JSONDecoder().decode(BlazeDataRecord.self, from: encoded)
            }
        }
    }
    
    // MARK: - Size Benchmarks
    
    func testBenchmark_StorageSize_SimpleRecord() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Test"),
            "value": .int(42)
        ])
        
        let jsonSize = try JSONEncoder().encode(record).count
        let binarySize = try BlazeBinaryEncoder.encode(record).count
        
        let savings = Double(jsonSize - binarySize) / Double(jsonSize) * 100
        
        print("Simple record:")
        print("  JSON: \(jsonSize) bytes")
        print("  BlazeBinary: \(binarySize) bytes")
        print("  Savings: \(String(format: "%.1f", savings))%")
        
        XCTAssertGreaterThan(savings, 40, "Should save > 40% for simple records")
    }
    
    func testBenchmark_StorageSize_ComplexRecord() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Complex bug report"),
            "description": .string("This is a detailed description of a complex bug that affects multiple users across different platforms."),
            "priority": .int(5),
            "status": .string("open"),
            "createdAt": .date(Date()),
            "updatedAt": .date(Date()),
            "userId": .uuid(UUID()),
            "teamId": .uuid(UUID()),
            "assignedTo": .uuid(UUID()),
            "tags": .array([.string("critical"), .string("crash"), .string("ios"), .string("p0")]),
            "metadata": .dictionary([
                "version": .string("1.0.3"),
                "platform": .string("iOS 16"),
                "deviceModel": .string("iPhone 14 Pro"),
                "osVersion": .string("16.5"),
                "locale": .string("en_US")
            ])
        ])
        
        let jsonSize = try JSONEncoder().encode(record).count
        let binarySize = try BlazeBinaryEncoder.encode(record).count
        
        let savings = Double(jsonSize - binarySize) / Double(jsonSize) * 100
        
        print("Complex record:")
        print("  JSON: \(jsonSize) bytes")
        print("  BlazeBinary: \(binarySize) bytes")
        print("  Savings: \(String(format: "%.1f", savings))%")
        
        // ✅ Complex nested records have lower savings (nested structures already compact in JSON)
        // Simple records: ~55-60% savings
        // Complex records: ~35-45% savings (still excellent!)
        XCTAssertGreaterThan(savings, 35, "Should save > 35% for complex nested records")
    }
    
    func testBenchmark_StorageSize_10kRecords() throws {
        print("\n📊 BENCHMARK: 10,000 records storage comparison")
        
        var jsonTotal = 0
        var binaryTotal = 0
        
        for i in 0..<10000 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "title": .string("Bug #\(i)"),
                "priority": .int(i % 5),
                "status": .string(["open", "closed", "in_progress"][i % 3]),
                "createdAt": .date(Date())
            ])
            
            jsonTotal += try JSONEncoder().encode(record).count
            binaryTotal += try BlazeBinaryEncoder.encode(record).count
        }
        
        let savings = Double(jsonTotal - binaryTotal) / Double(jsonTotal) * 100
        
        print("  JSON total: \(jsonTotal / 1024) KB")
        print("  BlazeBinary total: \(binaryTotal / 1024) KB")
        print("  Savings: \(String(format: "%.1f", savings))%")
        print("  Saved: \((jsonTotal - binaryTotal) / 1024) KB")
        
        XCTAssertGreaterThan(savings, 48, "Should save > 48% for typical BlazeDB records")
    }
    
    // MARK: - Throughput Tests
    
    func testPerformance_EncodeThroughput() {
        print("\n⚡ BENCHMARK: Encoding throughput")
        
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i),
                "data": .string("Record \(i)")
            ])
        }
        
        let start = Date()
        for record in records {
            _ = try? BlazeBinaryEncoder.encode(record)
        }
        let duration = Date().timeIntervalSince(start)
        
        let throughput = Double(records.count) / duration
        
        print("  Encoded \(records.count) records in \(String(format: "%.3f", duration))s")
        print("  Throughput: \(String(format: "%.0f", throughput)) records/sec")
        
        XCTAssertLessThan(duration, 0.150, "Should encode 1K records in < 150ms")
    }
    
    func testPerformance_DecodeThroughput() throws {
        print("\n⚡ BENCHMARK: Decoding throughput")
        
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i)
            ])
        }
        
        let encoded = try records.map { try BlazeBinaryEncoder.encode($0) }
        
        let start = Date()
        for data in encoded {
            _ = try? BlazeBinaryDecoder.decode(data)
        }
        let duration = Date().timeIntervalSince(start)
        
        let throughput = Double(records.count) / duration
        
        print("  Decoded \(records.count) records in \(String(format: "%.3f", duration))s")
        print("  Throughput: \(String(format: "%.0f", throughput)) records/sec")
        
        XCTAssertLessThan(duration, 0.130, "Should decode 1K records in < 130ms")
    }
}

