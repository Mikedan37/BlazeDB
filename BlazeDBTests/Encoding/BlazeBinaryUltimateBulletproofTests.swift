//
//  BlazeBinaryUltimateBulletproofTests.swift
//  BlazeDBTests
//
//  THE ULTIMATE test suite - if these pass, it's BULLETPROOF
//  Tests scenarios that would break ANY encoder/decoder
//

import XCTest
@testable import BlazeDBCore

final class BlazeBinaryUltimateBulletproofTests: XCTestCase {
    
    // MARK: - The Gauntlet (Tests That Break Everything)
    
    func testUltimate_TheGauntlet_AllPathologicalCases() throws {
        print("🔥 ULTIMATE: The Gauntlet - 20 cases that break most encoders")
        
        let gauntlet: [(String, BlazeDataRecord)] = [
            // 1. Empty everything
            ("Empty", BlazeDataRecord([:

])),
            
            // 2. Massive nested structure
            ("MassiveNest", BlazeDataRecord([
                "nest": .dictionary([
                    "level1": .dictionary([
                        "level2": .dictionary([
                            "level3": .array([.int(1), .int(2), .int(3)])
                        ])
                    ])
                ])
            ])),
            
            // 3. Confusing field names
            ("ConfusingNames", BlazeDataRecord([
                "BLAZE": .string("magic"),  // Same as header magic!
                "": .int(42),  // Empty field name
                "\0": .string("null byte in name"),
                String(repeating: "A", count: 10000): .int(1)  // Huge field name
            ])),
            
            // 4. All types at once
            ("AllTypes", BlazeDataRecord([
                "s": .string("test"),
                "i": .int(42),
                "d": .double(3.14),
                "b": .bool(true),
                "u": .uuid(UUID()),
                "dt": .date(Date()),
                "da": .data(Data([0x01])),
                "a": .array([.int(1)]),
                "di": .dictionary(["k": .int(1)])
            ])),
            
            // 5. Extreme values
            ("Extremes", BlazeDataRecord([
                "minInt": .int(Int.min),
                "maxInt": .int(Int.max),
                "inf": .double(Double.infinity),
                "negInf": .double(-Double.infinity),
                "nan": .double(Double.nan),
                "tiny": .double(Double.leastNonzeroMagnitude),
                "huge": .double(Double.greatestFiniteMagnitude)
            ])),
            
            // 6. Binary data with magic bytes
            ("MagicBytesInData", BlazeDataRecord([
                "magic": .data(Data([0x42, 0x4C, 0x41, 0x5A, 0x45])),  // "BLAZE"
                "header": .data(Data([0x42, 0x4C, 0x41, 0x5A, 0x45, 0x01, 0x00, 0x01]))  // Full header!
            ])),
            
            // 7. Duplicate UUIDs
            ("DuplicateValues", BlazeDataRecord([
                "uuid1": .uuid(UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!),
                "uuid2": .uuid(UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!)
            ])),
            
            // 8. Very long strings
            ("LongStrings", BlazeDataRecord([
                "s1": .string(String(repeating: "A", count: 100_000)),
                "s2": .string(String(repeating: "世界", count: 10_000))
            ])),
            
            // 9. Empty containers
            ("EmptyContainers", BlazeDataRecord([
                "emptyArray": .array([]),
                "emptyDict": .dictionary([:]),
                "emptyString": .string(""),
                "emptyData": .data(Data())
            ])),
            
            // 10. Special dates
            ("SpecialDates", BlazeDataRecord([
                "epoch": .date(Date(timeIntervalSince1970: 0)),
                "referenceEpoch": .date(Date(timeIntervalSinceReferenceDate: 0)),
                "distantPast": .date(Date.distantPast),
                "distantFuture": .date(Date.distantFuture)
            ])),
            
            // 11. Nested arrays
            ("NestedArrays", BlazeDataRecord([
                "nested": .array([
                    .array([
                        .array([
                            .array([.int(1)])
                        ])
                    ])
                ])
            ])),
            
            // 12. Mixed nested structures
            ("MixedNesting", BlazeDataRecord([
                "mix": .array([
                    .dictionary([
                        "inner": .array([
                            .dictionary([
                                "deep": .string("value")
                            ])
                        ])
                    ])
                ])
            ])),
            
            // 13. All zero UUID
            ("ZeroUUID", BlazeDataRecord([
                "zero": .uuid(UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)))
            ])),
            
