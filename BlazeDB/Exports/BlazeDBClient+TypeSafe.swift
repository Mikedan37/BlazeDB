//
//  BlazeDBClient+TypeSafe.swift
//  BlazeDB
//
//  Type-safe database operations for BlazeDocument models.
//  These methods provide compile-time safety while remaining 100% backward compatible.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import Foundation

// MARK: - Type-Safe CRUD Operations

extension BlazeDBClient {
    
    // MARK: - Insert
    
    /// Insert a type-safe document
    ///
    /// Example:
    /// ```swift
    /// let bug = Bug(title: "Fix login", priority: 1, status: "open")
    /// let id = try await db.insert(bug)
    /// ```
    public func insert<T: BlazeDocument>(_ document: T) async throws -> UUID {
        BlazeLogger.debug("Inserting type-safe document of type \(T.self)")
        let storage = try document.toStorage()
        return try await insert(storage)
    }
    
    /// Insert a type-safe document (sync version)
    public func insert<T: BlazeDocument>(_ document: T) throws -> UUID {
        BlazeLogger.debug("Inserting type-safe document of type \(T.self)")
        let storage = try document.toStorage()
        return try insert(storage)
    }
    
    // MARK: - Fetch
    
    /// Fetch a type-safe document by ID
    ///
    /// Example:
    /// ```swift
    /// let bug = try await db.fetch(Bug.self, id: bugID)
    /// print(bug?.title)  // Type-safe access!
    /// ```
    public func fetch<T: BlazeDocument>(_ type: T.Type, id: UUID) async throws -> T? {
        BlazeLogger.debug("Fetching type-safe document of type \(T.self) with id: \(id)")
        guard let storage = try await fetch(id: id) else {
            return nil
        }
        return try T(from: storage)
    }
    
    /// Fetch a type-safe document by ID (sync version)
    public func fetch<T: BlazeDocument>(_ type: T.Type, id: UUID) throws -> T? {
        BlazeLogger.debug("Fetching type-safe document of type \(T.self) with id: \(id)")
        guard let storage = try fetch(id: id) else {
            return nil
        }
        return try T(from: storage)
    }
    
    /// Fetch all documents as a specific type
    ///
    /// Example:
    /// ```swift
    /// let bugs = try await db.fetchAll(Bug.self)
    /// for bug in bugs {
    ///     print(bug.title)  // Type-safe!
    /// }
    /// ```
    public func fetchAll<T: BlazeDocument>(_ type: T.Type) async throws -> [T] {
        BlazeLogger.debug("Fetching all documents of type \(T.self)")
        let records = try await fetchAll()
        return try records.map { try T(from: $0) }
    }
    
    /// Fetch all documents as a specific type (sync version)
    public func fetchAll<T: BlazeDocument>(_ type: T.Type) throws -> [T] {
        BlazeLogger.debug("Fetching all documents of type \(T.self)")
        let records = try fetchAll()
        return try records.map { try T(from: $0) }
    }
    
    // MARK: - Update
    
    /// Update a type-safe document
    ///
    /// The document's ID is used to identify which record to update.
    ///
    /// Example:
    /// ```swift
    /// var bug = try await db.fetch(Bug.self, id: bugID)
    /// bug.priority = 2
    /// bug.status = "closed"
    /// try await db.update(bug)
    /// ```
    public func update<T: BlazeDocument>(_ document: T) async throws {
        BlazeLogger.debug("Updating type-safe document of type \(T.self) with id: \(document.id)")
        let storage = try document.toStorage()
        try await update(id: document.id, data: storage)
    }
    
    /// Update a type-safe document (sync version - runs synchronously)
    public func update<T: BlazeDocument>(_ document: T) throws {
        BlazeLogger.debug("Updating type-safe document of type \(T.self) with id: \(document.id)")
        let storage = try document.toStorage()
        // Use the synchronous update method
        try update(id: document.id, with: storage)
    }
    
    // MARK: - Upsert
    
    /// Upsert (insert or update) a type-safe document
    ///
    /// Example:
    /// ```swift
    /// let bug = Bug(id: specificID, title: "Bug", priority: 1)
    /// let wasInserted = try await db.upsert(bug)
    /// ```
    @discardableResult
    public func upsert<T: BlazeDocument>(_ document: T) async throws -> Bool {
        BlazeLogger.debug("Upserting type-safe document of type \(T.self) with id: \(document.id)")
        let storage = try document.toStorage()
        return try await upsert(id: document.id, data: storage)
    }
    
    /// Upsert a type-safe document (sync version)
    @discardableResult
    public func upsert<T: BlazeDocument>(_ document: T) throws -> Bool {
        BlazeLogger.debug("Upserting type-safe document of type \(T.self) with id: \(document.id)")
        let storage = try document.toStorage()
        return try upsert(id: document.id, data: storage)
    }
    
    // MARK: - BlazeStorable Upsert
    
    /// Upsert a Codable/BlazeStorable object (async)
    @discardableResult
    public func upsert<T: BlazeStorable>(_ object: T) async throws -> Bool {
        BlazeLogger.debug("Upserting BlazeStorable of type \(T.self) with id: \(object.id)")
        let record = try object.toBlazeRecord()
        return try await upsert(id: object.id, data: record)
    }
    
    /// Upsert a Codable/BlazeStorable object (sync)
    @discardableResult
    public func upsert<T: BlazeStorable>(_ object: T) throws -> Bool {
        BlazeLogger.debug("Upserting BlazeStorable of type \(T.self) with id: \(object.id)")
        let record = try object.toBlazeRecord()
        return try upsert(id: object.id, data: record)
    }
    
    // MARK: - Batch Operations
    
    /// Insert many type-safe documents
    ///
    /// Example:
    /// ```swift
    /// let bugs = [
    ///     Bug(title: "Bug 1", priority: 1),
    ///     Bug(title: "Bug 2", priority: 2)
    /// ]
    /// let ids = try await db.insertMany(bugs)
    /// ```
    public func insertMany<T: BlazeDocument>(_ documents: [T]) async throws -> [UUID] {
        BlazeLogger.debug("Inserting \(documents.count) type-safe documents of type \(T.self)")
        let records = try documents.map { try $0.toStorage() }
        return try await insertMany(records)
    }
    
    /// Insert many type-safe documents (sync version)
    public func insertMany<T: BlazeDocument>(_ documents: [T]) throws -> [UUID] {
        BlazeLogger.debug("Inserting \(documents.count) type-safe documents of type \(T.self)")
        let records = try documents.map { try $0.toStorage() }
        return try insertMany(records)
    }
}

// MARK: - QueryResult Type-Safe Extensions

extension QueryResult {
    /// Extract results as a specific type
    ///
    /// Example:
    /// ```swift
    /// let result = try await db.query()
    ///     .where("status", equals: .string("open"))
    ///     .execute()
    /// let bugs = try result.records(as: Bug.self)
    /// ```
    public func records<T: BlazeDocument>(as type: T.Type) throws -> [T] {
        let records = try self.records
        return try records.map { try T(from: $0) }
    }
}

