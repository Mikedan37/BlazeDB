//
//  BlazeBinaryFuzzTests.swift
//  BlazeDBTests
//
//  Deterministic fuzz testing for BlazeBinary codec with dual-codec validation
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class BlazeBinaryFuzzTests: XCTestCase {
    
    // Fixed seed for deterministic fuzz testing
    // This ensures tests are reproducible and both codecs see identical inputs
    private var rng: FuzzTestRNG!
    
    override func setUp() {
        super.setUp()
        // Use fixed seed for deterministic testing
        rng = FuzzTestRNG(seed: 42)
    }
    
    func testFuzz_RandomRecords() throws {
        // Deterministic fuzz: 1000 records with fixed seed
        for i in 0..<1000 {
            let record = generateRandomRecord(seed: UInt64(i))
            
            // Dual-codec validation for every random record
            try assertCodecsEqual(record)
        }
    }
    
    func testFuzz_RandomFieldNames() throws {
        // Deterministic fuzz: 100 records with fixed seed
        for i in 0..<100 {
            var storage: [String: BlazeDocumentField] = [:]
            
            // Generate random field names using seeded RNG
            for j in 0..<10 {
                let seed = UInt64(i * 100 + j)
                let length = deterministicRandom(in: 1...50, seed: seed)
                let fieldName = generateRandomString(length: length, seed: seed)
                let value = deterministicRandom(in: 0...1000, seed: seed + 1)
                storage[fieldName] = .int(value)
            }
            
            let record = BlazeDataRecord(storage)
            
            // Dual-codec validation
            try assertCodecsEqual(record)
        }
    }
    
    func testFuzz_RandomNesting() throws {
        // Deterministic fuzz: 100 nested records with fixed seed
        for i in 0..<100 {
            let record = generateRandomNestedRecord(depth: 3, seed: UInt64(i))
            
            // Dual-codec validation
            try assertCodecsEqual(record)
        }
    }
    
    func testFuzz_RandomValues() throws {
        // Deterministic fuzz: 1000 records with fixed seed
        for i in 0..<1000 {
            var storage: [String: BlazeDocumentField] = [:]
            let seed = UInt64(i)
            
            // Random ints (using deterministic seed)
            storage["int"] = .int(deterministicRandom(in: Int.min...Int.max, seed: seed))
            
            // Random doubles (using deterministic seed)
            storage["double"] = .double(Double(deterministicRandom(in: -1000...1000, seed: seed + 1)))
            
            // Random bools (using deterministic seed)
            storage["bool"] = .bool(deterministicRandom(in: 0...1, seed: seed + 2) == 1)
            
            // Deterministic UUIDs (using seed)
            storage["uuid"] = .uuid(deterministicUUID(seed: seed + 3))
            
            // Random dates (using deterministic seed)
            let dateSeed = deterministicRandom(in: 0...1000000000, seed: seed + 4)
            storage["date"] = .date(Date(timeIntervalSince1970: Double(dateSeed)))
            
            // Random strings (using deterministic seed)
            let strLength = deterministicRandom(in: 0...1000, seed: seed + 5)
            storage["string"] = .string(generateRandomString(length: strLength, seed: seed + 6))
            
            // Random data (using deterministic seed)
            let dataLength = deterministicRandom(in: 0...10000, seed: seed + 7)
            var randomData = Data(count: dataLength)
            randomData.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                for j in 0..<dataLength {
                    bytes[j] = UInt8(deterministicRandom(in: 0...255, seed: seed + UInt64(j)))
                }
            }
            storage["data"] = .data(randomData)
            
            let record = BlazeDataRecord(storage)
            
            // Dual-codec validation
            try assertCodecsEqual(record)
        }
    }
    
    func testFuzz_EdgeCaseIntegers() throws {
        let edgeCases: [Int] = [
            Int.min,
            Int.min + 1,
            -1,
            0,
            1,
            255,
            256,
            65535,
            65536,
            Int.max - 1,
            Int.max
        ]
        
        for intValue in edgeCases {
            let record = BlazeDataRecord(["value": .int(intValue)])
            
            // Dual-codec validation
            try assertCodecsEqual(record)
        }
    }
    
    func testFuzz_UnicodeStrings() throws {
        let unicodeStrings = [
            "🔥",
            "🚀",
            "Hello 世界",
            "مرحبا",
            "こんにちは",
            String(repeating: "🔥", count: 100),
            "Mixed 🔥 English 世界 Text"
        ]
        
        for str in unicodeStrings {
            let record = BlazeDataRecord(["str": .string(str)])
            
            // Dual-codec validation
            try assertCodecsEqual(record)
        }
    }
    
    // MARK: - Helper Methods (Deterministic)
    
    /// Generate a deterministic random record using a seed
    private func generateRandomRecord(seed: UInt64) -> BlazeDataRecord {
        var storage: [String: BlazeDocumentField] = [:]
        let fieldCount = deterministicRandom(in: 1...50, seed: seed)
        
        for i in 0..<fieldCount {
            let fieldName = "field\(i)"
            let fieldType = deterministicRandom(in: 0...7, seed: seed + UInt64(i))
            
            switch fieldType {
            case 0:
                let strLength = deterministicRandom(in: 0...100, seed: seed + UInt64(i) + 1000)
                storage[fieldName] = .string(generateRandomString(length: strLength, seed: seed + UInt64(i) + 2000))
            case 1:
                storage[fieldName] = .int(deterministicRandom(in: -1000...1000, seed: seed + UInt64(i) + 3000))
            case 2:
                storage[fieldName] = .double(Double(deterministicRandom(in: -1000...1000, seed: seed + UInt64(i) + 4000)))
            case 3:
                storage[fieldName] = .bool(deterministicRandom(in: 0...1, seed: seed + UInt64(i) + 5000) == 1)
            case 4:
                storage[fieldName] = .uuid(deterministicUUID(seed: seed + UInt64(i) + 6000))
            case 5:
                let dateSeed = deterministicRandom(in: 0...1000000000, seed: seed + UInt64(i) + 7000)
                storage[fieldName] = .date(Date(timeIntervalSince1970: Double(dateSeed)))
            case 6:
                let dataLength = deterministicRandom(in: 0...1000, seed: seed + UInt64(i) + 8000)
                var data = Data(count: dataLength)
                data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                    for j in 0..<dataLength {
                        bytes[j] = UInt8(deterministicRandom(in: 0...255, seed: seed + UInt64(i) + UInt64(j) + 9000))
                    }
                }
                storage[fieldName] = .data(data)
            case 7:
                let arrayLength = deterministicRandom(in: 0...100, seed: seed + UInt64(i) + 10000)
                var items: [BlazeDocumentField] = []
                for j in 0..<arrayLength {
                    items.append(.int(deterministicRandom(in: 0...100, seed: seed + UInt64(i) + UInt64(j) + 11000)))
                }
                storage[fieldName] = .array(items)
            default:
                break
            }
        }
        
        return BlazeDataRecord(storage)
    }
    
    /// Generate a deterministic nested record using a seed
    private func generateRandomNestedRecord(depth: Int, seed: UInt64) -> BlazeDataRecord {
        if depth == 0 {
            return BlazeDataRecord(["value": .int(deterministicRandom(in: 0...100, seed: seed))])
        }
        
        var storage: [String: BlazeDocumentField] = [:]
        let nested = generateRandomNestedRecord(depth: depth - 1, seed: seed + 1)
        storage["nested"] = .dictionary(nested.storage)
        storage["value"] = .int(deterministicRandom(in: 0...100, seed: seed + 2))
        
        return BlazeDataRecord(storage)
    }
    
    /// Generate a deterministic random string using a seed
    private func generateRandomString(length: Int, seed: UInt64) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { i in
            let index = deterministicRandom(in: 0..<chars.count, seed: seed + UInt64(i))
            return chars[chars.index(chars.startIndex, offsetBy: index)]
        })
    }
    
    /// Deterministic random number generator using linear congruential generator
    /// This ensures tests are reproducible across runs
    private func deterministicRandom(in range: Range<Int>, seed: UInt64) -> Int {
        var state = seed
        state = state &* 1103515245 &+ 12345
        let value = Int(state % UInt64(range.count))
        return range.lowerBound + value
    }
    
    /// Deterministic random number generator for closed ranges
    private func deterministicRandom(in range: ClosedRange<Int>, seed: UInt64) -> Int {
        // Handle overflow case: if upperBound is Int.max, we can't add 1 to it
        // Also handle the case where the range spans Int.min...Int.max (count would overflow)
        if range.upperBound == Int.max {
            var state = seed
            state = state &* 1103515245 &+ 12345
            
            // Special case: full range Int.min...Int.max
            if range.lowerBound == Int.min {
                // For full range, use the random state directly as a bit pattern
                // This gives us uniform distribution across all Int values
                return Int(bitPattern: UInt(truncatingIfNeeded: state))
            }
            
            // Calculate count safely: upperBound - lowerBound + 1
            // Convert to UInt64 for safe arithmetic
            // For Int values: map to UInt64 space, calculate count, then map back
            let lowerBoundU = UInt64(bitPattern: Int64(range.lowerBound))
            let upperBoundU = UInt64(bitPattern: Int64(range.upperBound))
            
            // Calculate count in unsigned space
            // If upperBoundU < lowerBoundU, it means we wrapped around (shouldn't happen for valid ranges)
            let count: UInt64
            if upperBoundU >= lowerBoundU {
                count = upperBoundU - lowerBoundU + 1
            } else {
                // Wraparound case - this means the range spans more than half the Int64 space
                // Use the full range
                count = UInt64.max
            }
            
            // Generate value in range [0, count)
            let valueU = state % count
            
            // Convert back to signed Int
            // Map valueU to the range [lowerBoundU, upperBoundU]
            let resultU = lowerBoundU + valueU
            
            // Convert back to signed Int
            return Int(Int64(bitPattern: resultU))
        } else {
            // Safe to add 1 when upperBound < Int.max
            return deterministicRandom(in: range.lowerBound..<(range.upperBound + 1), seed: seed)
        }
    }
    
    /// Generate a deterministic UUID from a seed
    private func deterministicUUID(seed: UInt64) -> UUID {
        var state = seed
        var bytes: [UInt8] = []
        for _ in 0..<16 {
            state = state &* 1103515245 &+ 12345
            bytes.append(UInt8(state & 0xFF))
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Simple seeded random number generator for deterministic testing
private struct FuzzTestRNG: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        state = state &* 1103515245 &+ 12345
        return state
    }
}

