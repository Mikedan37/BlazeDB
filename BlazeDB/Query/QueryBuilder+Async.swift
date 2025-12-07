//
//  QueryBuilder+Async.swift
//  BlazeDB
//
//  Async/await support for QueryBuilder, enabling non-blocking database operations
//  that integrate seamlessly with modern Swift async/await patterns and SwiftUI.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import Foundation

// MARK: - Async Extensions for QueryBuilder

extension QueryBuilder {
    
    // MARK: - Async WHERE Clauses
    
    /// Filter records where field equals value (async)
    @discardableResult
    public func `where`(_ field: String, equals value: BlazeDocumentField) async -> QueryBuilder {
        return await Task { self.where(field, equals: value) }.value
    }
    
    /// Filter records where field does not equal value (async)
    @discardableResult
    public func `where`(_ field: String, notEquals value: BlazeDocumentField) async -> QueryBuilder {
        return await Task { self.where(field, notEquals: value) }.value
    }
    
    /// Filter records where field is greater than value (async)
    @discardableResult
    public func `where`(_ field: String, greaterThan value: BlazeDocumentField) async -> QueryBuilder {
        return await Task { self.where(field, greaterThan: value) }.value
    }
    
    /// Filter records where field is less than value (async)
    @discardableResult
    public func `where`(_ field: String, lessThan value: BlazeDocumentField) async -> QueryBuilder {
        return await Task { self.where(field, lessThan: value) }.value
    }
    
    // MARK: - Async JOIN
    
    /// Join with another collection (async)
    @discardableResult
    public func join(
        _ other: DynamicCollection,
        on foreignKey: String,
        equals primaryKey: String = "id",
        type: JoinType = .inner
    ) async -> QueryBuilder {
        return await Task { self.join(other, on: foreignKey, equals: primaryKey, type: type) }.value
    }
    
    // MARK: - Async Sorting
    
    /// Order results by field (async)
    @discardableResult
    public func orderBy(_ field: String, descending: Bool = false) async -> QueryBuilder {
        return await Task { self.orderBy(field, descending: descending) }.value
    }
    
    // MARK: - Async Execution
    
    /// Execute the query asynchronously and return a unified QueryResult
    ///
    /// This method runs the query on a background thread, preventing main thread blocking.
    /// Perfect for SwiftUI, UIKit, and server-side Swift applications.
    ///
    /// Example usage:
    /// ```swift
    /// // In a SwiftUI view or async context:
    /// let result = try await db.query()
    ///     .where("status", equals: .string("open"))
    ///     .execute()
    /// let records = try result.records
    ///
    /// // With JOIN (auto-detected):
    /// let result = try await db.query()
    ///     .join(usersDB.collection, on: "authorId")
    ///     .execute()
    /// let joined = try result.joined
    /// ```
    public func execute() async throws -> QueryResult {
        return try await withCheckedThrowingContinuation { continuation in
            // Execute on background queue
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.execute()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Execute with caching support (async)
    public func execute(withCache ttl: TimeInterval) async throws -> QueryResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.execute(withCache: ttl)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Async Legacy Methods (Deprecated)
    
    /// Execute standard query asynchronously (deprecated)
    @available(*, deprecated, message: "Use execute() async which returns QueryResult")
    public func executeStandard() async throws -> [BlazeDataRecord] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.executeStandard()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Execute JOIN query asynchronously (deprecated)
    @available(*, deprecated, message: "Use execute() async which returns QueryResult")
    public func executeJoin() async throws -> [JoinedRecord] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.executeJoin()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Execute aggregation query asynchronously (deprecated)
    @available(*, deprecated, message: "Use execute() async which returns QueryResult")
    public func executeAggregation() async throws -> AggregationResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.executeAggregation()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Execute grouped aggregation query asynchronously (deprecated)
    @available(*, deprecated, message: "Use execute() async which returns QueryResult")
    public func executeGroupedAggregation() async throws -> GroupedAggregationResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.executeGroupedAggregation()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

