//
//  BlazeDBClient+Batch.swift
//  BlazeDB
//
//  Complete batch operations API for high-performance bulk data manipulation
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - Batch Operations Extension

extension BlazeDBClient {
    
    // MARK: - Batch Upsert
    
    /// Upsert multiple records (insert or update based on existence)
    ///
    /// For each record with an ID: updates if exists, inserts if not.
    /// For records without IDs: always inserts as new.
    ///
    /// - Parameter records: Array of (id, record) tuples
    /// - Returns: Number of records processed
    /// - Throws: BlazeDBError if operation fails
    ///
    /// ## Example
    /// ```swift
    /// let records: [(UUID, BlazeDataRecord)] = [
    ///     (id1, BlazeDataRecord(["title": .string("Update existing")])),
    ///     (id2, BlazeDataRecord(["title": .string("Insert new")]))
    /// ]
    /// let count = try await db.upsertMany(records)
    /// print("Processed \(count) records")
    /// ```
    public func upsertMany(_ records: [(id: UUID, record: BlazeDataRecord)]) async throws -> Int {
        BlazeLogger.debug("Upserting \(records.count) records...")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var count = 0
                    try self.performSafeWrite {
                        for (id, record) in records {
                            _ = try self.upsert(id: id, data: record)
                            count += 1
                        }
                    }
                    
                    BlazeLogger.info("✅ Upserted \(count) records")
                    continuation.resume(returning: count)
                } catch {
                    BlazeLogger.error("❌ Batch upsert failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Upsert multiple records with automatic ID generation for new records
    ///
    /// - Parameter records: Array of records (with or without IDs)
    /// - Returns: Array of (wasInsert: Bool, id: UUID) for each record
    ///
    /// ## Example
    /// ```swift
    /// let results = try await db.upsertMany([
    ///     BlazeDataRecord(["id": .uuid(existingID), "value": .int(1)]),  // Update
    ///     BlazeDataRecord(["value": .int(2)])                            // Insert (new ID)
    /// ])
    /// ```
    public func upsertMany(_ records: [BlazeDataRecord]) async throws -> [(wasInsert: Bool, id: UUID)] {
        BlazeLogger.debug("Upserting \(records.count) records with auto-ID...")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var results: [(Bool, UUID)] = []
                    
                    try self.performSafeWrite {
                        for record in records {
                            if let existingID = record.storage["id"]?.uuidValue {
                                // Has ID: upsert
                                let wasInsert = try self.upsert(id: existingID, data: record)
                                results.append((wasInsert, existingID))
                            } else {
                                // No ID: insert as new
                                let newID = try self.insert(record)
                                results.append((true, newID))
                            }
                        }
                    }
                    
                    BlazeLogger.info("✅ Upserted \(results.count) records")
                    continuation.resume(returning: results)
                } catch {
                    BlazeLogger.error("❌ Batch upsert failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Batch Fetch
    
    /// Fetch multiple records by IDs (optimized single-pass)
    ///
    /// More efficient than calling fetch() in a loop.
    /// Uses a single database scan to find all requested IDs.
    ///
    /// - Parameter ids: Array of UUIDs to fetch
    /// - Returns: Dictionary mapping ID to record (missing IDs are omitted)
    ///
    /// ## Example
    /// ```swift
    /// let ids = [id1, id2, id3, id4, id5]
    /// let records = try await db.fetchMany(ids: ids)
    ///
    /// if let record1 = records[id1] {
    ///     print("Found: \(record1)")
    /// }
    /// ```
    public func fetchMany(ids: [UUID]) async throws -> [UUID: BlazeDataRecord] {
        BlazeLogger.debug("Fetching \(ids.count) records by ID...")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var results: [UUID: BlazeDataRecord] = [:]
                    let idSet = Set(ids)  // O(1) lookup
                    
                    // Single scan of all records
                    let allRecords = try self.fetchAll()
                    
                    for record in allRecords {
                        if let id = record.storage["id"]?.uuidValue, idSet.contains(id) {
                            results[id] = record
                        }
                    }
                    
                    BlazeLogger.info("✅ Fetched \(results.count)/\(ids.count) requested records")
                    continuation.resume(returning: results)
                } catch {
                    BlazeLogger.error("❌ Batch fetch failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Fetch multiple records by IDs, returning array in same order as requested
    ///
    /// Missing records are returned as nil.
    ///
    /// - Parameter ids: Array of UUIDs to fetch
    /// - Returns: Array of optional records in same order as input
    ///
    /// ## Example
    /// ```swift
    /// let ids = [id1, id2, id3]
    /// let records = try await db.fetchManyOrdered(ids: ids)
    /// // records[0] corresponds to id1, etc.
    /// ```
    public func fetchManyOrdered(ids: [UUID]) async throws -> [BlazeDataRecord?] {
        let recordsMap = try await fetchMany(ids: ids)
        return ids.map { recordsMap[$0] }
    }
    
    // MARK: - Batch Existence Check
    
    /// Check if multiple IDs exist (optimized bulk check)
    ///
    /// More efficient than calling exists() in a loop.
    ///
    /// - Parameter ids: Array of UUIDs to check
    /// - Returns: Dictionary mapping ID to existence
    ///
    /// ## Example
    /// ```swift
    /// let existence = try await db.existsMany(ids: [id1, id2, id3])
    /// if existence[id1] == true {
    ///     print("Record exists!")
    /// }
    /// ```
    public func existsMany(ids: [UUID]) async throws -> [UUID: Bool] {
        BlazeLogger.debug("Checking existence of \(ids.count) IDs...")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var results: [UUID: Bool] = [:]
                    let idSet = Set(ids)
                    
                    // Single scan
                    let allRecords = try self.fetchAll()
                    let existingIDs = Set(allRecords.compactMap { $0.storage["id"]?.uuidValue })
                    
                    for id in ids {
                        results[id] = existingIDs.contains(id)
                    }
                    
                    let existingCount = results.values.filter { $0 }.count
                    BlazeLogger.info("✅ Checked \(ids.count) IDs: \(existingCount) exist")
                    
                    continuation.resume(returning: results)
                } catch {
                    BlazeLogger.error("❌ Batch existence check failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Check if multiple IDs exist, returning just the array of booleans
    ///
    /// - Parameter ids: Array of UUIDs to check
    /// - Returns: Array of booleans in same order as input
    public func existsManyOrdered(ids: [UUID]) async throws -> [Bool] {
        let existenceMap = try await existsMany(ids: ids)
        return ids.map { existenceMap[$0] ?? false }
    }
    
    // MARK: - Batch Delete by IDs
    
    /// Delete multiple records by IDs
    ///
    /// More efficient than calling delete() in a loop.
    ///
    /// - Parameter ids: Array of UUIDs to delete
    /// - Returns: Number of records actually deleted
    ///
    /// ## Example
    /// ```swift
    /// let idsToDelete = [id1, id2, id3]
    /// let deleted = try await db.deleteMany(ids: idsToDelete)
    /// print("Deleted \(deleted) records")
    /// ```
    public func deleteMany(ids: [UUID]) async throws -> Int {
        BlazeLogger.debug("Deleting \(ids.count) records by ID...")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var count = 0
                    try self.performSafeWrite {
                        for id in ids {
                            do {
                                try self.delete(id: id)
                                count += 1
                            } catch BlazeDBError.recordNotFound {
                                // Already deleted, skip
                                BlazeLogger.trace("Record \(id) not found, skipping")
                            }
                        }
                    }
                    
                    BlazeLogger.info("✅ Deleted \(count)/\(ids.count) records")
                    continuation.resume(returning: count)
                } catch {
                    BlazeLogger.error("❌ Batch delete failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Batch Update by IDs
    
    /// Update multiple specific records
    ///
    /// - Parameters:
    ///   - ids: Array of UUIDs to update
    ///   - fields: Fields to update
    /// - Returns: Number of records actually updated
    ///
    /// ## Example
    /// ```swift
    /// let idsToClose = [id1, id2, id3]
    /// let updated = try await db.updateMany(
    ///     ids: idsToClose,
    ///     set: ["status": .string("closed")]
    /// )
    /// ```
    public func updateMany(ids: [UUID], set fields: [String: BlazeDocumentField]) async throws -> Int {
        BlazeLogger.debug("Updating \(ids.count) records by ID...")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var count = 0
                    try self.performSafeWrite {
                        for id in ids {
                            do {
                                try self.update(id: id, with: BlazeDataRecord(fields))
                                count += 1
                            } catch BlazeDBError.recordNotFound {
                                BlazeLogger.trace("Record \(id) not found, skipping")
                            }
                        }
                    }
                    
                    BlazeLogger.info("✅ Updated \(count)/\(ids.count) records")
                    continuation.resume(returning: count)
                } catch {
                    BlazeLogger.error("❌ Batch update failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

