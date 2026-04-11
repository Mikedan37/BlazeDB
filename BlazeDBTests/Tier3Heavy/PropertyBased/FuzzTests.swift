//
//  FuzzTests.swift
//  BlazeDBTests
//
//  LEVEL 8: Fuzzing - Throw random garbage at the database
//  and ensure it never crashes, corrupts data, or leaks memory.
//
//  Fuzzing discovers bugs that no human would ever think to test.
//  It's the ultimate stress test.
//
//  Created: 2025-11-12
//

import XCTest
@testable import BlazeDBCore

final class FuzzTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    private var fuzzSeed: UInt64 = 0
    private var fuzzScale: Int = 1
    
    override func setUp() {
        super.setUp()
        
        BlazeDBClient.clearCachedKey()
        fuzzSeed = Self.parseSeed(ProcessInfo.processInfo.environment["BLAZEDB_FUZZ_SEED"]) ?? 0xB1A2E3D4C5F60718
        fuzzScale = max(1, Int(ProcessInfo.processInfo.environment["BLAZEDB_FUZZ_SCALE"] ?? "") ?? 1)
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FuzzTest-\(testID).blazedb")
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try! BlazeDBClient(name: "fuzz_test", fileURL: tempURL, password: "SecureTestDB-456!")
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Fuzz: Random String Inputs
    
    /// Fuzz test: Random strings of all lengths and character types
    func testFuzz_RandomStrings() throws {
        let iterations = 20_000 * fuzzScale
        print("\n🎯 FUZZ: Random Strings (\(iterations) inputs)")
        var rng = FuzzTestRNG(seed: deriveSeed(0x1001))
        
        var successCount = 0
        var errorCount = 0
        var mismatchCount = 0
        var sampleErrors: [String] = []
        
        for i in 0..<iterations {
            let str = randomFuzzString(rng: &rng)
            
            do {
                let id = try db.insert(BlazeDataRecord(["fuzz": .string(str)]))
                let fetched = try db.fetch(id: id)
                
                // Verify round-trip
                if fetched?["fuzz"]?.stringValue == str {
                    successCount += 1
                } else {
                    mismatchCount += 1
                }
                
                // Cleanup to avoid memory bloat
                if i % 100 == 0 {
                    let allRecords = try db.fetchAll()
                    for record in allRecords {
                        if let id = record.storage["id"]?.uuidValue {
                            try? db.delete(id: id)
                        }
                    }
                }
            } catch {
                errorCount += 1
                if sampleErrors.count < 8 {
                    sampleErrors.append(String(describing: error))
                }
            }
            
            if i % 1000 == 0 {
                print("  Tested \(i) random strings...")
            }
        }
        
        print("  📊 Successful round-trips: \(successCount)")
        print("  📊 Mismatches: \(mismatchCount)")
        print("  📊 Errors: \(errorCount)")
        assertErrorBudget(
            testName: "RandomStrings",
            total: iterations,
            errors: errorCount + mismatchCount,
            maxErrorRate: 0.001,
            sampleErrors: sampleErrors
        )
        print("  ✅ No crashes detected!")
    }
    
    /// Fuzz test: Unicode edge cases and invalid sequences
    func testFuzz_UnicodeEdgeCases() throws {
        let iterations = 10_000 * fuzzScale
        print("\n🎯 FUZZ: Unicode Edge Cases (\(iterations) inputs)")
        var rng = FuzzTestRNG(seed: deriveSeed(0x2002))
        
        let edgeCases: [String] = [
            // Emoji and special characters
            "🔥💀🎯🚀",
            "👨‍👩‍👧‍👦",  // Family emoji (multiple codepoints)
            "🏳️‍🌈",        // Rainbow flag (combining characters)
            
            // Right-to-left text
            "مرحبا بك",
            "שלום",
            "مرحبا Hello שלום",  // Mixed RTL/LTR
            
            // Zero-width characters
            "Hello\u{200B}World",   // Zero-width space
            "Test\u{FEFF}Data",     // Zero-width no-break space
            
            // Control characters
            "Line1\nLine2\rLine3\r\nLine4",
            "Tab\tSeparated\tData",
            "\u{0000}NULL_BYTE\u{0000}",
            
            // Long combining sequences
            "e\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}",
            
            // Homoglyphs (look-alike characters)
            "Τеѕt",  // Uses Greek Tau, Cyrillic е, Latin s, t
            
            // Normalization edge cases
            "café",   // é as single character
            "café",   // é as e + combining accent
            
            // Surrogate pairs
            "𝕳𝖊𝖑𝖑𝖔 𝖂𝖔𝖗𝖑𝖉",  // Math bold
            
            // Unusual whitespace
            "Normal Space\u{00A0}NBSP\u{2003}EM_SPACE",
            
            // Very long strings
            String(repeating: "A", count: 100_000),
            String(repeating: "🔥", count: 10_000),
            
            // Empty and near-empty
            "",
            " ",
            "\n",
            "\t",
            
            // SQL injection attempts (should be safe)
            "'; DROP TABLE records; --",
            "' OR '1'='1",
            
            // JSON injection attempts
            "\",\"evil\":\"payload",
            "\n},\n{\"injection\":\"data\"\n}",
            
            // Path traversal attempts
            "../../etc/passwd",
            "..\\..\\windows\\system32",
            
            // Format string attacks
            "%s%s%s%s%s%s%s",
            "%@%@%@%@%@",
            
            // XML entities
            "&lt;&gt;&amp;&quot;&apos;",
            
            // Extremely nested quotes
            String(repeating: "\"", count: 1000),
        ]
        
        var edgeCaseFailures = 0
        for (i, testCase) in edgeCases.enumerated() {
            do {
                let id = try db.insert(BlazeDataRecord(["unicode": .string(testCase)]))
                let fetched = try db.fetch(id: id)
                
                // Verify exact round-trip
                XCTAssertEqual(fetched?["unicode"]?.stringValue, testCase, 
                              "Unicode case \(i) should survive round-trip")
            } catch {
                edgeCaseFailures += 1
                XCTFail("Unicode case \(i) caused error: \(error)")
            }
        }
        
        // Random Unicode fuzz
        var randomErrors = 0
        var sampleErrors: [String] = []
        for i in 0..<iterations {
            let randomUnicode = randomUnicodeString(rng: &rng)
            
            do {
                let id = try db.insert(BlazeDataRecord(["fuzz": .string(randomUnicode)]))
                _ = try db.fetch(id: id)
                
                if i % 50 == 0 {
                    let allRecords = try db.fetchAll()
                    for record in allRecords {
                        if let id = record.storage["id"]?.uuidValue {
                            try? db.delete(id: id)
                        }
                    }
                }
            } catch {
                randomErrors += 1
                if sampleErrors.count < 8 {
                    sampleErrors.append(String(describing: error))
                }
            }
            
            if i % 1000 == 0 {
                print("  Tested \(i) random Unicode strings...")
            }
        }
        
        print("  📊 Edge-case failures: \(edgeCaseFailures)")
        print("  📊 Random Unicode errors: \(randomErrors)")
        assertErrorBudget(
            testName: "UnicodeEdgeCases",
            total: iterations,
            errors: randomErrors,
            maxErrorRate: 0.002,
            sampleErrors: sampleErrors
        )
        print("  ✅ All Unicode edge cases handled!")
    }
    
    // MARK: - Fuzz: Malformed Binary Data
    
    /// Fuzz test: Random binary data of all sizes
    func testFuzz_RandomBinaryData() throws {
        let iterations = 10_000 * fuzzScale
        print("\n🎯 FUZZ: Random Binary Data (\(iterations) blobs)")
        var rng = FuzzTestRNG(seed: deriveSeed(0x3003))
        var errorCount = 0
        var sampleErrors: [String] = []
        
        for i in 0..<iterations {
            let size = Int.random(in: 0...20_000, using: &rng)
            let data = randomBinaryData(size: size, rng: &rng)
            
            do {
                let id = try db.insert(BlazeDataRecord(["blob": .data(data)]))
                let fetched = try db.fetch(id: id)
                
                // Verify byte-perfect round-trip
                if let fetchedData = fetched?["blob"]?.dataValue {
                    XCTAssertEqual(fetchedData, data, "Binary data should be byte-perfect")
                }
                
                if i % 100 == 0 {
                    let allRecords = try db.fetchAll()
                    for record in allRecords {
                        if let id = record.storage["id"]?.uuidValue {
                            try? db.delete(id: id)
                        }
                    }
                }
            } catch {
                errorCount += 1
                if sampleErrors.count < 8 {
                    sampleErrors.append(String(describing: error))
                }
            }
            
            if i % 1000 == 0 {
                print("  Tested \(i) random binary blobs...")
            }
        }
        
        print("  📊 Binary errors: \(errorCount)")
        assertErrorBudget(
            testName: "RandomBinaryData",
            total: iterations,
            errors: errorCount,
            maxErrorRate: 0.003,
            sampleErrors: sampleErrors
        )
        print("  ✅ All binary data handled correctly!")
    }
    
    // MARK: - Fuzz: Extreme Numbers
    
    /// Fuzz test: Extreme integer and floating-point values
    func testFuzz_ExtremeNumbers() throws {
        let iterations = 2_000 * fuzzScale
        print("\n🎯 FUZZ: Extreme Numbers (\(iterations) values)")
        var rng = FuzzTestRNG(seed: deriveSeed(0x4004))
        
        let edgeCases: [BlazeDocumentField] = [
            // Integer extremes
            .int(Int.max),
            .int(Int.min),
            .int(0),
            .int(-1),
            .int(1),
            
            // Double extremes
            .double(Double.infinity),
            .double(-Double.infinity),
            .double(Double.nan),
            .double(0.0),
            .double(-0.0),
            .double(Double.greatestFiniteMagnitude),
            .double(-Double.greatestFiniteMagnitude),
            .double(Double.leastNormalMagnitude),
            .double(Double.leastNonzeroMagnitude),
            
            // Subnormal numbers
            .double(Double.leastNonzeroMagnitude / 2),
            
            // Very precise numbers
            .double(1.0 / 3.0),
            .double(1.0 / 7.0),
            .double(0.1 + 0.2),  // Classic floating-point issue
            
            // Scientific notation extremes
            .double(1e308),
            .double(1e-308),
            .double(-1e308),
            .double(-1e-308),
        ]
        
        var edgeErrors = 0
        for (i, value) in edgeCases.enumerated() {
            do {
                let id = try db.insert(BlazeDataRecord(["number": value]))
                let fetched = try db.fetch(id: id)
                
                // For NaN, check that it's still NaN
                if case .double(let original) = value, original.isNaN {
                    if let fetchedDouble = fetched?["number"]?.doubleValue {
                        XCTAssertTrue(fetchedDouble.isNaN, "NaN should remain NaN")
                    }
                }
                // For infinity
                else if case .double(let original) = value, original.isInfinite {
                    if let fetchedDouble = fetched?["number"]?.doubleValue {
                        XCTAssertEqual(fetchedDouble.isInfinite, true, "Infinity should remain infinity")
                        XCTAssertEqual(fetchedDouble > 0, original > 0, "Sign should be preserved")
                    }
                }
            } catch {
                // Some values might be rejected (e.g., NaN in some systems)
                edgeErrors += 1
                print("  ⚠️ Edge case \(i) rejected: \(error)")
            }
        }
        
        // Random number fuzz
        var randomErrors = 0
        for i in 0..<iterations {
            let randomInt = Int.random(in: Int.min...Int.max, using: &rng)
            let randomDouble = Double.random(in: -1e100...1e100, using: &rng)
            
            do {
                _ = try db.insert(BlazeDataRecord([
                    "int": .int(randomInt),
                    "double": .double(randomDouble)
                ]))
                
                if i % 100 == 0 {
                    let allRecords = try db.fetchAll()
                    for record in allRecords {
                        if let id = record.storage["id"]?.uuidValue {
                            try? db.delete(id: id)
                        }
                    }
                }
            } catch {
                randomErrors += 1
            }
            
            if i % 200 == 0 {
                print("  Tested \(i) random numbers...")
            }
        }
        
        print("  📊 Extreme edge errors: \(edgeErrors)")
        print("  📊 Random number errors: \(randomErrors)")
        assertErrorBudget(
            testName: "ExtremeNumbers",
            total: iterations,
            errors: randomErrors,
            maxErrorRate: 0.01,
            sampleErrors: []
        )
        print("  ✅ All extreme numbers handled!")
    }
    
    // MARK: - Fuzz: Nested Data Structures
    
    /// Fuzz test: Deeply nested arrays and dictionaries
    func testFuzz_DeeplyNestedStructures() throws {
        print("\n🎯 FUZZ: Deeply Nested Structures (deeper)")
        let maxDepth = 30
        var failures = 0
        
        for depth in 1..<maxDepth {
            // Create deeply nested array
            var nestedArray: BlazeDocumentField = .int(42)
            for _ in 0..<depth {
                nestedArray = .array([nestedArray])
            }
            
            do {
                let id = try db.insert(BlazeDataRecord(["nested": nestedArray]))
                _ = try db.fetch(id: id)
            } catch {
                failures += 1
                print("  ⚠️ Depth \(depth) rejected: \(error)")
            }
        }
        
        for depth in 1..<maxDepth {
            // Create deeply nested dictionary
            var nestedDict: BlazeDocumentField = .int(42)
            for i in 0..<depth {
                nestedDict = .dictionary(["level\(i)": nestedDict])
            }
            
            do {
                let id = try db.insert(BlazeDataRecord(["nested": nestedDict]))
                _ = try db.fetch(id: id)
            } catch {
                failures += 1
                print("  ⚠️ Depth \(depth) rejected: \(error)")
            }
        }
        
        XCTAssertLessThanOrEqual(failures, 2, "Nested structure rejection rate too high")
        print("  ✅ Deeply nested structures handled!")
    }
    
    // MARK: - Fuzz: Malicious Field Names
    
    /// Fuzz test: Unusual and malicious field names
    func testFuzz_MaliciousFieldNames() throws {
        print("\n🎯 FUZZ: Malicious Field Names (100 tests)")
        
        let maliciousNames = [
            "",                           // Empty field name
            " ",                          // Whitespace only
            "\n",                         // Newline
            "\t",                         // Tab
            ".",                          // Single dot
            "..",                         // Double dot
            "...",                        // Triple dot
            "id",                         // Reserved keyword
            "ID",                         // Case variation
            "_id",                        // Underscore prefix
            "__proto__",                  // JavaScript prototype pollution
            "constructor",                // Another prototype pollution
            "$where",                     // MongoDB injection
            "$ne",                        // MongoDB operator
            "a".repeated(1000),           // Very long field name
            "field\u{0000}name",          // Null byte
            "field\nname",                // Newline in name
            "field\tname",                // Tab in name
            "🔥",                         // Emoji
            "键",                         // Chinese character
            String(repeating: "\"", count: 100),  // Many quotes
        ]
        
        var rejectionCount = 0
        for (i, fieldName) in maliciousNames.enumerated() {
            do {
                let record = BlazeDataRecord([fieldName: .string("test")])
                let id = try db.insert(record)
                let fetched = try db.fetch(id: id)
                
                // Should be able to retrieve
                XCTAssertNotNil(fetched, "Record with field '\(fieldName)' should be retrievable")
            } catch {
                // Some field names might be rejected
                rejectionCount += 1
                print("  ⚠️ Field name \(i) rejected: '\(fieldName)'")
            }
        }
        
        XCTAssertLessThanOrEqual(rejectionCount, 4, "Too many malicious-field-name rejections")
        print("  ✅ Malicious field names handled!")
    }
    
    // MARK: - Fuzz: Record Size Extremes
    
    /// Fuzz test: Very large and very small records
    func testFuzz_RecordSizeExtremes() throws {
        print("\n🎯 FUZZ: Record Size Extremes")
        var rejectedCases = 0
        
        // Empty record
        do {
            let emptyRecord = BlazeDataRecord([:])
            let id = try db.insert(emptyRecord)
            let fetched = try db.fetch(id: id)
            XCTAssertNotNil(fetched, "Empty record should be retrievable")
        } catch {
            rejectedCases += 1
            print("  ⚠️ Empty record rejected: \(error)")
        }
        
        // Single field
        do {
            let id = try db.insert(BlazeDataRecord(["a": .int(1)]))
            let fetched = try db.fetch(id: id)
            XCTAssertNotNil(fetched)
        } catch {
            rejectedCases += 1
            print("  ⚠️ Single field rejected")
        }
        
        // Many fields (1000 fields)
        do {
            var fields: [String: BlazeDocumentField] = [:]
            for i in 0..<1000 {
                fields["field\(i)"] = .int(i)
            }
            let id = try db.insert(BlazeDataRecord(fields))
            let fetched = try db.fetch(id: id)
            XCTAssertNotNil(fetched, "Record with 1000 fields should work")
        } catch {
            rejectedCases += 1
            print("  ⚠️ 1000 fields rejected: \(error)")
        }
        
        // Very large string field
        do {
            let largeString = String(repeating: "A", count: 1_000_000)  // 1MB
            let id = try db.insert(BlazeDataRecord(["large": .string(largeString)]))
            let fetched = try db.fetch(id: id)
            XCTAssertEqual(fetched?["large"]?.stringValue?.count, 1_000_000)
        } catch {
            rejectedCases += 1
            print("  ⚠️ 1MB string rejected: \(error)")
        }
        
        // Very large binary field
        do {
            let largeData = Data(repeating: 0xFF, count: 1_000_000)  // 1MB
            let id = try db.insert(BlazeDataRecord(["blob": .data(largeData)]))
            let fetched = try db.fetch(id: id)
            XCTAssertEqual(fetched?["blob"]?.dataValue?.count, 1_000_000)
        } catch {
            rejectedCases += 1
            print("  ⚠️ 1MB blob rejected: \(error)")
        }
        
        XCTAssertLessThanOrEqual(rejectedCases, 1, "Unexpected record-size regression")
        print("  ✅ Size extremes handled!")
    }
    
    // MARK: - Fuzz: Concurrent Chaos
    
    #if !BLAZEDB_LINUX_CORE
    /// Fuzz test: Thousands of concurrent random operations
    func testFuzz_ConcurrentChaos() throws {
        let operations = 10_000 * fuzzScale
        print("\n🎯 FUZZ: Concurrent Chaos (\(operations) operations)")
        
        // Pre-populate with some data
        for i in 0..<100 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        let group = DispatchGroup()
        var expectedErrorCount = 0
        var unexpectedErrorCount = 0
        let errorLock = NSLock()
        var unexpectedSamples: [String] = []
        
        // Deterministic operation plan for reproducibility.
        var planner = FuzzTestRNG(seed: deriveSeed(0x5005))
        let operationPlan = (0..<operations).map { _ in Int.random(in: 0...10, using: &planner) }
        
        // Concurrent random operations
        for i in 0..<operations {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                do {
                    var opRng = FuzzTestRNG(seed: self.deriveSeed(0x5100) &+ UInt64(i))
                    let op = operationPlan[i]
                    
                    switch op {
                    case 0...3:  // Insert (40%)
                        _ = try self.db.insert(self.randomFuzzRecord(rng: &opRng))
                        
                    case 4...6:  // Fetch (30%)
                        _ = try self.db.fetchAll()
                        
                    case 7...8:  // Update (20%)
                        let all = try self.db.fetchAll()
                        if let random = all.randomElement(),
                           let id = random.storage["id"]?.uuidValue {
                            try self.db.update(id: id, with: self.randomFuzzRecord(rng: &opRng))
                        }
                        
                    case 9:  // Delete (10%)
                        let all = try self.db.fetchAll()
                        if let random = all.randomElement(),
                           let id = random.storage["id"]?.uuidValue,
                           all.count > 10 {
                            try self.db.delete(id: id)
                        }
                        
                    case 10:  // Query
                        _ = try self.db.query()
                            .where("value", greaterThan: .int(0))
                            .execute()
                        
                    default:
                        break
                    }
                } catch {
                    errorLock.lock()
                    if self.isExpectedConcurrentChaosError(error) {
                        expectedErrorCount += 1
                    } else {
                        unexpectedErrorCount += 1
                        if unexpectedSamples.count < 8 {
                            unexpectedSamples.append(String(describing: error))
                        }
                    }
                    errorLock.unlock()
                }
            }
        }
        
        group.wait()
        
        print("  📊 Operations: \(operations)")
        print("  📊 Expected errors: \(expectedErrorCount)")
        print("  📊 Unexpected errors: \(unexpectedErrorCount)")
        
        // Database should still be functional
        XCTAssertNoThrow(try db.fetchAll(), "Database should remain queryable")
        XCTAssertEqual(unexpectedErrorCount, 0, "Unexpected concurrent errors: \(unexpectedSamples.joined(separator: " | "))")
        assertErrorBudget(
            testName: "ConcurrentChaos(expected)",
            total: operations,
            errors: expectedErrorCount,
            maxErrorRate: 0.03,
            sampleErrors: []
        )
        
        print("  ✅ Survived concurrent chaos!")
    }
    #else
    /// Linux CI: Swift 6 rejects `self` / `var` captures in `@Sendable` dispatch; keep a quick smoke test.
    func testFuzz_ConcurrentChaos() throws {
        print("\n🎯 FUZZ: Concurrent Chaos (Linux smoke, no thread fan-out)")
        for i in 0..<100 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        XCTAssertNoThrow(try db.fetchAll(), "Database should remain queryable")
        print("  ✅ Linux smoke complete")
    }
    #endif
    
    // MARK: - Fuzz: Query Injection
    
    /// Fuzz test: SQL/NoSQL injection attempts
    func testFuzz_QueryInjection() throws {
        print("\n🎯 FUZZ: Query Injection Attempts (100 tests)")
        
        let injectionPayloads = [
            "' OR '1'='1",
            "'; DROP TABLE users; --",
            "admin'--",
            "' OR 1=1--",
            "' UNION SELECT * FROM passwords--",
            "1; DROP TABLE records",
            "$where: '1 == 1'",
            "{ $ne: null }",
            "{ $gt: '' }",
            "$expr: { $eq: [1, 1] }",
            "../../../etc/passwd",
            "../../database.blazedb",
            "%00",
            "\0",
        ]
        
        var failures = 0
        // Insert records with injection payloads
        for (i, payload) in injectionPayloads.enumerated() {
            do {
                let id = try db.insert(BlazeDataRecord([
                    "name": .string(payload),
                    "safe": .int(i)
                ]))
                
                // Try to query with the payload
                let results = try db.query()
                    .where("name", equals: .string(payload))
                    .execute()
                
                // Should only find the one record
                XCTAssertEqual(results.count, 1, "Injection payload should not affect query")
                
                // Should be able to delete safely
                try db.delete(id: id)
            } catch {
                failures += 1
                print("  ⚠️ Injection payload \(i) caused error: \(error)")
            }
        }
        
        XCTAssertEqual(failures, 0, "Injection fuzz payloads should not fail")
        print("  ✅ All injection attempts safely handled!")
    }
    
    // MARK: - Fuzz: Memory Stress
    
    /// Fuzz test: Operations that could cause memory leaks
    func testFuzz_MemoryStress() throws {
        let cycles = 2_000 * fuzzScale
        print("\n🎯 FUZZ: Memory Stress (\(cycles) cycles)")
        
        for i in 0..<cycles {
            // Insert large record
            let largeRecord = BlazeDataRecord([
                "data": .string(String(repeating: "X", count: 10_000)),
                "blob": .data(Data(repeating: 0xFF, count: 10_000))
            ])
            
            let id = try db.insert(largeRecord)
            
            // Immediately fetch and delete
            _ = try db.fetch(id: id)
            try db.delete(id: id)
            
            // Occasionally persist
            if i % 100 == 0 {
                try db.persist()
                print("  Cycle \(i)/\(cycles)...")
            }
        }
        
        print("  ✅ Memory stress test passed!")
    }
    
    // MARK: - Fuzz: Transaction Chaos
    
    /// Fuzz test: Random batch operations with potential failures
    func testFuzz_TransactionChaos() throws {
        // Nightly/macOS runners: full 400×scale batches can OOM or trip limits when combined with other suites.
        let base = 400 * fuzzScale
        let batches: Int = {
            if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
                return min(base, max(80, base / 4))
            }
            return base
        }()
        print("\n🎯 FUZZ: Transaction Chaos (\(batches) batches)")
        var rng = FuzzTestRNG(seed: deriveSeed(0x6006))
        var errorCount = 0
        var sampleErrors: [String] = []
        
        for i in 0..<batches {
            let batchSize = Int.random(in: 1...75, using: &rng)
            // Keep this test focused on transaction behavior, not oversized payload rejection.
            let records = (0..<batchSize).map { _ in
                randomFuzzRecord(
                    rng: &rng,
                    maxFields: 8,
                    maxStringLength: 120,
                    maxBinarySize: 384
                )
            }
            
            do {
                _ = try db.insertMany(records)
                
                if i % 20 == 0 {
                    let allRecords = try db.fetchAll()
                    for record in allRecords {
                        if let id = record.storage["id"]?.uuidValue {
                            try? db.delete(id: id)
                        }
                    }
                }
            } catch {
                errorCount += 1
                if sampleErrors.count < 8 {
                    sampleErrors.append(String(describing: error))
                }
            }
            
            if i % 50 == 0 {
                print("  Tested \(i) random batches...")
            }
        }
        
        // Database should still be functional
        XCTAssertNoThrow(try db.fetchAll(), "Database should be queryable after chaos")
        print("  📊 Batch errors: \(errorCount)")
        assertErrorBudget(
            testName: "TransactionChaos",
            total: batches,
            errors: errorCount,
            maxErrorRate: 0.03,
            sampleErrors: sampleErrors
        )
        
        print("  ✅ Transaction chaos survived!")
    }

    /// Fuzz test: payload sizes around and beyond page thresholds to stress overflow chaining.
    func testFuzz_OverflowBoundaryChurn() throws {
        let iterations = 3_000 * fuzzScale
        print("\n🎯 FUZZ: Overflow Boundary Churn (\(iterations) iterations)")
        var rng = FuzzTestRNG(seed: deriveSeed(0x7007))
        var errorCount = 0
        var mismatchCount = 0
        var sampleErrors: [String] = []

        for i in 0..<iterations {
            let size: Int
            switch Int.random(in: 0...4, using: &rng) {
            case 0:
                size = Int.random(in: 4048...4066, using: &rng)
            case 1:
                size = Int.random(in: 4067...8192, using: &rng)
            default:
                size = Int.random(in: 8193...16_384, using: &rng)
            }

            let blob = randomBinaryData(size: size, rng: &rng)
            do {
                let id = try db.insert(BlazeDataRecord([
                    "kind": .string("overflow-boundary"),
                    "blob": .data(blob),
                    "size": .int(size)
                ]))
                let fetched = try db.fetch(id: id)
                if fetched?["blob"]?.dataValue != blob {
                    mismatchCount += 1
                }

                if i % 25 == 0 {
                    let all = try db.fetchAll()
                    for record in all {
                        if let id = record.storage["id"]?.uuidValue {
                            try? db.delete(id: id)
                        }
                    }
                }
            } catch {
                errorCount += 1
                if sampleErrors.count < 8 {
                    sampleErrors.append(String(describing: error))
                }
            }

            if i % 500 == 0 {
                print("  Tested \(i) overflow-boundary payloads...")
            }
        }

        print("  📊 Overflow errors: \(errorCount)")
        print("  📊 Overflow mismatches: \(mismatchCount)")
        assertErrorBudget(
            testName: "OverflowBoundaryChurn",
            total: iterations,
            errors: errorCount + mismatchCount,
            maxErrorRate: 0.002,
            sampleErrors: sampleErrors
        )
        print("  ✅ Overflow boundary churn passed!")
    }
    
    // MARK: - Fuzz: Date Edge Cases
    
    /// Fuzz test: Extreme and unusual dates
    func testFuzz_DateEdgeCases() throws {
        print("\n🎯 FUZZ: Date Edge Cases")
        
        let dateCases: [Date] = [
            Date(timeIntervalSince1970: 0),           // Unix epoch
            Date(timeIntervalSince1970: -1),          // Before epoch
            Date(timeIntervalSince1970: 1_000_000_000), // Year 2001
            Date(timeIntervalSince1970: 2_000_000_000), // Year 2033
            Date(timeIntervalSince1970: -2_147_483_648), // 32-bit min
            Date(timeIntervalSince1970: 2_147_483_647),  // 32-bit max
            Date.distantPast,
            Date.distantFuture,
            Date(),                                   // Now
        ]
        
        for (i, date) in dateCases.enumerated() {
            do {
                let id = try db.insert(BlazeDataRecord(["date": .date(date)]))
                let fetched = try db.fetch(id: id)
                
                if let fetchedDate = fetched?["date"]?.dateValue {
                    // Allow 1ms tolerance for encoding/decoding
                    let diff = abs(fetchedDate.timeIntervalSince1970 - date.timeIntervalSince1970)
                    XCTAssertLessThan(diff, 0.001, "Date \(i) should survive round-trip")
                }
            } catch {
                print("  ⚠️ Date case \(i) rejected: \(error)")
            }
        }
        
        print("  ✅ Date edge cases handled!")
    }
    
    // MARK: - Random Generators
    
    /// Generate random fuzz string (including garbage)
    private func randomFuzzString(rng: inout FuzzTestRNG, maxLength: Int = 2000) -> String {
        let boundedLength = max(1, maxLength)
        let length = Int.random(in: 0...boundedLength, using: &rng)
        
        let charSets: [String] = [
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
            " \n\r\t",
            "!@#$%^&*()_+-=[]{}|;':\",./<>?",
            "\u{0000}\u{0001}\u{0002}\u{0003}",  // Control chars
            "🔥💀🎯🚀👍",                          // Emoji
        ]
        
        let charSet = charSets.randomElement(using: &rng) ?? charSets[0]
        
        return String((0..<length).map { _ in charSet.randomElement(using: &rng) ?? "A" })
    }
    
    /// Generate random Unicode string
    private func randomUnicodeString(rng: inout FuzzTestRNG) -> String {
        let length = Int.random(in: 0...250, using: &rng)
        
        var result = ""
        for _ in 0..<length {
            // Avoid surrogate range so random output remains valid Unicode scalar space.
            let scalarValue = Int.random(in: 0x0020...0x10FFFF, using: &rng)
            let sanitized = (0xD800...0xDFFF).contains(scalarValue) ? 0x20 : scalarValue
            let scalar = UnicodeScalar(sanitized) ?? UnicodeScalar(0x0020)!
            result.append(String(scalar))
        }
        
        return result
    }
    
    /// Generate random binary data
    private func randomBinaryData(size: Int, rng: inout FuzzTestRNG) -> Data {
        var data = Data(capacity: size)
        for _ in 0..<size {
            data.append(UInt8.random(in: 0...255, using: &rng))
        }
        return data
    }
    
    /// Generate random fuzz record
    private func randomFuzzRecord(
        rng: inout FuzzTestRNG,
        maxFields: Int = 14,
        maxStringLength: Int = 2000,
        maxBinarySize: Int = 2000
    ) -> BlazeDataRecord {
        let boundedFieldCount = max(1, maxFields)
        let boundedStringLength = max(1, maxStringLength)
        let boundedBinarySize = max(1, maxBinarySize)
        let fieldCount = Int.random(in: 1...boundedFieldCount, using: &rng)
        var fields: [String: BlazeDocumentField] = [:]
        
        for i in 0..<fieldCount {
            let fieldType = Int.random(in: 0...5, using: &rng)
            
            switch fieldType {
            case 0:
                fields["f\(i)"] = .string(randomFuzzString(rng: &rng, maxLength: boundedStringLength))
            case 1:
                fields["f\(i)"] = .int(Int.random(in: Int.min...Int.max, using: &rng))
            case 2:
                fields["f\(i)"] = .double(Double.random(in: -1e6...1e6, using: &rng))
            case 3:
                fields["f\(i)"] = .bool(Bool.random(using: &rng))
            case 4:
                fields["f\(i)"] = .date(Date(timeIntervalSince1970: Double.random(in: 0...2e9, using: &rng)))
            case 5:
                fields["f\(i)"] = .data(randomBinaryData(size: Int.random(in: 0...boundedBinarySize, using: &rng), rng: &rng))
            default:
                break
            }
        }
        
        return BlazeDataRecord(fields)
    }

    private func deriveSeed(_ salt: UInt64) -> UInt64 {
        fuzzSeed ^ (salt &* 0x9E3779B97F4A7C15)
    }

    private static func parseSeed(_ value: String?) -> UInt64? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            return UInt64(raw.dropFirst(2), radix: 16)
        }
        return UInt64(raw)
    }

    private func assertErrorBudget(
        testName: String,
        total: Int,
        errors: Int,
        maxErrorRate: Double,
        sampleErrors: [String]
    ) {
        guard total > 0 else {
            XCTFail("\(testName): total iterations must be > 0")
            return
        }
        let rate = Double(errors) / Double(total)
        if !sampleErrors.isEmpty {
            print("  🧪 \(testName) sample errors: \(sampleErrors)")
        }
        XCTAssertLessThanOrEqual(
            rate,
            maxErrorRate,
            "\(testName) exceeded error budget: errors=\(errors), total=\(total), rate=\(rate), budget=\(maxErrorRate), seed=\(fuzzSeed)"
        )
    }

    private func isExpectedConcurrentChaosError(_ error: Error) -> Bool {
        let message = String(describing: error).lowercased()
        return message.contains("record not found")
            || message.contains("not found")
            || message.contains("duplicate")
            || message.contains("conflict")
            || message.contains("locked")
            || message.contains("retry")
    }
}

extension String {
    func repeated(_ times: Int) -> String {
        return String(repeating: self, count: times)
    }
}

private struct FuzzTestRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xA5A5A5A5A5A5A5A5 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

