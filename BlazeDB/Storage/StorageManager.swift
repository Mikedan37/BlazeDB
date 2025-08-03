//  StorageManager.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/21/25.
import Foundation

public final class StorageManager {
    private let collection: DynamicCollection
    private let fileURL: URL

    public init(collection: DynamicCollection, fileURL: URL) {
        self.collection = collection
        self.fileURL = fileURL
    }

    /// Perform garbage cleanup by deleting any orphaned records not present in the active store.
    public func performCleanup() throws {
        let allIDs = try collection.fetchAllIDs()
        let allRecords = try collection.fetchAll()
        let usedIDs = Set(
            allRecords.compactMap {
                if case let .string(id) = $0.storage["id"] {
                    return UUID(uuidString: id)
                }
                return nil
            }
        )
        let garbage = allIDs.filter { !usedIDs.contains($0) }

        for id in garbage {
            try? collection.delete(id: id)
            print("🧹 Deleted orphaned record: \(id)")
        }

        print("🧼 Cleanup complete. Removed \(garbage.count) unused records.")
    }

    /// Returns disk usage of the database file in bytes.
    public func databaseDiskUsage() -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64) ?? 0
    }

    /// Logs current layout metadata.
    public func logLayoutStatus() {
        do {
            let count = try collection.fetchAll().count
            print("📊 Record count: \(count)")
            print("📁 Disk size: \(databaseDiskUsage()) bytes")
        } catch {
            print("⚠️ Failed to fetch layout: \(error)")
        }
    }

    /// Returns dashboard metrics for the current store layout.
    public func generateDashboardStats() -> StorageDashboardStats {
        let pageSize = 4096
        return StorageDashboardStats(
            totalPages: collection.pageCount,
            orphanedPages: collection.orphanedPageCount,
            estimatedDBSizeKB: (collection.pageCount * pageSize) / 1024,
            recordCount: collection.recordCount,
            maxRecordSizeBytes: collection.largestRecordSize,
            lastCleanup: nil, // Update when cleanup date tracking is added
            pageWarnings: collection.pageWarningCount
        )
    }

    /// Warn if any record is close to exceeding page size.
    public func checkForLargeRecords(threshold: Int = 3900) {
        do {
            let records = try collection.fetchAll()
            for record in records {
                let encoded = try BlazeEncoder().encode(record)
                if encoded.count > threshold {
                    if case let .string(idStr) = record.storage["id"], let id = UUID(uuidString: idStr) {
                        print("⚠️ Large record (\(encoded.count) bytes): \(id)")
                    } else {
                        print("⚠️ Large record (\(encoded.count) bytes): Unknown ID")
                    }
                }
            }
        } catch {
            print("🚨 Failed to check record sizes: \(error)")
        }
    }
}

public struct BlazeEncoder {
    private let encoder = JSONEncoder()

    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }
}
