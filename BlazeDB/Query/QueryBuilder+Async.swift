//
//  QueryBuilder+Async.swift
//  BlazeDB
//
//  Async/await support for QueryBuilder, enabling non-blocking database operations
//  that integrate seamlessly with modern Swift async/await patterns and SwiftUI.
//
//  Created by Michael Danylchuk on 7/1/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

// MARK: - Async Extensions for QueryBuilder

extension QueryBuilder {
    
    // MARK: - Async WHERE Clauses
    
    /// Filter records where field equals value (async)
    @discardableResult
    public func `where`(_ field: String, equals value: BlazeDocumentField) async -> QueryBuilder {
        // Inline sync version logic to avoid recursion with async method
        BlazeLogger.debug("Query: WHERE \(field) = \(value)")
        filters.append { record in
            guard let fieldValue = record.storage[field] else { return false }
            return fieldsEqual(fieldValue, value)
        }
        return self
    }
    
    /// Filter records where field does not equal value (async)
    @discardableResult
    public func `where`(_ field: String, notEquals value: BlazeDocumentField) async -> QueryBuilder {
        // Inline sync version logic to avoid recursion with async method
        BlazeLogger.debug("Query: WHERE \(field) != \(value)")
        filters.append { record in
            guard let fieldValue = record.storage[field] else { return false }
            return !fieldsEqual(fieldValue, value)
        }
        return self
    }
    
    /// Filter records where field is greater than value (async)
    @discardableResult
    public func `where`(_ field: String, greaterThan value: BlazeDocumentField) async -> QueryBuilder {
        // Inline sync version logic to avoid recursion with async method
        BlazeLogger.debug("Query: WHERE \(field) > \(value)")
        filters.append { (record: BlazeDataRecord) -> Bool in
            guard let fieldValue = record.storage[field] else { return false }
            return compareFields(fieldValue, ComparisonOp.greaterThan, value)
        }
        return self
    }
    
    /// Filter records where field is less than value (async)
    @discardableResult
    public func `where`(_ field: String, lessThan value: BlazeDocumentField) async -> QueryBuilder {
        // Inline sync version logic to avoid recursion with async method
        BlazeLogger.debug("Query: WHERE \(field) < \(value)")
        filters.append { (record: BlazeDataRecord) -> Bool in
            guard let fieldValue = record.storage[field] else { return false }
            return compareFields(fieldValue, ComparisonOp.lessThan, value)
        }
        return self
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
        // Inline sync version logic to avoid recursion with async method
        BlazeLogger.debug("Query: JOIN on \(foreignKey) = \(primaryKey) (type: \(type))")
        joinOperations.append(JoinOperation(
            collection: other,
            foreignKey: foreignKey,
            primaryKey: primaryKey,
            type: type
        ))
        return self
    }
    
    // MARK: - Async Sorting
    
    /// Order results by field (async)
    @discardableResult
    public func orderBy(_ field: String, descending: Bool = false) async -> QueryBuilder {
        // Inline sync version logic to avoid recursion with async method
        BlazeLogger.debug("Query: ORDER BY \(field) \(descending ? "DESC" : "ASC")")
        sortOperations.append(SortOperation(
            field: field,
            descending: descending
        ))
        return self
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

#endif // !BLAZEDB_LINUX_CORE

