//
//  BlazeDBClient+AsyncOptimized.swift
//  BlazeDB
//
//  Optimized async operations using true async/await instead of DispatchQueue wrappers
//  Provides query caching, operation pooling, and connection limits
//
//  Created by Michael Danylchuk on 1/15/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

// MARK: - BlazeDBClient Async Optimized Extension

extension BlazeDBClient {
    
    // MARK: - Async CRUD Operations (Optimized)
    
    /// Insert a record asynchronously (true async, non-blocking)
    ///
    /// Uses operation pooling and true async/await for maximum efficiency.
    ///
    /// Example:
    /// ```swift
    /// let record = BlazeDataRecord(["title": .string("Hello")])
    /// let id = try await db.insertAsync(record)
    /// ```
    public func insertAsync(_ data: BlazeDataRecord) async throws -> UUID {
        let startTime = Date()
        
        do {
            var record = data
            let id: UUID
            if case let .uuid(existingID)? = record.storage["id"] {
                id = existingID
            } else if case let .string(idStr)? = record.storage["id"], let parsed = UUID(uuidString: idStr) {
                id = parsed
                record.storage["id"] = .uuid(parsed)
            } else {
                id = UUID()
                record.storage["id"] = .uuid(id)
            }
            
            if record.storage["createdAt"] == nil {
                record.storage["createdAt"] = .date(Date())
            }
            
            // Validate against schema
            try validateAgainstSchema(record)
            
            // Use true async insert
            let insertedId = try await collection.insertAsync(record)
            
            // Log to transaction log (synchronously - thread-safe method)
            appendToTransactionLog("insert", payload: record.storage)
            
            // Track telemetry
            #if BLAZEDB_DISTRIBUTED
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "insertAsync", duration: duration, success: true, recordCount: 1)
            #endif
            
            return insertedId
        } catch {
            #if BLAZEDB_DISTRIBUTED
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "insertAsync", duration: duration, success: false, recordCount: 0, error: error)
            #endif
            throw error
        }
    }
    
    /// Insert multiple records asynchronously (true async, parallel)
    public func insertManyAsync(_ records: [BlazeDataRecord]) async throws -> [UUID] {
        let startTime = Date()
        
        do {
            // Use true async batch insert
            let ids = try await collection.insertBatchAsync(records)
            
            // Log to transaction log (synchronously - thread-safe method)
            for (index, id) in ids.enumerated() {
                if index < records.count {
                    appendToTransactionLog("insert", payload: records[index].storage)
                }
            }
            
            BlazeLogger.info("Inserted \(ids.count) records asynchronously")
            
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "insertManyAsync", duration: duration, success: true, recordCount: ids.count)
            
            return ids
        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "insertManyAsync", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Fetch a record by ID asynchronously (true async, non-blocking)
    public func fetchAsync(id: UUID) async throws -> BlazeDataRecord? {
        let startTime = Date()
        
        do {
            let record = try await collection.fetchAsync(id: id)
            
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetchAsync", duration: duration, success: true, recordCount: record == nil ? 0 : 1)
            
            return record
        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetchAsync", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Fetch all records asynchronously (true async, non-blocking)
    public func fetchAllAsync() async throws -> [BlazeDataRecord] {
        let startTime = Date()
        
        do {
            let records = try await collection.fetchAllAsync()
            
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetchAllAsync", duration: duration, success: true, recordCount: records.count)
            
            return records
        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetchAllAsync", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Fetch a page of records asynchronously (true async, non-blocking)
    public func fetchPageAsync(offset: Int, limit: Int) async throws -> [BlazeDataRecord] {
        let startTime = Date()
        
        do {
            let records = try await collection.fetchPageAsync(offset: offset, limit: limit)
            
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetchPageAsync", duration: duration, success: true, recordCount: records.count)
            
            return records
        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetchPageAsync", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Update a record asynchronously (true async, non-blocking)
    public func updateAsync(id: UUID, with data: BlazeDataRecord) async throws {
        let startTime = Date()
        
        do {
            // Validate against schema
            try validateAgainstSchema(data)
            
            // Use true async update
            try await collection.updateAsync(id: id, with: data)
            
            // Log to transaction log (synchronously - thread-safe method)
            appendToTransactionLog("update", payload: data.storage)
            
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "updateAsync", duration: duration, success: true, recordCount: 1)
        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "updateAsync", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Delete a record asynchronously (true async, non-blocking)
    public func deleteAsync(id: UUID) async throws {
        let startTime = Date()
        
        do {
            // Use true async delete
            try await collection.deleteAsync(id: id)
            
            // Log to transaction log (synchronously - thread-safe method)
            appendToTransactionLog("delete", payload: ["id": .string(id.uuidString)])
            
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "deleteAsync", duration: duration, success: true, recordCount: 1)
        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "deleteAsync", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    // MARK: - Async Query with Caching
    
    /// Execute a query asynchronously with caching
    ///
    /// Example:
    /// ```swift
    /// let results = try await db.queryAsync(
    ///     where: "status",
    ///     equals: .string("open"),
    ///     orderBy: "priority",
    ///     descending: true,
    ///     limit: 10,
    ///     useCache: true
    /// )
    /// ```
    public func queryAsync(
        where field: String? = nil,
        equals value: BlazeDocumentField? = nil,
        orderBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil,
        useCache: Bool = true
    ) async throws -> [BlazeDataRecord] {
        let startTime = Date()
        
        do {
            let results = try await collection.queryAsync(
                where: field,
                equals: value,
                orderBy: orderBy,
                descending: descending,
                limit: limit,
                useCache: useCache
            )
            
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "queryAsync", duration: duration, success: true, recordCount: results.count)
            
            return results
        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "queryAsync", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    // MARK: - Cache Management
    
    /// Invalidate query cache
    public func invalidateQueryCache() async {
        await collection.invalidateQueryCache()
    }
    
    /// Get current operation pool load
    public func getOperationPoolLoad() async -> Int {
        await collection.getOperationPoolLoad()
    }
}
#endif // !BLAZEDB_LINUX_CORE
