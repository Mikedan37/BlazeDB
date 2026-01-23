import Foundation

// MARK: - Transaction DX Improvements

extension BlazeDBClient {
    
    /// Execute a transaction with cleaner syntax
    ///
    /// Example:
    /// ```swift
    /// try db.transaction {
    ///     let id = try db.insert { "title" => "Bug" }
    ///     try db.updateFields(id: id, fields: ["status": .string("done")])
    /// }
    /// ```
    public func transaction(_ block: () throws -> Void) throws {
        try self.beginTransaction()
        
        do {
            try block()
            try self.commitTransaction()
        } catch {
            try? self.rollbackTransaction()
            throw error
        }
    }
    
    /// Execute async transaction
    public func transaction(_ block: () async throws -> Void) async throws {
        try await self.beginTransaction()
        
        do {
            try await block()
            try await self.commitTransaction()
        } catch {
            try? await self.rollbackTransaction()
            throw error
        }
    }
}

// MARK: - Validation Helpers

extension BlazeDataRecord {
    
    /// Validate that required fields exist
    public func require(_ fields: String...) throws {
        for field in fields {
            guard self.storage[field] != nil else {
                throw BlazeDBError.validationFailed("Missing required field: \(field)")
            }
        }
    }
    
    /// Validate field is of expected type
    public func validate(_ field: String, isType type: BlazeFieldType) throws {
        guard let value = self.storage[field] else {
            throw BlazeDBError.validationFailed("Field '\(field)' does not exist")
        }
        
        let matches = switch type {
        case .string: value.stringValue != nil
        case .int: value.intValue != nil
        case .double: value.doubleValue != nil
        case .bool: value.boolValue != nil
        case .date: value.dateValue != nil
        case .uuid: value.uuidValue != nil
        case .array: value.arrayValue != nil
        case .data: value.dataValue != nil
        }
        
        if !matches {
            throw BlazeDBError.validationFailed("Field '\(field)' is not of type \(type)")
        }
    }
    
    /// Validate field value matches predicate
    public func validate(_ field: String, where predicate: (BlazeDocumentField) -> Bool) throws {
        guard let value = self.storage[field] else {
            throw BlazeDBError.validationFailed("Field '\(field)' does not exist")
        }
        
        if !predicate(value) {
            throw BlazeDBError.validationFailed("Field '\(field)' failed validation")
        }
    }
}

public enum BlazeFieldType {
    case string, int, double, bool, date, uuid, array, data
}

// MARK: - BlazeDBError Extension

extension BlazeDBError {
    public static func validationFailed(_ message: String) -> BlazeDBError {
        .transactionFailed(message)
    }
}

// MARK: - Batch Operations Syntax Sugar

extension BlazeDBClient {
    
    /// Bulk insert with DSL
    ///
    /// Example:
    /// ```swift
    /// try db.bulkInsert {
    ///     BlazeDataRecord { "title" => "Bug 1" }
    ///     BlazeDataRecord { "title" => "Bug 2" }
    ///     BlazeDataRecord { "title" => "Bug 3" }
    /// }
    /// ```
    @discardableResult
    public func bulkInsert(@RecordArrayBuilder _ builder: () -> [BlazeDataRecord]) throws -> [UUID] {
        let records = builder()
        return try self.insertMany(records)
    }
    
    /// Bulk insert async
    @discardableResult
    public func bulkInsert(@RecordArrayBuilder _ builder: () -> [BlazeDataRecord]) async throws -> [UUID] {
        let records = builder()
        return try await self.insertMany(records)
    }
}

@resultBuilder
public struct RecordArrayBuilder {
    public static func buildBlock(_ components: BlazeDataRecord...) -> [BlazeDataRecord] {
        components
    }
    
    public static func buildArray(_ components: [[BlazeDataRecord]]) -> [BlazeDataRecord] {
        components.flatMap { $0 }
    }
}

// MARK: - Query Shortcuts for Common Patterns

extension QueryBuilder {
    
    /// Find by ID shortcut
    public func byID(_ id: UUID) -> QueryBuilder {
        self.where("id", equals: .uuid(id))
    }
    
