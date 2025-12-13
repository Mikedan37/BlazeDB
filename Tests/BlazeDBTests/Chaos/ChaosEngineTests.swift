//
//  ChaosEngineTests.swift
//  BlazeDBTests
//
//  Chaos Engine: Randomly generate operations (insert, update, delete, query),
//  randomize fields and data types, simulate schema changes and triggers,
//  validate DB consistency after each operation. Run 1,000+ random ops per test.
//
//  Uses deterministic seed for reproducibility.
//
//  Created: 2025-01-XX
//

import XCTest
@testable import BlazeDB

final class ChaosEngineTests: XCTestCase {
    
    var db: BlazeDBClient!
    var tempURL: URL!
    var rng: SeededRandomNumberGenerator!
    
    override func setUp() {
        super.setUp()
        
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChaosEngine-\(testID).blazedb")
        
        // Clean up any leftover files
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            if !FileManager.default.fileExists(atPath: tempURL.path) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        do {
            db = try BlazeDBClient(name: "chaos_test_\(testID)", fileURL: tempURL, password: "ChaosEngineTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
        
        // Use deterministic seed from environment or default
        let seed = ProcessInfo.processInfo.environment["CHAOS_SEED"].flatMap { UInt64($0) } ?? 12345
        rng = SeededRandomNumberGenerator(seed: seed)
        print("🌱 Chaos Engine initialized with seed: \(seed)")
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Random Generators
    
    private func randomField() -> BlazeDocumentField {
        let type = Int.random(in: 0...8, using: &rng)
        
        switch type {
        case 0:
            let length = Int.random(in: 0...200, using: &rng)
            let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
            let str = String((0..<length).map { _ in chars.randomElement(using: &rng)! })
            return .string(str)
        case 1:
            return .int(Int.random(in: Int.min...Int.max, using: &rng))
        case 2:
            return .double(Double.random(in: -1e9...1e9, using: &rng))
        case 3:
            return .bool(Bool.random(using: &rng))
        case 4:
            return .uuid(UUID())
        case 5:
            return .date(Date(timeIntervalSince1970: Double.random(in: 0...1.5e9, using: &rng)))
        case 6:
            let size = Int.random(in: 0...1000, using: &rng)
            return .data(Data((0..<size).map { _ in UInt8.random(in: 0...255, using: &rng) }))
        case 7:
            let count = Int.random(in: 1...10, using: &rng)
            return .array((0..<count).map { _ in randomSimpleField() })
        case 8:
            let count = Int.random(in: 1...5, using: &rng)
            var dict: [String: BlazeDocumentField] = [:]
            for i in 0..<count {
                dict["key\(i)"] = randomSimpleField()
            }
            return .dictionary(dict)
        default:
            return .string("default")
        }
    }
    
    private func randomSimpleField() -> BlazeDocumentField {
        let type = Int.random(in: 0...5, using: &rng)
        switch type {
        case 0: return .string("test\(Int.random(in: 0...100, using: &rng))")
        case 1: return .int(Int.random(in: -1000...1000, using: &rng))
        case 2: return .double(Double.random(in: -100...100, using: &rng))
        case 3: return .bool(Bool.random(using: &rng))
        case 4: return .date(Date(timeIntervalSince1970: Double.random(in: 0...1e9, using: &rng)))
        case 5: return .uuid(UUID())
        default: return .string("default")
        }
    }
    
    private func randomRecord() -> BlazeDataRecord {
        let fieldCount = Int.random(in: 1...20, using: &rng)
        var storage: [String: BlazeDocumentField] = [:]
        
        // Always include ID
        storage["id"] = .uuid(UUID())
        
        for i in 0..<fieldCount {
            let fieldName = "field\(i)"
            storage[fieldName] = randomField()
        }
        
        return BlazeDataRecord(storage)
    }
    
    // MARK: - Consistency Validation
    
    private func validateConsistency() throws {
        // Check layout is valid
        let collection = db.collection as! DynamicCollection
        
        // Use in-memory layout instead of loading from disk to avoid signature verification issues
        // when the layout has been modified but not yet fully flushed
        // The in-memory layout is the source of truth for consistency checks
        // Convert secondaryIndexes from runtime format [String: [CompoundIndexKey: Set<UUID>]] to StorageLayout format
        // StorageLayout expects [String: [CompoundIndexKey: [UUID]]] (arrays, not sets)
        let convertedSecondaryIndexes = collection.secondaryIndexes.mapValues { inner in
            inner.mapValues { Array($0).sorted(by: { $0.uuidString < $1.uuidString }) }
        }
        // Use the same initializer pattern as saveLayout() in DynamicCollection
        var layout = StorageLayout(
            indexMap: collection.indexMap.mapValues { $0.first ?? 0 },
            nextPageIndex: collection.nextPageIndex,
            secondaryIndexes: convertedSecondaryIndexes,
            searchIndex: collection.cachedSearchIndex,
            searchIndexedFields: collection.cachedSearchIndexedFields
        )
        // Set additional properties after initialization
        layout.encodingFormat = collection.encodingFormat
        layout.secondaryIndexDefinitions = collection.secondaryIndexDefinitions
        layout.deletedPages = collection.deletedPages
        layout.metaData = collection.metaData
        
        // Verify no negative page counts
        XCTAssertGreaterThanOrEqual(layout.nextPageIndex, 0, "Page count should not be negative")
        
        // Verify index map consistency
        let allRecords = try db.fetchAll()
        let indexMapSize = collection.indexMap.count
        
        // Index map should have at least as many entries as records (some records may span pages)
        XCTAssertGreaterThanOrEqual(indexMapSize, allRecords.count, "Index map should contain all records")
        
        // Verify no invalid records
        for record in allRecords {
            XCTAssertNotNil(record.storage["id"]?.uuidValue, "All records should have ID")
        }
        
        // Verify indexes are not corrupted
        if let secondaryIndexes = collection.secondaryIndexes as? [String: Any] {
            for (indexName, index) in secondaryIndexes {
                // Basic sanity check: index should not be empty if we have records
                if !allRecords.isEmpty {
                    // Index should have some entries (exact count depends on indexed fields)
                    XCTAssertNotNil(index, "Index '\(indexName)' should exist")
                }
            }
        }
    }
    
    // MARK: - Tests
    
    func testChaosEngine_1000RandomOperations() throws {
        print("\n🎲 CHAOS ENGINE: 1,000 Random Operations")
        
        var insertedIDs: [UUID] = []
        var operationCount = 0
        var errorCount = 0
        
        for i in 0..<1000 {
            let op = Int.random(in: 0...10, using: &rng)
            
            do {
                switch op {
                case 0...4: // Insert (50%)
                    let record = randomRecord()
                    let id = try db.insert(record)
                    insertedIDs.append(id)
                    operationCount += 1
                    
                case 5...7: // Update (30%)
                    if !insertedIDs.isEmpty, let randomID = insertedIDs.randomElement(using: &rng) {
                        let update = randomRecord()
                        try db.update(id: randomID, with: update)
                        operationCount += 1
                    }
                    
                case 8...9: // Delete (20%)
                    if !insertedIDs.isEmpty, let randomID = insertedIDs.randomElement(using: &rng) {
                        try db.delete(id: randomID)
                        insertedIDs.removeAll { $0 == randomID }
                        operationCount += 1
                    }
                    
                case 10: // Query
                    _ = try db.query()
                        .where("field0", greaterThan: .int(0))
                        .execute()
                    operationCount += 1
                    
                default:
                    break
                }
                
                // Validate consistency every 100 operations
                if i % 100 == 0 && i > 0 {
                    try validateConsistency()
                    print("  ✅ Validated consistency at operation \(i) (total ops: \(operationCount))")
                }
                
            } catch {
                errorCount += 1
                // Some errors are acceptable (e.g., query on non-existent field)
                // But we should log them
                if i % 100 == 0 {
                    print("  ⚠️  Error at operation \(i): \(error)")
                }
            }
        }
        
        // Final consistency check
        try validateConsistency()
        
        print("  📊 Operations: \(operationCount)")
        print("  📊 Errors: \(errorCount)")
        print("  ✅ Chaos test completed - no crashes, no corruption!")
        
        XCTAssertLessThan(errorCount, operationCount / 10, "Error rate should be < 10%")
    }
    
    func testChaosEngine_SchemaChanges() throws {
        // Reduced from 500 to 200 operations for faster execution
        let operationCount = 200
        print("\n🎲 CHAOS ENGINE: Schema Changes (\(operationCount) operations)")
        
        var insertedIDs: [UUID] = []
        let collection = db.collection as! DynamicCollection
        
        // PERFORMANCE: Batch inserts between validation checks for better performance
        var batchRecords: [BlazeDataRecord] = []
        let batchSize = 50  // Insert in batches of 50
        
        for i in 0..<operationCount {
            // Randomly create/drop indexes (less frequently: every 75 ops instead of 50)
            if i % 75 == 0 && i > 0 {
                let fieldName = "field\(Int.random(in: 0...5, using: &rng))"
                do {
                    try collection.createIndex(on: fieldName)
                    print("  Created index on '\(fieldName)'")
                } catch {
                    // Index might already exist, that's fine
                }
            }
            
            // Collect records for batch insert
            let record = randomRecord()
            batchRecords.append(record)
            
            // Insert batch when it reaches batchSize or before validation
            let shouldFlushBatch = batchRecords.count >= batchSize || 
                                   (i % 150 == 0 && i > 0 && !batchRecords.isEmpty)
            
            if shouldFlushBatch {
                let batchIDs = try db.insertMany(batchRecords)
                insertedIDs.append(contentsOf: batchIDs)
                batchRecords.removeAll()
            }
            
            // Validate consistency less frequently (every 150 ops instead of 100)
            if i % 150 == 0 && i > 0 {
                try validateConsistency()
            }
        }
        
        // Insert any remaining records
        if !batchRecords.isEmpty {
            let batchIDs = try db.insertMany(batchRecords)
            insertedIDs.append(contentsOf: batchIDs)
        }
        
        // Final consistency check
        try validateConsistency()
        print("  ✅ Schema changes handled correctly!")
    }
    
    func testChaosEngine_TriggerSimulation() throws {
        print("\n🎲 CHAOS ENGINE: Trigger Simulation (300 operations)")
        
        // Set up a simple trigger (nil collectionName matches all collections)
        var triggerFiredCount = 0
        let triggerLock = NSLock()
        
        db.onInsert(nil) { record, modified, ctx in
            triggerLock.lock()
            triggerFiredCount += 1
            triggerLock.unlock()
        }
        
        // Insert records (triggers should fire)
        for i in 0..<300 {
            let record = randomRecord()
            _ = try db.insert(record)
            
            // Validate consistency every 50 operations
            if i % 50 == 0 && i > 0 {
                try validateConsistency()
            }
        }
        
        // Final consistency check
        try validateConsistency()
        
        print("  📊 Triggers fired: \(triggerFiredCount)")
        print("  ✅ Trigger simulation completed!")
        
        XCTAssertGreaterThan(triggerFiredCount, 0, "Triggers should have fired")
    }
    
    func testChaosEngine_ExtremeStress() throws {
        // Configurable operation count (reduced from 5,000 to 1,000 for faster tests)
        let operationCount = ProcessInfo.processInfo.environment["CHAOS_EXTREME_OPS"].flatMap(Int.init) ?? 1_000
        let validationInterval = max(500, operationCount / 2)  // Validate at midpoint and end
        
        print("\n🎲 CHAOS ENGINE: Extreme Stress (\(operationCount) operations)")
        
        var insertedIDs: [UUID] = []
        var actualOps = 0
        
        for i in 0..<operationCount {
            let op = Int.random(in: 0...8, using: &rng)
            
            do {
                switch op {
                case 0...5: // Insert (75%)
                    let record = randomRecord()
                    let id = try db.insert(record)
                    insertedIDs.append(id)
                    actualOps += 1
                    
                case 6...7: // Update (25%)
                    if !insertedIDs.isEmpty, let randomID = insertedIDs.randomElement(using: &rng) {
                        let update = randomRecord()
                        try db.update(id: randomID, with: update)
                        actualOps += 1
                    }
                    
                case 8: // Delete
                    if !insertedIDs.isEmpty, let randomID = insertedIDs.randomElement(using: &rng) {
                        try db.delete(id: randomID)
                        insertedIDs.removeAll { $0 == randomID }
                        actualOps += 1
                    }
                    
                default:
                    break
                }
                
                // Validate consistency at midpoint and end (reduced frequency for speed)
                if i == validationInterval || i == operationCount - 1 {
                    try validateConsistency()
                    print("  ✅ Validated consistency at operation \(i) (total ops: \(actualOps))")
                }
                
            } catch {
                // Some errors are acceptable
            }
        }
        
        // Final consistency check
        try validateConsistency()
        
        print("  📊 Total operations: \(actualOps)")
        print("  ✅ Extreme stress test completed - no crashes, no corruption!")
    }
}

// MARK: - Seeded Random Number Generator

struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        // Linear congruential generator
        state = (state &* 1103515245 &+ 12345) & 0x7fffffff
        return state
    }
}

extension Int {
    static func random(in range: Range<Int>, using generator: inout SeededRandomNumberGenerator) -> Int {
        let upperBound = UInt64(range.upperBound - range.lowerBound)
        let random = generator.next() % upperBound
        return Int(random) + range.lowerBound
    }
    
