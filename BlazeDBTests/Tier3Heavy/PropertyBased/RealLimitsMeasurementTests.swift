import XCTest
@testable import BlazeDBCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

final class RealLimitsMeasurementTests: XCTestCase {

    func testMeasure_RealLimitsAndGrowth() throws {
        let blobMax = try measureMaxBlobBytes()
        let stringMax = try measureMaxStringBytes()
        let growth = try measureDatabaseGrowth()

        print("REAL_LIMIT_BLOB_MAX_BYTES=\(blobMax)")
        print("REAL_LIMIT_BLOB_MAX_MIB=\(String(format: "%.3f", bytesToMiB(blobMax)))")
        print("REAL_LIMIT_STRING_MAX_BYTES=\(stringMax)")
        print("REAL_LIMIT_STRING_MAX_MIB=\(String(format: "%.3f", bytesToMiB(stringMax)))")
        print("REAL_DB_GROWTH_FINAL_BYTES=\(growth.finalBytes)")
        print("REAL_DB_GROWTH_FINAL_GIB=\(String(format: "%.3f", bytesToGiB(growth.finalBytes)))")
        print("REAL_DB_GROWTH_RECORDS_INSERTED=\(growth.recordsInserted)")
        print("REAL_DB_GROWTH_PAYLOAD_BYTES_PER_RECORD=\(growth.payloadBytesPerRecord)")
        print("REAL_DB_GROWTH_ELAPSED_SECONDS=\(String(format: "%.3f", growth.elapsedSeconds))")
    }

    // MARK: - Measurements

    private func measureMaxBlobBytes() throws -> Int {
        // Search range intentionally exceeds expected ceiling.
        return try binarySearchMax(low: 1, high: 80_000_000) { size in
            try roundTripBlob(size: size)
        }
    }

    private func measureMaxStringBytes() throws -> Int {
        return try binarySearchMax(low: 1, high: 80_000_000) { size in
            try roundTripString(size: size)
        }
    }

    private func measureDatabaseGrowth() throws -> (finalBytes: Int64, recordsInserted: Int, payloadBytesPerRecord: Int, elapsedSeconds: TimeInterval) {
        let targetGiB = Double(ProcessInfo.processInfo.environment["BLAZEDB_REAL_LIMIT_TARGET_GIB"] ?? "0.25") ?? 0.25
        let payloadBytes = Int(ProcessInfo.processInfo.environment["BLAZEDB_REAL_LIMIT_PAYLOAD_BYTES"] ?? "1000000") ?? 1_000_000
        let batchSize = Int(ProcessInfo.processInfo.environment["BLAZEDB_REAL_LIMIT_BATCH_SIZE"] ?? "8") ?? 8
        let targetBytes = Int64(targetGiB * 1024 * 1024 * 1024)

        let (store, url) = try openStore(namePrefix: "RealGrowthStore")
        defer { cleanupStore(store: store, url: url) }

        // Use pseudo-random payload to avoid optimistic compression artifacts.
        let payload = deterministicData(size: payloadBytes, seed: 0x5A)
        var inserted = 0
        let start = Date()
        var pageAllocator = 0

        while true {
            for _ in 0..<batchSize {
                let rootPage = pageAllocator
                pageAllocator += 1
                _ = try store.writePageWithOverflow(index: rootPage, plaintext: payload) {
                    defer { pageAllocator += 1 }
                    return pageAllocator
                }
                inserted += 1
            }

            let bytes = try fileSize(url)
            if bytes >= targetBytes {
                let elapsed = Date().timeIntervalSince(start)
                return (bytes, inserted, payloadBytes, elapsed)
            }
        }
    }

    // MARK: - Helpers

    private func binarySearchMax(low: Int, high: Int, predicate: (Int) throws -> Bool) throws -> Int {
        var lo = low
        var hi = high
        var best = 0

        while lo <= hi {
            let mid = lo + (hi - lo) / 2
            let ok = try predicate(mid)
            if ok {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return best
    }

    private func roundTripBlob(size: Int) throws -> Bool {
        let (store, url) = try openStore(namePrefix: "RealBlobStore")
        defer { cleanupStore(store: store, url: url) }

        do {
            let payload = Data(repeating: 0xAB, count: size)
            let encoded = try BlazeBinaryEncoder.encode(BlazeDataRecord(["blob": .data(payload)]))
            var nextPage = 1
            _ = try store.writePageWithOverflow(index: 0, plaintext: encoded) {
                defer { nextPage += 1 }
                return nextPage
            }
            guard let fetchedData = try store.readPageWithOverflow(index: 0) else { return false }
            let decoded = try BlazeBinaryDecoder.decode(fetchedData)
            return decoded["blob"]?.dataValue?.count == size
        } catch {
            return false
        }
    }

    private func roundTripString(size: Int) throws -> Bool {
        let (store, url) = try openStore(namePrefix: "RealStringStore")
        defer { cleanupStore(store: store, url: url) }

        do {
            let payload = String(repeating: "A", count: size)
            let encoded = try BlazeBinaryEncoder.encode(BlazeDataRecord(["text": .string(payload)]))
            var nextPage = 1
            _ = try store.writePageWithOverflow(index: 0, plaintext: encoded) {
                defer { nextPage += 1 }
                return nextPage
            }
            guard let fetchedData = try store.readPageWithOverflow(index: 0) else { return false }
            let decoded = try BlazeBinaryDecoder.decode(fetchedData)
            return decoded["text"]?.stringValue?.utf8.count == size
        } catch {
            return false
        }
    }

    private func openStore(namePrefix: String) throws -> (PageStore, URL) {
        let id = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(namePrefix)-\(id).blazedb")
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
        let key = SymmetricKey(size: .bits256)
        let store = try PageStore(fileURL: url, key: key, enableWAL: true)
        return (store, url)
    }

    private func cleanupStore(store: PageStore?, url: URL) {
        store?.close()
        Thread.sleep(forTimeInterval: 0.05)

        let exts = ["", "meta", "indexes", "wal", "backup", "transaction_backup"]
        for ext in exts {
            let file = ext.isEmpty ? url : url.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func deterministicData(size: Int, seed: UInt64) -> Data {
        var x = seed
        var result = Data(capacity: size)
        for _ in 0..<size {
            x = x &* 2862933555777941757 &+ 3037000493
            result.append(UInt8((x >> 24) & 0xFF))
        }
        return result
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func bytesToMiB(_ value: Int) -> Double {
        Double(value) / 1024.0 / 1024.0
    }

    private func bytesToGiB(_ value: Int64) -> Double {
        Double(value) / 1024.0 / 1024.0 / 1024.0
    }
}