    /// Find recent (last N days)
    public func recent(days: Int, field: String = "createdAt") -> QueryBuilder {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return self.where(field, greaterThan: .date(cutoff))
    }
    
    /// Find by date range
    public func between(_ field: String, from: Date, to: Date) -> QueryBuilder {
        self.where(field, greaterThanOrEqual: .date(from))
            .where(field, lessThanOrEqual: .date(to))
    }
    
    /// Pagination helper
    public func page(_ number: Int, size: Int = 20) -> QueryBuilder {
        self.offset(number * size).limit(size)
    }
}

// MARK: - Async Sequence for Large Queries

extension BlazeDBClient {
    
    /// Stream large result sets without loading all into memory
    ///
    /// Example:
    /// ```swift
    /// for try await batch in db.stream(batchSize: 100) {
    ///     process(batch)
    /// }
    /// ```
    public func stream(
        batchSize: Int = 100,
        where predicate: (@Sendable (BlazeDataRecord) -> Bool)? = nil
    ) -> AsyncThrowingStream<[BlazeDataRecord], Error> {
        AsyncThrowingStream { continuation in
            // Capture predicate before Task - predicate is now @Sendable
            let capturedPredicate = predicate
            // BlazeDBClient is @unchecked Sendable, so we can capture self
            // Use Task.detached with @Sendable closure
            Task.detached(priority: .userInitiated) { @Sendable [weak self] in
                guard let self = self else {
                    continuation.finish(throwing: BlazeDBError.transactionFailed("Client deallocated"))
                    return
                }
                do {
                    var offset = 0
                    while true {
                        let batch = try self.fetchPage(offset: offset, limit: batchSize)
                        
                        let filtered = if let predicate = capturedPredicate {
                            batch.filter(predicate)
                        } else {
                            batch
                        }
                        
                        if filtered.isEmpty {
                            continuation.finish()
                            break
                        }
                        
                        continuation.yield(filtered)
                        offset += batchSize
                        
                        if batch.count < batchSize {
                            continuation.finish()
                            break
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Pretty Printing

extension BlazeDataRecord {
    
    /// Pretty print for debugging
    public var prettyPrint: String {
        var lines: [String] = ["BlazeDataRecord {"]
        
        for (key, value) in storage.sorted(by: { $0.key < $1.key }) {
            let valueString = switch value {
            case .string(let s): "\"\(s)\""
            case .int(let i): "\(i)"
            case .double(let d): "\(d)"
            case .bool(let b): "\(b)"
            case .date(let d): "\(d)"
            case .uuid(let u): "\(u)"
            case .array(let a): "[\(a.count) items]"
            case .data(let d): "<\(d.count) bytes>"
            case .dictionary(let dict): "{\(dict.count) fields}"
            case .vector(let v): "[\(v.count) floats]"
            case .null: "null"
            }
            lines.append("  \(key): \(valueString)")
        }
        
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Error Messages

extension BlazeDBError {
    
    /// User-friendly error message
    public var friendlyMessage: String {
        switch self {
        case .recordNotFound:
            return "The record you're looking for doesn't exist. It may have been deleted."
        case .recordExists:
            return "A record with this ID already exists."
        case .transactionFailed(let msg, _):
            return "Operation failed: \(msg)"
        case .migrationFailed(let msg, _):
            return "Database migration failed: \(msg)"
        case .invalidQuery(let reason, _):
            return "Invalid query: \(reason)"
        case .indexNotFound(let field, _):
            return "Index not found for field '\(field)'"
        case .invalidField(let name, let expected, let actual):
            return "Field '\(name)' type mismatch: expected \(expected), got \(actual)"
        case .diskFull:
            return "Not enough disk space available"
        case .permissionDenied(let operation, _):
            return "Permission denied for operation: \(operation)"
        case .databaseLocked(let operation, _, _):
            return "Database is locked for operation: \(operation)"
        case .corruptedData(let location, let reason):
            return "Data corrupted at \(location): \(reason)"
        case .passwordTooWeak(let requirements):
            return "Password too weak. Requirements: \(requirements)"
        case .invalidData(let reason):
            return "Invalid data: \(reason)"
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        }
    }
}

