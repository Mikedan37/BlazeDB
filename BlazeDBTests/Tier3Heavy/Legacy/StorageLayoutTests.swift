//  StorageLayoutTests.swift
//  Tests for StorageLayout operations
//
//  TIER 3 — Legacy / Internal / Non-blocking
//  This test accesses internal StorageLayout APIs and storage layout structures.
//  It is NOT part of production gate tests and may fail without blocking releases.

import XCTest
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif
@testable import BlazeDBCore

final class StorageLayoutTests: XCTestCase {
    var tempURL: URL!
    var key: SymmetricKey!
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageLayout-\(UUID().uuidString).blazedb")
        key = SymmetricKey(size: .bits256)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
    }
    
    /// Test StorageLayout.rebuild(from:) can reconstruct index from pages
    func testRebuildFromDataPages() throws {
        let store = try PageStore(fileURL: tempURL, key: key)
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "Test", encryptionKey: key)
        
        // Insert records
        var insertedIDs: [UUID] = []
        for i in 0..<10 {
            let id = try collection.insert(BlazeDataRecord(["index": .int(i)]))
            insertedIDs.append(id)
        }
        
        try collection.persist()
        
        // Delete metadata to force rebuild
        try FileManager.default.removeItem(at: metaURL)
        
        // Rebuild from pages
        let rebuiltLayout = try StorageLayout.rebuild(from: store)
        
        XCTAssertEqual(rebuiltLayout.nextPageIndex, 10, "Should detect 10 pages")
        XCTAssertGreaterThan(rebuiltLayout.indexMap.count, 0, "Should rebuild some index entries")
    }
    
    /// Test StorageLayout save and load
    func testSaveAndLoadLayout() throws {
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        let originalLayout = StorageLayout(
            indexMap: [UUID(): [0], UUID(): [1]],
            nextPageIndex: 2,
            secondaryIndexes: [:]
        )
        
        try originalLayout.save(to: metaURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path))
        
        let loadedLayout = try StorageLayout.load(from: metaURL)
        
        XCTAssertEqual(loadedLayout.indexMap.count, 2)
        XCTAssertEqual(loadedLayout.nextPageIndex, 2)
        
        try? FileManager.default.removeItem(at: metaURL)
    }
    
    /// Test checksumMatchesStoredValue
    func testChecksumValidation() throws {
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        let layout = StorageLayout(
            indexMap: [UUID(): [0]],
            nextPageIndex: 1,
            secondaryIndexes: [:]
        )
        
        try layout.save(to: metaURL)
        
        let loaded = try StorageLayout.load(from: metaURL)
        
        XCTAssertTrue(loaded.checksumMatchesStoredValue(), "Checksum should match")
        
        try? FileManager.default.removeItem(at: metaURL)
    }
    
    /// Test headerIsValid
    func testHeaderValidation() throws {
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        let layout = StorageLayout(
            indexMap: [:],
            nextPageIndex: 0,
            secondaryIndexes: [:]
        )
        
        try layout.save(to: metaURL)
        let loaded = try StorageLayout.load(from: metaURL)
        
        XCTAssertTrue(loaded.headerIsValid(), "Header should be valid")
        
        try? FileManager.default.removeItem(at: metaURL)
    }
    
    /// Test toRuntimeIndexes conversion
    func testToRuntimeIndexesConversion() throws {
        let id1 = UUID()
        let id2 = UUID()
        
        let layout = StorageLayout(
            indexMap: [id1: [0], id2: [1]],
            nextPageIndex: 2,
            secondaryIndexes: [
                "status": [
                    CompoundIndexKey([AnyBlazeCodable("active")]): [id1, id2]
                ]
            ]
        )
        
        let runtimeIndexes = layout.toRuntimeIndexes()
        
        XCTAssertEqual(runtimeIndexes.count, 1)
        XCTAssertNotNil(runtimeIndexes["status"])
        
        let statusIndex = runtimeIndexes["status"]!
        let key = CompoundIndexKey([AnyBlazeCodable("active")])
        let ids = statusIndex[key]
        
        XCTAssertEqual(ids?.count, 2)
        XCTAssertTrue(ids?.contains(id1) ?? false)
        XCTAssertTrue(ids?.contains(id2) ?? false)
    }

    func testDecodeIndexMapFromNestedLegacyArrays() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let json = """
        {
          "indexMap": {
            "\(id.uuidString)": [[1], [2, 3]]
          },
          "nextPageIndex": 4
        }
        """
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StorageLayout.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.indexMap[id] ?? [], [1, 2, 3])
    }

    func testDecodeIndexMapFromMixedLegacyShapes() throws {
        let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let id3 = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let id4 = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let json = """
        {
          "indexMap": {
            "\(id1.uuidString)": 1,
            "\(id2.uuidString)": [2, 3],
            "\(id3.uuidString)": [[4], [5, 6]],
            "\(id4.uuidString)": "7"
          },
          "nextPageIndex": 8
        }
        """
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StorageLayout.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.indexMap[id1] ?? [], [1])
        XCTAssertEqual(decoded.indexMap[id2] ?? [], [2, 3])
        XCTAssertEqual(decoded.indexMap[id3] ?? [], [4, 5, 6])
        XCTAssertEqual(decoded.indexMap[id4] ?? [], [7])
    }

    func testSecureLayoutDecodesLegacyArrayIndexMapShape() throws {
        let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let json = """
        {
          "secureLayoutVersion": 1,
          "signature": "",
          "signedAt": 0,
          "layout": {
            "indexMap": [
              ["\(id1.uuidString)", [1, 2]],
              ["\(id2.uuidString)", [3]]
            ],
            "nextPageIndex": 4,
            "secondaryIndexes": {}
          }
        }
        """
        let decoder = JSONDecoder()
        let secureLayout = try decoder.decode(StorageLayout.SecureLayout.self, from: Data(json.utf8))
        XCTAssertEqual(secureLayout.layout.indexMap[id1] ?? [], [1, 2])
        XCTAssertEqual(secureLayout.layout.indexMap[id2] ?? [], [3])
        XCTAssertEqual(secureLayout.layout.nextPageIndex, 4)
    }

    func testSecureLayoutDecodesCurrentDictionaryIndexMapShape() throws {
        let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let json = """
        {
          "secureLayoutVersion": 1,
          "signature": "",
          "signedAt": 0,
          "layout": {
            "indexMap": {
              "\(id1.uuidString)": [4, 5],
              "\(id2.uuidString)": [6]
            },
            "nextPageIndex": 7,
            "secondaryIndexes": {}
          }
        }
        """
        let decoder = JSONDecoder()
        let secureLayout = try decoder.decode(StorageLayout.SecureLayout.self, from: Data(json.utf8))
        XCTAssertEqual(secureLayout.layout.indexMap[id1] ?? [], [4, 5])
        XCTAssertEqual(secureLayout.layout.indexMap[id2] ?? [], [6])
        XCTAssertEqual(secureLayout.layout.nextPageIndex, 7)
    }
}

