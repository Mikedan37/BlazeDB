import Foundation

// MARK: - Type-Safe KeyPath Query Support

/// KeyPath-based query builder for type-safe queries
public class TypeSafeQueryBuilder<T: BlazeStorable> {
    private let db: BlazeDBClient
    private var filters: [(BlazeDataRecord) -> Bool] = []
    private var sortField: String?
    private var sortDescending: Bool = false
    private var limitValue: Int?
    private var offsetValue: Int?
    
    internal init(db: BlazeDBClient) {
        self.db = db
    }
    
    // MARK: - KeyPath-Based Where Clauses
    
    /// Filter by KeyPath (String fields)
    @discardableResult
    public func `where`<V: Equatable>(_ keyPath: KeyPath<T, V>, equals value: V) -> Self {
        let fieldName = extractFieldName(from: keyPath)
        filters.append { record in
            guard let fieldValue = record.storage[fieldName] else { return false }
            
            // Convert and compare based on type
            if let v = value as? String, let recordValue = fieldValue.stringValue {
                return recordValue == v
            } else if let v = value as? Int, let recordValue = fieldValue.intValue {
                return recordValue == v
            } else if let v = value as? Bool, let recordValue = fieldValue.boolValue {
                return recordValue == v
            } else if let v = value as? Double, let recordValue = fieldValue.doubleValue {
                return recordValue == v
            } else if let v = value as? UUID, let recordValue = fieldValue.uuidValue {
                return recordValue == v
            }
            
            return false
        }
        return self
    }
    
    /// Filter by KeyPath (Comparable fields)
    @discardableResult
    public func `where`<V: Comparable>(_ keyPath: KeyPath<T, V>, greaterThan value: V) -> Self {
        let fieldName = extractFieldName(from: keyPath)
        filters.append { record in
            guard let fieldValue = record.storage[fieldName] else { return false }
            
            if let v = value as? Int, let recordValue = fieldValue.intValue {
                return recordValue > v
            } else if let v = value as? Double, let recordValue = fieldValue.doubleValue {
                return recordValue > v
            } else if let v = value as? Date, let recordValue = fieldValue.dateValue {
                return recordValue > v
            }
            
            return false
        }
        return self
    }
    
    /// Filter by KeyPath (less than)
    @discardableResult
    public func `where`<V: Comparable>(_ keyPath: KeyPath<T, V>, lessThan value: V) -> Self {
        let fieldName = extractFieldName(from: keyPath)
        filters.append { record in
            guard let fieldValue = record.storage[fieldName] else { return false }
            
            if let v = value as? Int, let recordValue = fieldValue.intValue {
                return recordValue < v
            } else if let v = value as? Double, let recordValue = fieldValue.doubleValue {
                return recordValue < v
            } else if let v = value as? Date, let recordValue = fieldValue.dateValue {
                return recordValue < v
            }
            
            return false
        }
        return self
    }
    
    /// Filter by custom predicate on typed object
    @discardableResult
    public func filter(_ predicate: @escaping (T) -> Bool) -> Self {
        filters.append { record in
            guard let object = try? T.fromBlazeRecord(record) else { return false }
            return predicate(object)
        }
        return self
    }
    
    // MARK: - Sorting
    
    /// Sort by KeyPath
    @discardableResult
    public func orderBy<V>(_ keyPath: KeyPath<T, V>, descending: Bool = false) -> Self {
        sortField = extractFieldName(from: keyPath)
        sortDescending = descending
        return self
    }
    
    // MARK: - Limit/Offset
    
    @discardableResult
    public func limit(_ count: Int) -> Self {
        limitValue = count
        return self
    }
    
    @discardableResult
    public func offset(_ count: Int) -> Self {
        offsetValue = count
        return self
    }
    
    // MARK: - Execute
    
    /// Execute and return typed results
    public func all() throws -> [T] {
        var query = db.query()
        
        // Apply filters
        for filter in filters {
            query = query.where(filter)
        }
        
        // Apply sort
        if let field = sortField {
            query = query.orderBy(field, descending: sortDescending)
        }
        
        // Apply limit/offset
        if let limit = limitValue {
            query = query.limit(limit)
        }
        if let offset = offsetValue {
            query = query.offset(offset)
        }
        
        let records = try query.all()
        return try records.map { try T.fromBlazeRecord($0) }
    }
    
    /// Execute async
    public func all() async throws -> [T] {
        var query = db.query()
        
        for filter in filters {
            query = query.where(filter)
        }
        
        if let field = sortField {
            query = await query.orderBy(field, descending: sortDescending)
        }
        
        if let limit = limitValue {
            query = query.limit(limit)
        }
        if let offset = offsetValue {
            query = query.offset(offset)
        }
        
        let records = try await query.all()
        return try records.map { try T.fromBlazeRecord($0) }
    }
    
    /// Get first result
    public func first() throws -> T? {
        guard let record = try self.limit(1).all().first else {
            return nil
        }
        return record
    }
    
    /// Get first async
    public func first() async throws -> T? {
        guard let record = try await self.limit(1).all().first else {
            return nil
        }
        return record
    }
    
    /// Check if results exist
    public func exists() throws -> Bool {
        try self.limit(1).all().isEmpty == false
    }
    
    /// Check exists async
    public func exists() async throws -> Bool {
        try await self.limit(1).all().isEmpty == false
    }
    
    /// Quick count
    public func count() throws -> Int {
        try self.all().count
    }
    
    /// Count async
    public func count() async throws -> Int {
        try await self.all().count
    }
    
    // MARK: - KeyPath Field Name Extraction
    
    private func extractFieldName<V>(from keyPath: KeyPath<T, V>) -> String {
        // Use Mirror to extract property name from KeyPath
        let mirror = Mirror(reflecting: keyPath)
        
        // Try to get the field name from the KeyPath
        // This is a best-effort approach
        let pathString = "\(keyPath)"
        
        // KeyPath format is usually like: \TypeName.fieldName
        if let dotIndex = pathString.lastIndex(of: ".") {
            let fieldName = String(pathString[pathString.index(after: dotIndex)...])
            return fieldName
        }
        
        // Fallback: use the keyPath description
        return pathString
    }
}

// MARK: - BlazeDBClient KeyPath Query Extension

extension BlazeDBClient {
    
    /// Start a type-safe query with KeyPaths
    ///
    /// Example:
    /// ```swift
    /// let bugs = try db.query(Bug.self)
    ///     .where(\.status, equals: "open")
    ///     .where(\.priority, greaterThan: 5)
    ///     .orderBy(\.createdAt, descending: true)
    ///     .all()
    /// ```
    public func query<T: BlazeStorable>(_ type: T.Type) -> TypeSafeQueryBuilder<T> {
        TypeSafeQueryBuilder<T>(db: self)
    }
}

