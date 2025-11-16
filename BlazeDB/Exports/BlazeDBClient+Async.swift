//
//  BlazeDBClient+Async.swift
//  BlazeDB
//
//  Async/await support for BlazeDBClient, providing non-blocking CRUD operations.
//  These methods run database operations on background threads, preventing UI freezing
//  and integrating seamlessly with SwiftUI, UIKit, and server-side Swift.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import Foundation

// MARK: - Async Extensions for BlazeDBClient

extension BlazeDBClient {
    
    // MARK: - Async CRUD Operations
    
    /// Insert a record asynchronously
    ///
    /// Example usage:
    /// ```swift
    /// let bug = BlazeDataRecord([
    ///     "title": .string("Fix login bug"),
    ///     "priority": .int(1)
    /// ])
    /// let id = try await db.insert(bug)
    /// print("Inserted with ID: \(id)")
    /// ```
    public func insert(_ data: BlazeDataRecord) async throws -> UUID {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let id = try self.insert(data)
                    continuation.resume(returning: id)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Fetch a record by ID asynchronously
    public func fetch(id: UUID) async throws -> BlazeDataRecord? {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let record = try self.fetch(id: id)
                    continuation.resume(returning: record)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Fetch all records asynchronously
    public func fetchAll() async throws -> [BlazeDataRecord] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let records = try self.fetchAll()
                    continuation.resume(returning: records)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Update a record asynchronously
    public func update(id: UUID, data: BlazeDataRecord) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.update(id: id, with: data)  // Call the sync version with 'with' label
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Delete a record asynchronously
    public func delete(id: UUID) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.delete(id: id)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Get record count asynchronously
    public func count() async throws -> Int {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let count = try self.count()
                    continuation.resume(returning: count)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Async Batch Operations
    
    /// Insert many records asynchronously
    public func insertMany(_ records: [BlazeDataRecord]) async throws -> [UUID] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let ids = try self.insertMany(records)
                    continuation.resume(returning: ids)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Update many records asynchronously
    public func updateMany(
        where predicate: @escaping (BlazeDataRecord) -> Bool,
        set fields: [String: BlazeDocumentField]
    ) async throws -> Int {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let count = try self.updateMany(where: predicate, set: fields)
                    continuation.resume(returning: count)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Delete many records asynchronously
    public func deleteMany(
        where predicate: @escaping (BlazeDataRecord) -> Bool
    ) async throws -> Int {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let count = try self.deleteMany(where: predicate)
                    continuation.resume(returning: count)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Upsert a record asynchronously
    @discardableResult
    public func upsert(id: UUID, data: BlazeDataRecord) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let wasInserted = try self.upsert(id: id, data: data)
                    continuation.resume(returning: wasInserted)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Get distinct values for a field asynchronously
    public func distinct(field: String) async throws -> [BlazeDocumentField] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let values = try self.distinct(field: field)
                    continuation.resume(returning: values)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Async Index Management
    
    /// Create an index asynchronously
    public func createIndex(on field: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.collection.createIndex(on: field)  // Correct method name
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Create a compound index asynchronously
    public func createCompoundIndex(on fields: [String]) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.collection.createIndex(on: fields)  // Correct method name
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Async Persistence
    
    /// Persist metadata to disk asynchronously
    public func persist() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.persist()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Flush metadata to disk asynchronously (alias for persist)
    public func flush() async throws {
        return try await self.persist()
    }
    
    // MARK: - Async Transaction Support
    
    /// Perform a transaction asynchronously
    ///
    /// Example usage:
    /// ```swift
    /// try await db.performTransaction { txn in
    ///     let id = try txn.insert(record1)
    ///     try txn.update(id: id2, data: record2)
    ///     try txn.delete(id: id3)
    ///     try txn.commit()
    /// }
    /// ```
    public func performTransaction(_ closure: @escaping (BlazeTransaction) throws -> Void) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let transaction = BlazeTransaction(store: self.collection.store)
                    try closure(transaction)
                    try transaction.commit()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