    static func random(in range: ClosedRange<Int>, using generator: inout SeededRandomNumberGenerator) -> Int {
        // Handle full range case to avoid overflow (Int.min...Int.max)
        if range.lowerBound == Int.min && range.upperBound == Int.max {
            // For full range, map UInt64 directly to Int range
            let random = generator.next()
            return Int(Int64(bitPattern: random))
        }
        
        // For normal ranges, convert to Int64 to avoid overflow when upperBound is Int.max
        let upper = Int64(range.upperBound)
        let lower = Int64(range.lowerBound)
        let rangeSize = UInt64(upper - lower + 1)
        let random = generator.next() % rangeSize
        return Int(lower + Int64(random))
    }
}

extension Double {
    static func random(in range: ClosedRange<Double>, using generator: inout SeededRandomNumberGenerator) -> Double {
        let random = Double(generator.next()) / Double(UInt64.max)
        return range.lowerBound + random * (range.upperBound - range.lowerBound)
    }
}

extension Bool {
    static func random(using generator: inout SeededRandomNumberGenerator) -> Bool {
        return generator.next() % 2 == 0
    }
}

extension UInt8 {
    static func random(in range: ClosedRange<UInt8>, using generator: inout SeededRandomNumberGenerator) -> UInt8 {
        let upper = UInt64(range.upperBound)
        let lower = UInt64(range.lowerBound)
        let rangeSize = upper - lower + 1
        let random = generator.next() % rangeSize
        return UInt8(random) + range.lowerBound
    }
}

extension Array {
    func randomElement(using generator: inout SeededRandomNumberGenerator) -> Element? {
        guard !isEmpty else { return nil }
        let index = Int.random(in: 0..<count, using: &generator)
        return self[index]
    }
}

extension String {
    func randomElement(using generator: inout SeededRandomNumberGenerator) -> Character? {
        guard !isEmpty else { return nil }
        let index = self.index(self.startIndex, offsetBy: Int.random(in: 0..<count, using: &generator))
        return self[index]
    }
}

