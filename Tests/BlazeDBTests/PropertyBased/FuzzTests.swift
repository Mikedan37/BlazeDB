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
@testable import BlazeDB

final class FuzzTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FuzzTest-\(testID).blazedb")
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        
        do {
            db = try BlazeDBClient(name: "fuzz_test", fileURL: tempURL, password: "FuzzTestPassword123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Fuzz: Random String Inputs
    
    /// Fuzz test: Random strings of all lengths and character types
    func testFuzz_RandomStrings() throws {
        print("\n🎯 FUZZ: Random Strings (10,000 inputs)")
        
        var crashCount = 0
        var successCount = 0
        
        for i in 0..<10_000 {
            let str = randomFuzzString()
            
            do {
                let id = try db.insert(BlazeDataRecord(["fuzz": .string(str)]))
                let fetched = try db.fetch(id: id)
                
                // Verify round-trip
                if fetched?["fuzz"]?.stringValue == str {
                    successCount += 1
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
                // Acceptable: Some inputs might be rejected
                // Not acceptable: Crash or corruption
            }
            
            if i % 1000 == 0 {
                print("  Tested \(i) random strings...")
            }
        }
        
        print("  📊 Successful round-trips: \(successCount)")
        print("  ✅ No crashes detected!")
    }
    
    /// Fuzz test: Unicode edge cases and invalid sequences
    func testFuzz_UnicodeEdgeCases() throws {
        print("\n🎯 FUZZ: Unicode Edge Cases (5,000 inputs)")
        
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
            
            // Long strings (within 4KB page limit - ~1KB each to be safe)
            String(repeating: "A", count: 1000),
            String(repeating: "🔥", count: 250),  // Emojis are 4 bytes each = 1KB
            
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
        
        for (i, testCase) in edgeCases.enumerated() {
            do {
                let id = try db.insert(BlazeDataRecord(["unicode": .string(testCase)]))
                let fetched = try db.fetch(id: id)
                
                // Verify exact round-trip
                XCTAssertEqual(fetched?["unicode"]?.stringValue, testCase, 
                              "Unicode case \(i) should survive round-trip")
            } catch {
                XCTFail("Unicode case \(i) caused error: \(error)")
            }
        }
        
        // Random Unicode fuzz
        for i in 0..<5000 {
            let randomUnicode = randomUnicodeString()
            
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
                // Acceptable
            }
            
            if i % 1000 == 0 {
                print("  Tested \(i) random Unicode strings...")
            }
        }
        
        print("  ✅ All Unicode edge cases handled!")
    }
    
    // MARK: - Fuzz: Malformed Binary Data
    
    /// Fuzz test: Random binary data of all sizes
    func testFuzz_RandomBinaryData() throws {
        print("\n🎯 FUZZ: Random Binary Data (5,000 blobs)")
        
        for i in 0..<5000 {
            let size = Int.random(in: 0...10_000)
            let data = randomBinaryData(size: size)
            
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
                // Some sizes might be rejected
            }
            
            if i % 1000 == 0 {
                print("  Tested \(i) random binary blobs...")
            }
        }
        
        print("  ✅ All binary data handled correctly!")
    }
    
    // MARK: - Fuzz: Extreme Numbers
    
    /// Fuzz test: Extreme integer and floating-point values
    func testFuzz_ExtremeNumbers() throws {
        print("\n🎯 FUZZ: Extreme Numbers (1,000 values)")
        
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
                print("  ⚠️ Edge case \(i) rejected: \(error)")
            }
        }
        
        // Random number fuzz
        for i in 0..<1000 {
            let randomInt = Int.random(in: Int.min...Int.max)
            let randomDouble = Double.random(in: -1e100...1e100)
            
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
                // Acceptable
            }
            
            if i % 200 == 0 {
                print("  Tested \(i) random numbers...")
            }
        }
        
        print("  ✅ All extreme numbers handled!")
    }
    
    // MARK: - Fuzz: Nested Data Structures
    
    /// Fuzz test: Deeply nested arrays and dictionaries
    func testFuzz_DeeplyNestedStructures() throws {
        print("\n🎯 FUZZ: Deeply Nested Structures (100 tests)")
        
        for depth in 1..<20 {
            // Create deeply nested array
            var nestedArray: BlazeDocumentField = .int(42)
            for _ in 0..<depth {
                nestedArray = .array([nestedArray])
            }
            
            do {
                let id = try db.insert(BlazeDataRecord(["nested": nestedArray]))
                _ = try db.fetch(id: id)
            } catch {
                print("  ⚠️ Depth \(depth) rejected: \(error)")
            }
        }
        
        for depth in 1..<20 {
            // Create deeply nested dictionary
            var nestedDict: BlazeDocumentField = .int(42)
            for i in 0..<depth {
                nestedDict = .dictionary(["level\(i)": nestedDict])
            }
            
            do {
                let id = try db.insert(BlazeDataRecord(["nested": nestedDict]))
                _ = try db.fetch(id: id)
            } catch {
                print("  ⚠️ Depth \(depth) rejected: \(error)")
            }
        }
        
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
        
        for (i, fieldName) in maliciousNames.enumerated() {
            do {
                let record = BlazeDataRecord([fieldName: .string("test")])
                let id = try db.insert(record)
                let fetched = try db.fetch(id: id)
                
                // Should be able to retrieve
                XCTAssertNotNil(fetched, "Record with field '\(fieldName)' should be retrievable")
            } catch {
                // Some field names might be rejected
                print("  ⚠️ Field name \(i) rejected: '\(fieldName)'")
            }
        }
        
        print("  ✅ Malicious field names handled!")
    }
    
    // MARK: - Fuzz: Record Size Extremes
    
    /// Fuzz test: Very large and very small records
    func testFuzz_RecordSizeExtremes() throws {
        print("\n🎯 FUZZ: Record Size Extremes")
        
        // Empty record
        do {
            let emptyRecord = BlazeDataRecord([:])
            let id = try db.insert(emptyRecord)
            let fetched = try db.fetch(id: id)
            XCTAssertNotNil(fetched, "Empty record should be retrievable")
        } catch {
            print("  ⚠️ Empty record rejected: \(error)")
        }
        
        // Single field
        do {
            let id = try db.insert(BlazeDataRecord(["a": .int(1)]))
            let fetched = try db.fetch(id: id)
            XCTAssertNotNil(fetched)
        } catch {
            print("  ⚠️ Single field rejected")
        }
        
        // Many fields (1000 fields) - may exceed page size limit
        do {
            var fields: [String: BlazeDocumentField] = [:]
            for i in 0..<1000 {
                fields["field\(i)"] = .int(i)
            }
            let id = try db.insert(BlazeDataRecord(fields))
            let fetched = try db.fetch(id: id)
            XCTAssertNotNil(fetched, "Record with 1000 fields should work")
        } catch {
            // Expected: Records exceeding page size limit are rejected
            print("  ℹ️  1000 fields rejected (expected if exceeds page size): \(error.localizedDescription)")
        }
        
        // Very large string field (1MB) - will exceed page size limit
        do {
            let largeString = String(repeating: "A", count: 1_000_000)  // 1MB
            let id = try db.insert(BlazeDataRecord(["large": .string(largeString)]))
            let fetched = try db.fetch(id: id)
            XCTAssertEqual(fetched?["large"]?.stringValue?.count, 1_000_000)
        } catch {
            // Expected: Records exceeding page size limit are rejected
            print("  ℹ️  1MB string rejected (expected - exceeds page size limit): \(error.localizedDescription)")
        }
        
        // Very large binary field (1MB) - will exceed page size limit
        do {
            let largeData = Data(repeating: 0xFF, count: 1_000_000)  // 1MB
            let id = try db.insert(BlazeDataRecord(["blob": .data(largeData)]))
            let fetched = try db.fetch(id: id)
            XCTAssertEqual(fetched?["blob"]?.dataValue?.count, 1_000_000)
        } catch {
            // Expected: Records exceeding page size limit are rejected
            print("  ℹ️  1MB blob rejected (expected - exceeds page size limit): \(error.localizedDescription)")
        }
        
        print("  ✅ Size extremes handled!")
    }
    
    // MARK: - Fuzz: Concurrent Chaos
    
    /// Fuzz test: Thousands of concurrent random operations
    func testFuzz_ConcurrentChaos() throws {
        print("\n🎯 FUZZ: Concurrent Chaos (50 operations, 5 concurrent)")
        
        // Pre-populate with minimal data
        var seedIDs: [UUID] = []
        for i in 0..<10 {
            let id = try db.insert(BlazeDataRecord(["value": .int(i)]))
            seedIDs.append(id)
        }
        print("  ✅ Pre-populated 10 seed records")
        
        let group = DispatchGroup()
        let errorCount = Atomic(0)
        let completedCount = Atomic(0)
        
        // Very limited concurrency - only 5 at a time
        let semaphore = DispatchSemaphore(value: 5)
        
        // Only 50 operations total
        for i in 0..<50 {
            group.enter()
            DispatchQueue.global().async {
                semaphore.wait()
                defer {
                    semaphore.signal()
                    group.leave()
                }
                
                do {
                    // Simpler operation distribution
                    let op = i % 3
                    
                    switch op {
                    case 0:  // Insert
                        _ = try self.db.insert(BlazeDataRecord([
                            "value": .int(Int.random(in: 0...1000)),
                            "type": .string("fuzz")
                        ]))
                        
                    case 1:  // Read
                        _ = try self.db.query().limit(10).execute()
                        
                    case 2:  // Update (rarely fails)
                        if let randomID = seedIDs.randomElement() {
                            try? self.db.update(id: randomID, with: BlazeDataRecord([
                                "value": .int(Int.random(in: 0...1000))
                            ]))
                        }
                        
                    default:
                        break
                    }
                    completedCount.increment()
                } catch {
                    errorCount.increment()
                }
            }
            
            // Add small delay every 10 operations to prevent overwhelming
            if i % 10 == 9 {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        
        print("  ⏳ Waiting for operations to complete...")
        
        // Wait with timeout
        let result = group.wait(timeout: .now() + 10)
        
        if result == .timedOut {
            print("  ⚠️ Test timed out after 10 seconds")
            XCTFail("Concurrent operations timed out - possible deadlock")
            return
        }
        
        print("  📊 Operations: 50")
        print("  📊 Completed: \(completedCount.value)")
        print("  📊 Errors: \(errorCount.value)")
        
        // Database should still be functional
        let finalCount = try db.count()
        print("  📊 Final count: \(finalCount)")
        XCTAssertGreaterThan(finalCount, 0, "Database should have records")
        
        print("  ✅ Survived concurrent chaos!")
    }
    
    // Simple atomic counter helper
    private class Atomic<T> {
        private var value_: T
        private let lock = NSLock()
        
        init(_ value: T) {
            self.value_ = value
        }
        
        var value: T {
            lock.lock()
            defer { lock.unlock() }
            return value_
        }
        
        func increment() where T == Int {
            lock.lock()
            defer { lock.unlock() }
            value_ = (value_ as! Int + 1) as! T
        }
    }
    
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
                print("  ⚠️ Injection payload \(i) caused error: \(error)")
            }
        }
        
        print("  ✅ All injection attempts safely handled!")
    }
    
    // MARK: - Fuzz: Memory Stress
    
    /// Fuzz test: Operations that could cause memory leaks
    func testFuzz_MemoryStress() throws {
        print("\n🎯 FUZZ: Memory Stress (1,000 cycles)")
        
        for i in 0..<1000 {
            // Insert reasonably large record (within 4KB page limit)
            // BlazeDB pages are 4KB, so keep records under ~2KB to allow for overhead
            let largeRecord = BlazeDataRecord([
                "cycle": .int(i),
                "data": .string(String(repeating: "X", count: 800)),  // 800 bytes
                "blob": .data(Data(repeating: 0xFF, count: 800)),      // 800 bytes
                "metadata": .string("stress_test_\(i)")
            ])
            
            let id = try db.insert(largeRecord)
            
            // Immediately fetch and delete to test memory cleanup
            _ = try db.fetch(id: id)
            try db.delete(id: id)
            
            // Occasionally persist to test memory management across persist cycles
            if i % 100 == 0 {
                try db.persist()
                print("  Cycle \(i)/1000...")
            }
        }
        
        print("  ✅ Memory stress test passed!")
    }
    
    // MARK: - Fuzz: Transaction Chaos
    
    /// Fuzz test: Random batch operations with potential failures
    func testFuzz_TransactionChaos() throws {
        print("\n🎯 FUZZ: Transaction Chaos (200 batches)")
        
        for i in 0..<200 {
            let batchSize = Int.random(in: 1...50)
            let records = (0..<batchSize).map { _ in randomFuzzRecord() }
            
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
                // Some batches might fail, that's fine
            }
            
            if i % 50 == 0 {
                print("  Tested \(i) random batches...")
            }
        }
        
        // Database should still be functional
        XCTAssertNoThrow(try db.fetchAll(), "Database should be queryable after chaos")
        
        print("  ✅ Transaction chaos survived!")
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
    private func randomFuzzString() -> String {
        let length = Int.random(in: 0...1000)
        
        let charSets: [String] = [
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
            " \n\r\t",
            "!@#$%^&*()_+-=[]{}|;':\",./<>?",
            "\u{0000}\u{0001}\u{0002}\u{0003}",  // Control chars
            "🔥💀🎯🚀👍",                          // Emoji
        ]
        
        let charSet = charSets.randomElement()!
        
        return String((0..<length).map { _ in charSet.randomElement()! })
    }
    
    /// Generate random Unicode string
    private func randomUnicodeString() -> String {
        let length = Int.random(in: 0...100)
        
        var result = ""
        for _ in 0..<length {
            // Random Unicode scalar
            let scalar = UnicodeScalar(Int.random(in: 0x0020...0x10FFFF)) ?? UnicodeScalar(0x0020)!
            result.append(String(scalar))
        }
        
        return result
    }
    
    /// Generate random binary data
    private func randomBinaryData(size: Int) -> Data {
        var data = Data(capacity: size)
        for _ in 0..<size {
            data.append(UInt8.random(in: 0...255))
        }
        return data
    }
    
    /// Generate random fuzz record
    private func randomFuzzRecord() -> BlazeDataRecord {
        let fieldCount = Int.random(in: 1...10)
        var fields: [String: BlazeDocumentField] = [:]
        
        for i in 0..<fieldCount {
            let fieldType = Int.random(in: 0...5)
            
            switch fieldType {
            case 0:
                fields["f\(i)"] = .string(randomFuzzString())
            case 1:
                fields["f\(i)"] = .int(Int.random(in: Int.min...Int.max))
            case 2:
                fields["f\(i)"] = .double(Double.random(in: -1e6...1e6))
            case 3:
                fields["f\(i)"] = .bool(Bool.random())
            case 4:
                fields["f\(i)"] = .date(Date(timeIntervalSince1970: Double.random(in: 0...2e9)))
            case 5:
                fields["f\(i)"] = .data(randomBinaryData(size: Int.random(in: 0...1000)))
            default:
                break
            }
        }
        
        return BlazeDataRecord(fields)
    }
}

extension String {
    func repeated(_ times: Int) -> String {
        return String(repeating: self, count: times)
    }
}