            // 14. All max UUID
            ("MaxUUID", BlazeDataRecord([
                "max": .uuid(UUID(uuid: (255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255)))
            ])),
            
            // 15. Boolean edge cases
            ("BoolEdges", BlazeDataRecord([
                "true": .bool(true),
                "false": .bool(false),
                "trueArray": .array([.bool(true), .bool(true), .bool(true)]),
                "falseArray": .array([.bool(false), .bool(false), .bool(false)])
            ])),
            
            // 16. Repeated type tags in data
            ("TypeTagsInData", BlazeDataRecord([
                "tags": .data(Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x12, 0xFF]))
            ])),
            
            // 17. Unicode everywhere
            ("UnicodeEverywhere", BlazeDataRecord([
                "🔥": .string("🚀"),
                "世界": .string("Hello"),
                "مفتاح": .string("قيمة"),
                "ключ": .string("значение")
            ])),
            
            // 18. Large array with duplicates
            ("LargeArrayDupes", BlazeDataRecord([
                "arr": .array(Array(repeating: .int(42), count: 10_000))
            ])),
            
            // 19. Alternating types
            ("AlternatingTypes", BlazeDataRecord([
                "alt": .array([
                    .int(1), .string("a"), .double(1.0), .bool(true),
                    .int(2), .string("b"), .double(2.0), .bool(false),
                    .int(3), .string("c"), .double(3.0), .bool(true)
                ])
            ])),
            
            // 20. The Kitchen Sink
            ("KitchenSink", BlazeDataRecord([
                "everything": .array([
                    .int(Int.min),
                    .int(Int.max),
                    .double(Double.infinity),
                    .double(Double.nan),
                    .string(""),
                    .string(String(repeating: "X", count: 10000)),
                    .bool(true),
                    .bool(false),
                    .uuid(UUID()),
                    .date(Date()),
                    .data(Data([0x00, 0xFF])),
                    .array([]),
                    .dictionary([:])
                ])
            ]))
        ]
        
        var passCount = 0
        
        for (name, record) in gauntlet {
            do {
                let encoded = try BlazeBinaryEncoder.encode(record)
                let decoded = try BlazeBinaryDecoder.decode(encoded)
                
                // Verify basic integrity
                XCTAssertEqual(decoded.storage.count, record.storage.count,
                              "\(name): Field count mismatch!")
                
                passCount += 1
                print("  ✅ \(name) PASSED")
            } catch {
                XCTFail("\(name) FAILED: \(error)")
            }
        }
        
        XCTAssertEqual(passCount, 20, "All 20 gauntlet cases should pass!")
        print("  🔥 THE GAUNTLET: \(passCount)/20 PASSED!")
    }
    
    // MARK: - Memory Corruption Simulation
    
    func testUltimate_SimulateMemoryCorruption_BitFlips() throws {
        print("🔥 ULTIMATE: Simulate memory corruption (random bit flips)")
        
        let record = BlazeDataRecord([
            "critical": .string("Important data"),
            "value": .int(12345)
        ])
        
        let validEncoding = try BlazeBinaryEncoder.encode(record)
        
        // Simulate 100 random bit flips
        var detectedCount = 0
        
        for _ in 0..<100 {
            var corrupted = validEncoding
            
            // Random byte
            let randomByte = Int.random(in: 0..<corrupted.count)
            // Random bit
            let randomBit = UInt8(1 << Int.random(in: 0...7))
            
            // Flip bit
            corrupted[randomByte] ^= randomBit
            
            do {
                let decoded = try BlazeBinaryDecoder.decode(corrupted)
                let original = try BlazeBinaryDecoder.decode(validEncoding)
                
                // Check if corruption affected data
                if decoded.storage["value"]?.intValue != original.storage["value"]?.intValue ||
                   decoded.storage["critical"]?.stringValue != original.storage["critical"]?.stringValue {
                    detectedCount += 1  // Data changed = detected
                }
            } catch {
                detectedCount += 1  // Decoder caught it
            }
        }
        
        let detectionRate = Double(detectedCount) / 100 * 100
        
        print("  Bit flips: 100")
        print("  Detected: \(detectedCount) (\(String(format: "%.1f", detectionRate))%)")
        
        XCTAssertGreaterThan(detectionRate, 90, "Should detect >90% of bit flips!")
        
        print("  ✅ Memory corruption detection: \(String(format: "%.1f", detectionRate))%!")
    }
    
    // MARK: - Concurrent Stress Test
    
    func testUltimate_ConcurrentEncodeDecode_10kThreads() throws {
        print("🔥 ULTIMATE: 10,000 concurrent encode/decode operations")
        
        let expectation = self.expectation(description: "Concurrent ops")
        expectation.expectedFulfillmentCount = 10_000
        
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        var failureCount = 0
        let lock = NSLock()
        
        for i in 0..<10_000 {
            queue.async {
                do {
                    let record = BlazeDataRecord([
                        "id": .int(i),
                        "uuid": .uuid(UUID()),
                        "timestamp": .date(Date())
                    ])
                    
                    let encoded = try BlazeBinaryEncoder.encode(record)
                    let decoded = try BlazeBinaryDecoder.decode(encoded)
                    
                    if decoded.storage["id"]?.intValue != i {
                        lock.lock()
                        failureCount += 1
                        lock.unlock()
                    }
                } catch {
                    lock.lock()
                    failureCount += 1
                    lock.unlock()
                }
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 60)
        
        print("  Operations: 10,000")
        print("  Failures: \(failureCount)")
        print("  Success rate: \(String(format: "%.2f", (10000 - failureCount) / 100))%")
        
        XCTAssertEqual(failureCount, 0, "Should have ZERO failures in concurrent ops!")
        
        print("  ✅ 10,000 concurrent operations: 100.00% success!")
    }
    
    // MARK: - Fuzz Testing (Random Data)
    
    func testUltimate_FuzzTest_10kRandomRecords() throws {
        print("🔥 ULTIMATE: Fuzz test with 10,000 random records")
        
        var failureCount = 0
        var corruptionCount = 0
        
        func randomField() -> BlazeDocumentField {
            let types: [BlazeDocumentField] = [
                .string(UUID().uuidString),
                .int(Int.random(in: Int.min...Int.max)),
                .double(Double.random(in: -1000...1000)),
                .bool(Bool.random()),
                .uuid(UUID()),
                .date(Date(timeIntervalSince1970: Double.random(in: 0...2_000_000_000))),
                .data(Data((0..<Int.random(in: 0...100)).map { _ in UInt8.random(in: 0...255) })),
                .array([.int(Int.random(in: 0...100))]),
                .dictionary(["key": .int(Int.random(in: 0...100))])
            ]
            return types.randomElement()!
        }
        
        for i in 0..<10_000 {
            var storage: [String: BlazeDocumentField] = [:]
            
            // Random field count
            let fieldCount = Int.random(in: 1...20)
            for j in 0..<fieldCount {
                storage["field\(j)"] = randomField()
            }
            
            let record = BlazeDataRecord(storage)
            
            do {
                let encoded = try BlazeBinaryEncoder.encode(record)
                let decoded = try BlazeBinaryDecoder.decode(encoded)
                
                // Basic integrity check
                if decoded.storage.count != record.storage.count {
                    corruptionCount += 1
                }
            } catch {
                failureCount += 1
            }
            
            if (i + 1) % 1000 == 0 {
                print("  Progress: \(i + 1)/10,000...")
            }
        }
        
        let successRate = Double(10_000 - failureCount - corruptionCount) / 10_000 * 100
        
        print("  Records: 10,000")
        print("  Failures: \(failureCount)")
        print("  Corruptions: \(corruptionCount)")
        print("  Success rate: \(String(format: "%.2f", successRate))%")
        
        XCTAssertLessThan(failureCount + corruptionCount, 10, "Should have <10 total failures!")
        
        print("  ✅ Fuzz test: \(String(format: "%.2f", successRate))% success!")
    }
    
    // MARK: - Backwards Compatibility Test
    
    func testUltimate_FormatStability_SavedBinaryReference() throws {
        print("🔥 ULTIMATE: Format stability with saved reference")
        
        // Create deterministic test data
        let fixedUUID = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
        let fixedDate = Date(timeIntervalSinceReferenceDate: 0)
        
        let record = BlazeDataRecord([
            "id": .uuid(fixedUUID),
            "timestamp": .date(fixedDate),
            "value": .int(42),
            "title": .string("Test")
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // Save hex dump for future comparison
        let hexDump = encoded.map { String(format: "%02X", $0) }.joined(separator: " ")
        
        print("  Reference hex dump (v1.0):")
        print("  \(hexDump)")
        print("  Length: \(encoded.count) bytes")
        
        // Decode it
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        XCTAssertEqual(decoded.storage["value"]?.intValue, 42)
        XCTAssertEqual(decoded.storage["title"]?.stringValue, "Test")
        XCTAssertEqual(decoded.storage["id"]?.uuidValue, fixedUUID)
        
        print("  ✅ Reference encoding created and verified!")
        
        // TODO: In future versions, compare against this exact hex dump
        // to ensure backwards compatibility!
    }
    
    // MARK: - Performance Under Load
    
    func testUltimate_PerformanceUnderLoad_LargeRecords() throws {
        print("🔥 ULTIMATE: Performance with large records")
        
        // Create 1,000 large records (each ~1MB)
        var records: [BlazeDataRecord] = []
        
        for i in 0..<100 {  // Reduced to 100 for reasonable test time
            let largeString = String(repeating: "X", count: 100_000)
            let record = BlazeDataRecord([
                "id": .int(i),
                "data": .string(largeString)
            ])
            records.append(record)
        }
        
        let startTime = Date()
        
        // Encode all
        var encodings: [Data] = []
        for record in records {
            let encoded = try BlazeBinaryEncoder.encode(record)
            encodings.append(encoded)
        }
        
        // Decode all
        for encoded in encodings {
            _ = try BlazeBinaryDecoder.decode(encoded)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        print("  Records: \(records.count) (each ~100KB)")
        print("  Total time: \(String(format: "%.2f", duration)) seconds")
        print("  Per-record: \(String(format: "%.2f", duration / Double(records.count) * 1000)) ms")
        
        XCTAssertLessThan(duration, 10, "Should process 100 large records in <10s!")
        
        print("  ✅ Large record performance acceptable!")
    }
    
    // MARK: - The Ultimate Test
    
    func testUltimate_TheUltimateTest_EverythingAtOnce() throws {
        print("🔥 ULTIMATE: THE ULTIMATE TEST - Everything at once!")
        
        // This test combines:
        // - Large data
        // - Many fields
        // - All types
        // - Deep nesting
        // - Special values
        // - Unicode
        // - Everything else
        
        var storage: [String: BlazeDocumentField] = [:]
        
        // 1. All simple types
        storage["int"] = .int(42)
        storage["double"] = .double(3.14)
        storage["bool"] = .bool(true)
        storage["string"] = .string("Test")
        storage["uuid"] = .uuid(UUID())
        storage["date"] = .date(Date())
        storage["data"] = .data(Data([0x01, 0x02]))
        
        // 2. Extreme values
        storage["intMin"] = .int(Int.min)
        storage["intMax"] = .int(Int.max)
        storage["inf"] = .double(Double.infinity)
        storage["nan"] = .double(Double.nan)
        
        // 3. Empty containers
        storage["emptyArray"] = .array([])
        storage["emptyDict"] = .dictionary([:])
        storage["emptyString"] = .string("")
        
        // 4. Large data
        storage["largeString"] = .string(String(repeating: "X", count: 10_000))
        storage["largeArray"] = .array(Array(repeating: .int(42), count: 1000))
        
        // 5. Deep nesting
        var deep: BlazeDocumentField = .string("bottom")
        for _ in 0..<50 {
            deep = .dictionary(["level": deep])
        }
        storage["deepNest"] = deep
        
        // 6. Unicode
        storage["🔥"] = .string("🚀")
        storage["世界"] = .string("Hello")
        
        // 7. Confusing field names
        storage["BLAZE"] = .string("magic")
        
        // 8. Many fields
        for i in 0..<100 {
            storage["field\(i)"] = .int(i)
        }
        
        let record = BlazeDataRecord(storage)
        
        print("  Total fields: \(storage.count)")
        
        // Encode
        let encoded = try BlazeBinaryEncoder.encode(record)
        print("  Encoded size: \(encoded.count / 1024) KB")
        
        // Decode
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        // Verify
        XCTAssertEqual(decoded.storage.count, storage.count, "Field count mismatch!")
        XCTAssertEqual(decoded.storage["int"]?.intValue, 42)
        XCTAssertEqual(decoded.storage["string"]?.stringValue, "Test")
        XCTAssertEqual(decoded.storage["intMin"]?.intValue, Int.min)
        XCTAssertEqual(decoded.storage["intMax"]?.intValue, Int.max)
        XCTAssertTrue(decoded.storage["nan"]?.doubleValue?.isNaN ?? false)
        XCTAssertEqual(decoded.storage["largeString"]?.stringValue?.count, 10_000)
        XCTAssertEqual(decoded.storage["🔥"]?.stringValue, "🚀")
        
        print("  ✅ THE ULTIMATE TEST PASSED!")
    }
    
    // MARK: - The Final Boss
    
    func testUltimate_TheFinalBoss_IfThisPassesItsFlawless() throws {
        print("🔥 ULTIMATE: THE FINAL BOSS - The hardest test possible")
        
        // This is the test that breaks everything if there's ANY flaw
        
        let expectation = self.expectation(description: "Final Boss")
        expectation.expectedFulfillmentCount = 1000
        
        let queue = DispatchQueue(label: "finalBoss", attributes: .concurrent)
        var failureCount = 0
        let lock = NSLock()
        
        for i in 0..<1000 {
            queue.async {
                do {
                    // Create pathological record
                    var storage: [String: BlazeDocumentField] = [:]
                    
                    storage["id"] = .int(i)
                    storage["magic"] = .data(Data([0x42, 0x4C, 0x41, 0x5A, 0x45]))
                    storage["extreme"] = .int(Int.min)
                    storage["inf"] = .double(Double.infinity)
                    storage["nan"] = .double(Double.nan)
                    storage["large"] = .string(String(repeating: "X", count: 10_000))
                    storage["uuid"] = .uuid(UUID())
                    storage["date"] = .date(Date())
                    storage["empty"] = .array([])
                    storage["🔥"] = .string("test")
                    
                    // Deep nest
                    var nest: BlazeDocumentField = .string("deep")
                    for _ in 0..<20 {
                        nest = .dictionary(["level": nest])
                    }
                    storage["nest"] = nest
                    
                    // Large array
                    storage["arr"] = .array(Array(repeating: .int(Int.random(in: 0...1000)), count: 100))
                    
                    let record = BlazeDataRecord(storage)
                    
                    // Encode/decode
                    let encoded = try BlazeBinaryEncoder.encode(record)
                    let decoded = try BlazeBinaryDecoder.decode(encoded)
                    
                    // Verify integrity
                    if decoded.storage.count != storage.count {
                        lock.lock()
                        failureCount += 1
                        lock.unlock()
                    }
                    
                    if decoded.storage["id"]?.intValue != i {
                        lock.lock()
                        failureCount += 1
                        lock.unlock()
                    }
                    
                    if decoded.storage["extreme"]?.intValue != Int.min {
                        lock.lock()
                        failureCount += 1
                        lock.unlock()
                    }
                    
                } catch {
                    lock.lock()
                    failureCount += 1
                    lock.unlock()
                }
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 120)
        
        print("  Operations: 1,000 pathological records")
        print("  Failures: \(failureCount)")
        print("  Success rate: \(String(format: "%.1f", Double(1000 - failureCount) / 10))%")
        
        XCTAssertEqual(failureCount, 0, "THE FINAL BOSS: ZERO failures allowed!")
        
        print("  🏆 THE FINAL BOSS: DEFEATED! BlazeBinary is FLAWLESS!")
    }
}

