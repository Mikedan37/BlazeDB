//  QueryBuilder.swift
//  BlazeDB
//  Created by Michael Danylchuk

import Foundation

// MARK: - Filter Descriptor for Cache Key Generation and Index Execution

/// Describes a filter operation for cache key generation and index-based execution
internal struct FilterDescriptor: Hashable {
    let field: String
    let operation: String
    let valueHash: Int
    let value: BlazeDocumentField?  // Stored for index execution
    let values: [BlazeDocumentField]?  // For IN queries
    
    init(field: String, operation: String, value: BlazeDocumentField) {
        self.field = field
        self.operation = operation
        self.valueHash = Self.hashValue(value)
        self.value = value
        self.values = nil
    }
    
    init(field: String, operation: String, values: [BlazeDocumentField]) {
        self.field = field
        self.operation = operation
        var hasher = Hasher()
        for value in values {
            hasher.combine(Self.hashValue(value))
        }
        self.valueHash = hasher.finalize()
        self.value = nil
        self.values = values
    }
    
    init(customDescription: String) {
        self.field = "_custom"
        self.operation = "closure"
        var hasher = Hasher()
        hasher.combine(customDescription)
        self.valueHash = hasher.finalize()
        self.value = nil
        self.values = nil
    }
    
    private static func hashValue(_ field: BlazeDocumentField) -> Int {
        var hasher = Hasher()
        switch field {
        case .string(let s): hasher.combine("s"); hasher.combine(s)
        case .int(let i): hasher.combine("i"); hasher.combine(i)
        case .double(let d): hasher.combine("d"); hasher.combine(d.bitPattern)
        case .bool(let b): hasher.combine("b"); hasher.combine(b)
        case .uuid(let u): hasher.combine("u"); hasher.combine(u)
        case .date(let d): hasher.combine("t"); hasher.combine(d.timeIntervalSince1970)
        case .data(let d): hasher.combine("D"); hasher.combine(d)
        case .array(let a):
            hasher.combine("a")
            for item in a { hasher.combine(hashValue(item)) }
        case .dictionary(let d):
            hasher.combine("m")
            for (k, v) in d.sorted(by: { $0.key < $1.key }) {
                hasher.combine(k)
                hasher.combine(hashValue(v))
            }
        case .null: hasher.combine("n")
        case .vector(let v): hasher.combine("v"); hasher.combine(v)
        }
        return hasher.finalize()
    }
    
    /// Convert BlazeDocumentField to AnyHashable for index lookup
    var hashableValue: AnyHashable? {
        guard let value = value else { return nil }
        switch value {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .uuid(let u): return u
        case .date(let d): return d
        case .data(let d): return d
        case .null: return nil
        case .array, .dictionary, .vector: return nil  // Complex types not indexable
        }
    }
    
    var cacheKeyComponent: String {
        return "\(field):\(operation):\(valueHash)"
    }
    
    // Hashable conformance - exclude stored value for equality to avoid issues with complex types
    static func == (lhs: FilterDescriptor, rhs: FilterDescriptor) -> Bool {
        return lhs.field == rhs.field &&
               lhs.operation == rhs.operation &&
               lhs.valueHash == rhs.valueHash
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(field)
        hasher.combine(operation)
        hasher.combine(valueHash)
    }
}

// MARK: - Query Builder

/// Fluent query builder for BlazeDB with chainable methods
/// Note: @unchecked Sendable for async method compatibility - builder is designed for sequential access
public final class QueryBuilder: @unchecked Sendable {
    internal weak var collection: DynamicCollection?
    internal var filters: [(BlazeDataRecord) -> Bool] = []  // Internal for subquery access
    internal var filterDescriptors: [FilterDescriptor] = []  // For cache key generation
    internal var filterFields: Set<String> = []  // Tracked filter fields for optimizer
    internal var joinOperations: [JoinOperation] = []
    internal var sortOperations: [SortOperation] = []
    internal var limitValue: Int?
    internal var offsetValue: Int = 0
    internal var groupByFields: [String] = []
    internal var aggregations: [AggregationType] = []
    internal var havingPredicate: ((AggregationResult) -> Bool)?
    
    #if !BLAZEDB_LINUX_CORE
    // Advanced query features (spatial, vector, window functions)
    internal var sortByDistanceCenter: SpatialPoint?
    internal var windowFunctions: [(function: WindowFunction, alias: String)] = []
    #endif
    
    internal init(collection: DynamicCollection) {
        self.collection = collection
    }
    
    // MARK: - WHERE Clauses
    
    /// Filter records where field equals value
    @discardableResult
    public func `where`(_ field: String, equals value: BlazeDocumentField) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) = \(value)")
        filterFields.insert(field)
        filterDescriptors.append(FilterDescriptor(field: field, operation: "eq", value: value))
        filters.append { record in
            guard let fieldValue = record.storage[field] else { return false }
            return fieldsEqual(fieldValue, value)
        }
        return self
    }
    
    /// Filter records where field does not equal value
    @discardableResult
    public func `where`(_ field: String, notEquals value: BlazeDocumentField) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) != \(value)")
        filterFields.insert(field)
        filterDescriptors.append(FilterDescriptor(field: field, operation: "ne", value: value))
        filters.append { record in
            guard let fieldValue = record.storage[field] else { return false }
            return !fieldsEqual(fieldValue, value)
        }
        return self
    }
    
    /// Filter records where field is greater than value
    @discardableResult
    public func `where`(_ field: String, greaterThan value: BlazeDocumentField) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) > \(value)")
        filterFields.insert(field)
        filterDescriptors.append(FilterDescriptor(field: field, operation: "gt", value: value))
        filters.append { (record: BlazeDataRecord) -> Bool in
            guard let fieldValue = record.storage[field] else { return false }
            return compareFields(fieldValue, .greaterThan, value)
        }
        return self
    }
    
    /// Filter records where field is less than value
    @discardableResult
    public func `where`(_ field: String, lessThan value: BlazeDocumentField) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) < \(value)")
        filterFields.insert(field)
        filterDescriptors.append(FilterDescriptor(field: field, operation: "lt", value: value))
        filters.append { (record: BlazeDataRecord) -> Bool in
            guard let fieldValue = record.storage[field] else { return false }
            return compareFields(fieldValue, .lessThan, value)
        }
        return self
    }
    
    /// Filter records where field is greater than or equal to value
    @discardableResult
    public func `where`(_ field: String, greaterThanOrEqual value: BlazeDocumentField) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) >= \(value)")
        filterFields.insert(field)
        filterDescriptors.append(FilterDescriptor(field: field, operation: "gte", value: value))
        filters.append { (record: BlazeDataRecord) -> Bool in
            guard let fieldValue = record.storage[field] else { return false }
            return compareFields(fieldValue, .greaterThan, value) || fieldsEqual(fieldValue, value)
        }
        return self
    }
    
    /// Filter records where field is less than or equal to value
    @discardableResult
    public func `where`(_ field: String, lessThanOrEqual value: BlazeDocumentField) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) <= \(value)")
        filterFields.insert(field)
        filterDescriptors.append(FilterDescriptor(field: field, operation: "lte", value: value))
        filters.append { (record: BlazeDataRecord) -> Bool in
            guard let fieldValue = record.storage[field] else { return false }
            return compareFields(fieldValue, .lessThan, value) || fieldsEqual(fieldValue, value)
        }
        return self
    }
    
    /// Filter records where field contains value (for strings)
    @discardableResult
    public func `where`(_ field: String, contains substring: String) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) CONTAINS '\(substring)'")
        filterFields.insert(field)
        filterDescriptors.append(FilterDescriptor(field: field, operation: "contains", value: .string(substring)))
        filters.append { record in
            guard let stringValue = record.storage[field]?.stringValue else { return false }
            return stringValue.contains(substring)
        }
        return self
    }
    
    /// Filter records where field is in array of values
    @discardableResult
    public func `where`(_ field: String, in values: [BlazeDocumentField]) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) IN [\(values.count) values]")
        filterFields.insert(field)
        filterDescriptors.append(FilterDescriptor(field: field, operation: "in", values: values))
        filters.append { record in
            guard let fieldValue = record.storage[field] else { return false }
            return values.contains { fieldsEqual(fieldValue, $0) }
        }
        return self
    }
    
    /// Filter records where field is nil or missing
    @discardableResult
    public func whereNil(_ field: String) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) IS NULL")
        filterFields.insert(field)
        filterDescriptors.append(FilterDescriptor(field: field, operation: "isnil", value: .null))
        filters.append { record in
            record.storage[field] == nil
        }
        return self
    }
    
    /// Filter records where field is not nil
    @discardableResult
    public func whereNotNil(_ field: String) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) IS NOT NULL")
        filterFields.insert(field)
        filterDescriptors.append(FilterDescriptor(field: field, operation: "notnil", value: .null))
        filters.append { record in
            record.storage[field] != nil
        }
        return self
    }
    
    /// Custom filter with closure (maximum flexibility)
    @discardableResult
    public func `where`(_ predicate: @escaping (BlazeDataRecord) -> Bool) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE <custom closure>")
        filterDescriptors.append(FilterDescriptor(customDescription: "closure_\(filters.count)"))
        filters.append(predicate)
        return self
    }
    
    // MARK: - JOIN Operations
    
    /// Join with another collection
    @discardableResult
    public func join(
        _ other: DynamicCollection,
        on foreignKey: String,
        equals primaryKey: String = "id",
        type: JoinType = .inner
    ) -> QueryBuilder {
        BlazeLogger.debug("Query: JOIN on \(foreignKey) = \(primaryKey) (type: \(type))")
        joinOperations.append(JoinOperation(
            collection: other,
            foreignKey: foreignKey,
            primaryKey: primaryKey,
            type: type
        ))
        return self
    }
    
    // MARK: - ORDER BY
    
    /// Sort results by field
    @discardableResult
    public func orderBy(_ field: String, descending: Bool = false) -> QueryBuilder {
        BlazeLogger.debug("Query: ORDER BY \(field) \(descending ? "DESC" : "ASC")")
        sortOperations.append(SortOperation(
            field: field,
            descending: descending
        ))
        return self
    }
    
    /// Sort by multiple fields (convenience)
    @discardableResult
    public func orderBy(_ fields: [(String, Bool)]) -> QueryBuilder {
        for (field, descending) in fields {
            sortOperations.append(SortOperation(
                field: field,
                descending: descending
            ))
        }
        return self
    }
    
    // MARK: - LIMIT & OFFSET
    
    /// Limit number of results
    @discardableResult
    public func limit(_ count: Int) -> QueryBuilder {
        BlazeLogger.debug("Query: LIMIT \(count)")
        self.limitValue = count
        return self
    }
    
    /// Skip first N results
    @discardableResult
    public func offset(_ count: Int) -> QueryBuilder {
        BlazeLogger.debug("Query: OFFSET \(count)")
        self.offsetValue = count
        return self
    }
    
    // MARK: - Aggregations
    
    /// Group results by one or more fields
    @discardableResult
    public func groupBy(_ fields: String...) -> QueryBuilder {
        BlazeLogger.debug("Query: GROUP BY \(fields.joined(separator: ", "))")
        self.groupByFields.append(contentsOf: fields)
        return self
    }
    
    /// Group results by an array of fields
    @discardableResult
    public func groupBy(_ fields: [String]) -> QueryBuilder {
        BlazeLogger.debug("Query: GROUP BY \(fields.joined(separator: ", "))")
        self.groupByFields.append(contentsOf: fields)
        return self
    }
    
    /// Add aggregation operations
    @discardableResult
    public func aggregate(_ operations: [AggregationType]) -> QueryBuilder {
        BlazeLogger.debug("Query: AGGREGATE \(operations.count) operations")
        self.aggregations.append(contentsOf: operations)
        return self
    }
    
    /// Count records (convenience)
    @discardableResult
    public func count(as alias: String? = nil) -> QueryBuilder {
        BlazeLogger.debug("Query: COUNT")
        self.aggregations.append(.count(as: alias))
        return self
    }
    
    /// Sum a numeric field
    @discardableResult
    public func sum(_ field: String, as alias: String? = nil) -> QueryBuilder {
        BlazeLogger.debug("Query: SUM(\(field))")
        self.aggregations.append(.sum(field, as: alias))
        return self
    }
    
    /// Calculate average of a field
    @discardableResult
    public func avg(_ field: String, as alias: String? = nil) -> QueryBuilder {
        BlazeLogger.debug("Query: AVG(\(field))")
        self.aggregations.append(.avg(field, as: alias))
        return self
    }
    
    /// Find minimum value of a field
    @discardableResult
    public func min(_ field: String, as alias: String? = nil) -> QueryBuilder {
        BlazeLogger.debug("Query: MIN(\(field))")
        self.aggregations.append(.min(field, as: alias))
        return self
    }
    
    /// Find maximum value of a field
    @discardableResult
    public func max(_ field: String, as alias: String? = nil) -> QueryBuilder {
        BlazeLogger.debug("Query: MAX(\(field))")
        self.aggregations.append(.max(field, as: alias))
        return self
    }
    
    /// Filter aggregated results (HAVING clause)
    @discardableResult
    public func having(_ predicate: @escaping (AggregationResult) -> Bool) -> QueryBuilder {
        BlazeLogger.debug("Query: HAVING <predicate>")
        self.havingPredicate = predicate
        return self
    }
    
    // MARK: - Execution (Unified Smart API)
    
    /// Execute the query and return a unified QueryResult.
    /// This method intelligently detects the query type (normal, join, aggregation, grouped)
    /// and returns the appropriate result wrapped in QueryResult.
    ///
    /// Example usage:
    /// ```swift
    /// // Normal query
    /// let result = try db.query().where("status", equals: .string("open")).execute()
    /// let records = try result.records  // Extract records
    ///
    /// // Join query (automatic detection!)
    /// let result = try db.query().join(usersDB.collection, on: "authorId").execute()
    /// let joined = try result.joined  // Extract joined records
    ///
    /// // Aggregation (automatic detection!)
    /// let result = try db.query().count().execute()
    /// let count = try result.aggregation.count  // Extract count
    ///
    /// // Grouped aggregation (automatic detection!)
    /// let result = try db.query().groupBy("team").count().execute()
    /// let groups = try result.grouped  // Extract grouped results
    /// ```
    public func execute() throws -> QueryResult {
        guard collection != nil else {
            BlazeLogger.error("Query execution failed: Collection has been deallocated")
            throw BlazeDBError.invalidData(reason: "Query builder's collection has been deallocated. Recreate the query from a live database.")
        }
        
        // Validate query before execution
        try validateQuery()
        
        BlazeLogger.info("Executing unified query (auto-detecting type)")
        
        // Detect query type and execute appropriately
        if !groupByFields.isEmpty && !aggregations.isEmpty {
            // Grouped aggregation
            BlazeLogger.debug("✓ Detected: Grouped aggregation query")
            let result = try _executeGroupedAggregation()
            return .grouped(result)
        } else if !aggregations.isEmpty {
            // Simple aggregation
            BlazeLogger.debug("✓ Detected: Aggregation query")
            let result = try _executeAggregation()
            return .aggregation(result)
        } else if !joinOperations.isEmpty {
            // Join query
            BlazeLogger.debug("✓ Detected: JOIN query")
            let result = try _executeJoin()
            return .joined(result)
        } else {
            // Normal query
            BlazeLogger.debug("✓ Detected: Standard query")
            let result = try _executeStandard()
            return .records(result)
        }
    }
    
    /// Execute with caching support (unified)
    public func execute(withCache ttl: TimeInterval) throws -> QueryResult {
        let cacheKey = generateCacheKey()
        BlazeLogger.debug("Checking cache with key: \(cacheKey.prefix(8))...")
        
        // Try cache first
        if let cached: QueryResult = QueryCache.shared.get(key: cacheKey) {
            BlazeLogger.info("Cache HIT: returning cached result")
            return cached
        }
        
        // Cache miss, execute and cache
        BlazeLogger.debug("Cache MISS: executing query")
        let result = try execute()
        QueryCache.shared.set(key: cacheKey, value: result, ttl: ttl)
        BlazeLogger.info("Cached result with TTL: \(ttl)s")
        
        return result
    }
    
    // MARK: - Execution (Legacy Specific Methods - Deprecated)
    
    /// Execute standard query and return matching records
    /// - Note: This method is deprecated. Use `execute()` which auto-detects query type and returns QueryResult
    @available(*, deprecated, message: "Use execute() which returns QueryResult and auto-detects query type")
    public func executeStandard() throws -> [BlazeDataRecord] {
        return try _executeStandard()
    }
    
    /// Internal: Execute standard query (non-deprecated)
    private func _executeStandard() throws -> [BlazeDataRecord] {
        guard let collection = collection else {
            BlazeLogger.error("Query execution failed: Collection has been deallocated")
            throw BlazeDBError.invalidData(reason: "Query builder's collection has been deallocated. Recreate the query from a live database.")
        }
        
        let startTime = Date()
        BlazeLogger.info("Executing query with \(filters.count) filters, \(sortOperations.count) sorts, limit: \(limitValue.map { String($0) } ?? "none"), offset: \(offsetValue)")
        
        // Step 1: Fetch all records
        var records = try collection.fetchAll()
        BlazeLogger.debug("Loaded \(records.count) records from storage")
        
        // Step 2: Apply filters using lazy evaluation (single allocation at end)
        let preFilterCount = records.count
        
        if !filters.isEmpty {
            // Combine all filters into single predicate for efficiency
            let combinedFilter: (BlazeDataRecord) -> Bool = { record in
                for filter in self.filters {
                    if !filter(record) { return false }
                }
                return true
            }
            
            // Single pass through data (much faster!)
            records = records.filter(combinedFilter)
            
            // Log individual filter stats if trace enabled
            if BlazeLogger.level >= .trace {
                var tempRecords = records
                for (index, filter) in filters.enumerated() {
                    let beforeCount = tempRecords.count
                    tempRecords = tempRecords.filter(filter)
                    let filtered = beforeCount - tempRecords.count
                    BlazeLogger.trace("Filter \(index + 1): removed \(filtered) records (\(tempRecords.count) remaining)")
                }
            }
            
            if preFilterCount > records.count {
                BlazeLogger.debug("Filters reduced \(preFilterCount) → \(records.count) records (\(String(format: "%.1f", Double(records.count) / Double(preFilterCount) * 100))% retained)")
            }
        }
        
        // Step 3: Apply sorts
        if !sortOperations.isEmpty {
            BlazeLogger.debug("Sorting by \(sortOperations.count) field(s)")
            records = applySorts(to: records)
        }
        
        // Step 4: Apply offset
        if offsetValue > 0 {
            let beforeOffset = records.count
            records = Array(records.dropFirst(Swift.min(offsetValue, records.count)))
            BlazeLogger.debug("Offset: skipped \(beforeOffset - records.count) records (\(records.count) remaining)")
        }
        
        // Step 5: Apply limit
        if let limit = limitValue {
            let beforeLimit = records.count
            records = Array(records.prefix(Swift.max(0, limit)))
            if beforeLimit > records.count {
                BlazeLogger.debug("Limit: reduced \(beforeLimit) → \(records.count) records")
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        BlazeLogger.info("Query complete: \(records.count) results in \(String(format: "%.2f", duration * 1000))ms")
        
        return records
    }
    
    /// Execute query and return joined records
    /// - Note: This method is deprecated. Use `execute()` which auto-detects query type and returns QueryResult
    @available(*, deprecated, message: "Use execute() which returns QueryResult and auto-detects query type")
    public func executeJoin() throws -> [JoinedRecord] {
        return try _executeJoin()
    }
    
    /// Internal: Execute JOIN query (non-deprecated)
    private func _executeJoin() throws -> [JoinedRecord] {
        guard let collection = collection else {
            BlazeLogger.error("Join execution failed: Collection has been deallocated")
            throw BlazeDBError.invalidData(reason: "Query builder's collection has been deallocated. Recreate the query from a live database.")
        }
        
        let startTime = Date()
        
        guard !joinOperations.isEmpty else {
            BlazeLogger.error("executeJoin() called but no join operations defined. Use .join() first")
            throw BlazeDBError.invalidQuery(reason: "No join operations defined", suggestion: "Add .join() before .execute()")
        }
        
        BlazeLogger.info("Executing JOIN query with \(filters.count) pre-filters, \(joinOperations.count) join(s)")
        
        // Step 1: Apply pre-join filters (OPTIMIZATION: reduce data before joining!)
        var records = try collection.fetchAll()
        let originalCount = records.count
        BlazeLogger.debug("Loaded \(records.count) records from left collection")
        
        // Apply filters using combined predicate (single pass, more efficient)
        if !filters.isEmpty {
            let combinedFilter: (BlazeDataRecord) -> Bool = { record in
                for filter in self.filters {
                    if !filter(record) { return false }
                }
                return true
            }
            
            records = records.filter(combinedFilter)
            
            // Log individual filter stats if trace enabled
            if BlazeLogger.level >= .trace {
                var tempRecords = records
                for (index, filter) in filters.enumerated() {
                    let beforeCount = tempRecords.count
                    tempRecords = tempRecords.filter(filter)
                    let filtered = beforeCount - tempRecords.count
                    BlazeLogger.trace("Pre-join filter \(index + 1): removed \(filtered) records")
                }
            }
            
            if originalCount > records.count {
                BlazeLogger.info("Pre-join filters reduced \(originalCount) → \(records.count) records (saves join work!)")
            }
        }
        
        // Step 2: Perform joins
        guard let joinOp = joinOperations.first else {
            BlazeLogger.error("Join operation list is empty")
            throw BlazeDBError.invalidQuery(reason: "No join operation defined", suggestion: "Add .join() before .execute()")
        }
        
        BlazeLogger.debug("Performing \(joinOp.type) join on \(joinOp.foreignKey) = \(joinOp.primaryKey)")
        var joinedResults = try performJoin(records: records, operation: joinOp)
        BlazeLogger.debug("Join produced \(joinedResults.count) results")
        
        // Step 3: Apply sorts on joined records
        if !sortOperations.isEmpty {
            BlazeLogger.debug("Sorting joined results by \(sortOperations.count) field(s)")
            joinedResults = applySortsToJoined(joinedResults)
        }
        
        // Step 4: Apply offset
        if offsetValue > 0 {
            let beforeOffset = joinedResults.count
            joinedResults = Array(joinedResults.dropFirst(Swift.min(offsetValue, joinedResults.count)))
            BlazeLogger.debug("Offset: \(beforeOffset) → \(joinedResults.count) records")
        }
        
        // Step 5: Apply limit
        if let limit = limitValue {
            let beforeLimit = joinedResults.count
            joinedResults = Array(joinedResults.prefix(Swift.max(0, limit)))
            if beforeLimit > joinedResults.count {
                BlazeLogger.debug("Limit: \(beforeLimit) → \(joinedResults.count) records")
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        BlazeLogger.info("JOIN query complete: \(joinedResults.count) results in \(String(format: "%.2f", duration * 1000))ms")
        
        return joinedResults
    }
    
    /// Execute aggregation query (without grouping)
    /// - Note: This method is deprecated. Use `execute()` which auto-detects query type and returns QueryResult
    @available(*, deprecated, message: "Use execute() which returns QueryResult and auto-detects query type")
    public func executeAggregation() throws -> AggregationResult {
        return try _executeAggregation()
    }
    
    /// Internal: Execute aggregation query (non-deprecated)
    private func _executeAggregation() throws -> AggregationResult {
        guard let collection = collection else {
            BlazeLogger.error("Aggregation execution failed: Collection has been deallocated")
            throw BlazeDBError.invalidData(reason: "Query builder's collection has been deallocated. Recreate the query from a live database.")
        }
        
        guard !aggregations.isEmpty else {
            BlazeLogger.error("executeAggregation() called but no aggregations defined")
            throw BlazeDBError.invalidQuery(reason: "No aggregations defined", suggestion: "Add .count(), .sum(), or .avg() before .execute()")
        }
        
        let startTime = Date()
        BlazeLogger.info("Executing aggregation query with \(aggregations.count) operations")
        
        // Fetch and filter records
        var records = try collection.fetchAll()
        let originalCount = records.count
        BlazeLogger.debug("Loaded \(records.count) records from storage")
        
        // Apply filters
        if !filters.isEmpty {
            let combinedFilter: (BlazeDataRecord) -> Bool = { record in
                for filter in self.filters {
                    if !filter(record) { return false }
                }
                return true
            }
            records = records.filter(combinedFilter)
            BlazeLogger.debug("Filters reduced \(originalCount) → \(records.count) records")
        }
        
        // Perform aggregations
        let result = AggregationEngine.aggregate(records: records, operations: aggregations)
        
        let duration = Date().timeIntervalSince(startTime)
        BlazeLogger.info("Aggregation complete: \(aggregations.count) operations on \(records.count) records in \(String(format: "%.2f", duration * 1000))ms")
        
        return result
    }
    
    /// Execute grouped aggregation query (with GROUP BY)
    /// - Note: This method is deprecated. Use `execute()` which auto-detects query type and returns QueryResult
    @available(*, deprecated, message: "Use execute() which returns QueryResult and auto-detects query type")
    public func executeGroupedAggregation() throws -> GroupedAggregationResult {
        return try _executeGroupedAggregation()
    }
    
    /// Internal: Execute grouped aggregation query (non-deprecated)
    private func _executeGroupedAggregation() throws -> GroupedAggregationResult {
        guard let collection = collection else {
            BlazeLogger.error("Grouped aggregation execution failed: Collection has been deallocated")
            throw BlazeDBError.invalidData(reason: "Query builder's collection has been deallocated. Recreate the query from a live database.")
        }
        
        guard !groupByFields.isEmpty else {
            BlazeLogger.error("executeGroupedAggregation() called but no groupBy defined")
            throw BlazeDBError.invalidQuery(reason: "No groupBy defined", suggestion: "Add .groupBy() before .execute()")
        }

        guard !aggregations.isEmpty else {
            BlazeLogger.error("executeGroupedAggregation() called but no aggregations defined")
            throw BlazeDBError.invalidQuery(reason: "No aggregations defined for grouped query", suggestion: "Add .count(), .sum(), or .avg() after .groupBy()")
        }
        
        let startTime = Date()
        BlazeLogger.info("Executing grouped aggregation: GROUP BY \(groupByFields.joined(separator: ", ")) with \(aggregations.count) operations")
        
        // Fetch and filter records
        var records = try collection.fetchAll()
        let originalCount = records.count
        BlazeLogger.debug("Loaded \(records.count) records from storage")
        
        // Apply filters
        if !filters.isEmpty {
            let combinedFilter: (BlazeDataRecord) -> Bool = { record in
                for filter in self.filters {
                    if !filter(record) { return false }
                }
                return true
            }
            records = records.filter(combinedFilter)
            BlazeLogger.debug("Filters reduced \(originalCount) → \(records.count) records")
        }
        
        // Perform grouped aggregation
        var result = AggregationEngine.aggregateGrouped(
            records: records,
            groupByFields: groupByFields,
            operations: aggregations
        )
        
        BlazeLogger.debug("Grouped into \(result.groups.count) groups")
        
        // Apply HAVING filter
        if let havingPredicate = havingPredicate {
            let beforeCount = result.groups.count
            result.groups = result.groups.filter { havingPredicate($0.value) }
            if beforeCount > result.groups.count {
                BlazeLogger.debug("HAVING reduced \(beforeCount) → \(result.groups.count) groups")
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        BlazeLogger.info("Grouped aggregation complete: \(result.groups.count) groups from \(records.count) records in \(String(format: "%.2f", duration * 1000))ms")
        
        return result
    }
    
    // MARK: - Helpers
    
    /// Generate a unique cache key for this query
    internal func generateCacheKey() -> String {
        var key = "q"

        // Include filters with their full descriptors (field, operation, value hash)
        if !filterDescriptors.isEmpty {
            var hasher = Hasher()
            for descriptor in filterDescriptors {
                hasher.combine(descriptor)
            }
            key += "_f\(hasher.finalize())"
        }

        // Include joins
        if !joinOperations.isEmpty {
            key += "_j\(joinOperations.count)"
        }

        // Include sorts
        if !sortOperations.isEmpty {
            key += "_s\(sortOperations.map { $0.field + ($0.descending ? "D" : "A") }.joined(separator: ","))"
        }

        // Include limit/offset
        if let limit = limitValue {
            key += "_l\(limit)"
        }
        if offsetValue > 0 {
            key += "_o\(offsetValue)"
        }

        // Include aggregations
        if !aggregations.isEmpty {
            key += "_a\(aggregations.count)"
        }

        // Include groupBy
        if !groupByFields.isEmpty {
            key += "_g\(groupByFields.joined(separator: ","))"
        }

        return key
    }
    
    private func applySorts(to records: [BlazeDataRecord]) -> [BlazeDataRecord] {
        return records.sorted { (left: BlazeDataRecord, right: BlazeDataRecord) -> Bool in
            for sortOp in sortOperations {
                let leftValue = left.storage[sortOp.field]
                let rightValue = right.storage[sortOp.field]
                
                // Handle nil values (nil sorts last)
                if leftValue == nil && rightValue == nil { continue }
                if leftValue == nil { return false }
                if rightValue == nil { return true }
                
                // Compare values
                if leftValue == rightValue { continue }
                
                guard let lv = leftValue, let rv = rightValue else { continue }
                let comparison = compareFields(lv, .lessThan, rv)
                return sortOp.descending ? !comparison : comparison
            }
            return false
        }
    }
    
    private func applySortsToJoined(_ records: [JoinedRecord]) -> [JoinedRecord] {
        return records.sorted { (left: JoinedRecord, right: JoinedRecord) -> Bool in
            for sortOp in sortOperations {
                // Check left record first, then right
                let leftValue: BlazeDocumentField? = left.left.storage[sortOp.field] ?? left.right?.storage[sortOp.field]
                let rightValue: BlazeDocumentField? = right.left.storage[sortOp.field] ?? right.right?.storage[sortOp.field]
                
                if leftValue == nil && rightValue == nil { continue }
                if leftValue == nil { return false }
                if rightValue == nil { return true }
                
                if leftValue == rightValue { continue }
                
                guard let lv = leftValue, let rv = rightValue else { continue }
                let comparison = compareFields(lv, .lessThan, rv)
                return sortOp.descending ? !comparison : comparison
            }
            return false
        }
    }
    
    private func performJoin(records: [BlazeDataRecord], operation: JoinOperation) throws -> [JoinedRecord] {
        // Collect foreign key values from filtered records
        let foreignKeyValues = Set(records.compactMap { record -> UUID? in
            guard let field = record.storage[operation.foreignKey] else { return nil }
            switch field {
            case .uuid(let uuid): return uuid
            case .string(let str): return UUID(uuidString: str)
            default: 
                BlazeLogger.trace("Foreign key '\(operation.foreignKey)' has incompatible type, skipping record")
                return nil
            }
        })
        
        BlazeLogger.debug("Collected \(foreignKeyValues.count) unique foreign keys for batch fetch")
        
        // Batch fetch from right collection
        BlazeLogger.trace("Batch fetching \(foreignKeyValues.count) records from right collection")
        let rightRecords = try operation.collection.fetchBatch(ids: Array(foreignKeyValues))
        BlazeLogger.debug("Fetched \(rightRecords.count) records from right collection")
        
        // Build joined results
        var results: [JoinedRecord] = []
        var matchedRightIDs = Set<UUID>()
        
        for leftRecord in records {
            guard let field = leftRecord.storage[operation.foreignKey] else {
                if operation.type == .left || operation.type == .full {
                    results.append(JoinedRecord(left: leftRecord, right: nil))
                }
                continue
            }
            
            let foreignKeyValue: UUID?
            switch field {
            case .uuid(let uuid): foreignKeyValue = uuid
            case .string(let str): foreignKeyValue = UUID(uuidString: str)
            default: foreignKeyValue = nil
            }
            
            guard let fkValue = foreignKeyValue else {
                if operation.type == .left || operation.type == .full {
                    results.append(JoinedRecord(left: leftRecord, right: nil))
                }
                continue
            }
            
            if let rightRecord = rightRecords[fkValue] {
                results.append(JoinedRecord(left: leftRecord, right: rightRecord))
                matchedRightIDs.insert(fkValue)
            } else {
                if operation.type == .left || operation.type == .full {
                    results.append(JoinedRecord(left: leftRecord, right: nil))
                }
            }
        }
        
        // Add unmatched right records for right/full joins
        if operation.type == .right || operation.type == .full {
            let unmatchedCount = rightRecords.count - matchedRightIDs.count
            if unmatchedCount > 0 {
                BlazeLogger.debug("Adding \(unmatchedCount) unmatched right records for \(operation.type) join")
            }
            for (rightID, rightRecord) in rightRecords {
                if !matchedRightIDs.contains(rightID) {
                    results.append(JoinedRecord(left: BlazeDataRecord([:]), right: rightRecord))
                }
            }
        }
        
        BlazeLogger.info("Join matched \(matchedRightIDs.count)/\(rightRecords.count) right records, produced \(results.count) results")
        
        return results
    }
}

// MARK: - Supporting Types

internal struct JoinOperation {
    let collection: DynamicCollection
    let foreignKey: String
    let primaryKey: String
    let type: JoinType
}

internal struct SortOperation {
    let field: String
    let descending: Bool
}

// MARK: - Comparison Helper

/// Comparison operation type
internal enum ComparisonOp {
    case lessThan
    case greaterThan
}

/// Check if two BlazeDocumentFields are equal (with cross-type support)
internal func fieldsEqual(_ lhs: BlazeDocumentField, _ rhs: BlazeDocumentField) -> Bool {
    // Direct equality
    if lhs == rhs { return true }
    
    // Cross-type equality checks
    switch (lhs, rhs) {
    // Date/Timestamp equality (Double)
    case (.double(let l), .date(let r)):
        return abs(l - r.timeIntervalSinceReferenceDate) < 0.001  // Allow small floating-point difference
    case (.date(let l), .double(let r)):
        return abs(l.timeIntervalSinceReferenceDate - r) < 0.001
    
    // Date/Timestamp equality (Int - for whole-second timestamps)
    case (.int(let l), .date(let r)):
        return abs(Double(l) - r.timeIntervalSinceReferenceDate) < 0.001
    case (.date(let l), .int(let r)):
        return abs(l.timeIntervalSinceReferenceDate - Double(r)) < 0.001
    
    // String and Data are distinct types; no implicit conversion
    case (.string, .data), (.data, .string):
        return false
    
    // Int/Double equality
    case (.int(let l), .double(let r)):
        return Double(l) == r
    case (.double(let l), .int(let r)):
        return l == Double(r)
    
    default:
        return false
    }
}

/// Compare two BlazeDocumentFields with a specific operation
internal func compareFields(
    _ lhs: BlazeDocumentField,
    _ op: ComparisonOp,
    _ rhs: BlazeDocumentField
) -> Bool {
    switch (lhs, rhs) {
    case (.int(let l), .int(let r)):
        return op == .lessThan ? l < r : l > r
    case (.double(let l), .double(let r)):
        return op == .lessThan ? l < r : l > r
    case (.string(let l), .string(let r)):
        return op == .lessThan ? l < r : l > r
    case (.date(let l), .date(let r)):
        return op == .lessThan ? l < r : l > r
    case (.bool(let l), .bool(let r)):
        return op == .lessThan ? !l && r : l && !r
    case (.uuid(let l), .uuid(let r)):
        return op == .lessThan ? l.uuidString < r.uuidString : l.uuidString > r.uuidString
    case (.data(let l), .data(let r)):
        // Compare Data by count (size comparison)
        return op == .lessThan ? l.count < r.count : l.count > r.count
    
    // String and Data are distinct types; no implicit ordering
    case (.string, .data), (.data, .string):
        return false
    
    // Numeric cross-type comparisons
    case (.int(let l), .double(let r)):
        return op == .lessThan ? Double(l) < r : Double(l) > r
    case (.double(let l), .int(let r)):
        return op == .lessThan ? l < Double(r) : l > Double(r)
    
    // Date/Timestamp cross-type comparisons (Double)
    // Dates may be stored as Double (timeIntervalSinceReferenceDate)
    case (.double(let l), .date(let r)):
        // Left is timestamp, right is Date
        return op == .lessThan ? l < r.timeIntervalSinceReferenceDate : l > r.timeIntervalSinceReferenceDate
    case (.date(let l), .double(let r)):
        // Left is Date, right is timestamp
        return op == .lessThan ? l.timeIntervalSinceReferenceDate < r : l.timeIntervalSinceReferenceDate > r
    
    // Date/Timestamp cross-type comparisons (Int - for whole-second timestamps)
    case (.int(let l), .date(let r)):
        // Left is int timestamp, right is Date
        return op == .lessThan ? Double(l) < r.timeIntervalSinceReferenceDate : Double(l) > r.timeIntervalSinceReferenceDate
    case (.date(let l), .int(let r)):
        // Left is Date, right is int timestamp
        return op == .lessThan ? l.timeIntervalSinceReferenceDate < Double(r) : l.timeIntervalSinceReferenceDate > Double(r)
    
    default:
        return false
    }
}

/// Compare two BlazeDocumentFields (legacy, using closure)
private func compare(
    _ lhs: BlazeDocumentField,
    _ op: (Any, Any) -> Bool,
    _ rhs: BlazeDocumentField
) -> Bool {
    switch (lhs, rhs) {
    case (.int(let l), .int(let r)):
        return op(l, r)
    case (.double(let l), .double(let r)):
        return op(l, r)
    case (.string(let l), .string(let r)):
        return op(l, r)
    case (.date(let l), .date(let r)):
        return op(l, r)
    case (.bool(let l), .bool(let r)):
        return op(l, r)
    case (.uuid(let l), .uuid(let r)):
        return op(l.uuidString, r.uuidString)
    case (.int(let l), .double(let r)):
        return op(Double(l), r)
    case (.double(let l), .int(let r)):
        return op(l, Double(r))
    default:
        return false
    }
}

// MARK: - Query Cursor for Batch Fetching

/// A cursor for iterating over query results in batches
/// Provides memory-efficient access to large result sets
public final class QueryCursor: Sequence, IteratorProtocol {
    private let records: [BlazeDataRecord]
    private let batchSize: Int
    private var currentIndex: Int = 0
    
    /// Total number of records in the result set
    public let totalCount: Int
    
    /// Number of batches remaining
    public var batchesRemaining: Int {
        let remaining = totalCount - currentIndex
        return (remaining + batchSize - 1) / batchSize
    }
    
    /// Whether there are more records to fetch
    public var hasMore: Bool {
        return currentIndex < totalCount
    }
    
    /// Current position in the result set
    public var currentPosition: Int {
        return currentIndex
    }
    
    internal init(records: [BlazeDataRecord], batchSize: Int) {
        self.records = records
        self.batchSize = Swift.max(1, batchSize)
        self.totalCount = records.count
    }
    
    /// Fetch the next batch of records
    /// - Returns: Array of records, or nil if no more records
    public func next() -> [BlazeDataRecord]? {
        guard hasMore else { return nil }
        
        let endIndex = Swift.min(currentIndex + batchSize, totalCount)
        let batch = Array(records[currentIndex..<endIndex])
        currentIndex = endIndex
        
        return batch
    }
    
    /// Reset the cursor to the beginning
    public func reset() {
        currentIndex = 0
    }
    
    /// Skip a number of records
    /// - Parameter count: Number of records to skip
    public func skip(_ count: Int) {
        currentIndex = Swift.min(currentIndex + count, totalCount)
    }
    
    /// Get all remaining records (caution: may use significant memory)
    public func fetchAll() -> [BlazeDataRecord] {
        guard hasMore else { return [] }
        let remaining = Array(records[currentIndex...])
        currentIndex = totalCount
        return remaining
    }
    
    /// Iterate over all batches with a closure
    /// - Parameter handler: Closure called for each batch
    public func forEachBatch(_ handler: ([BlazeDataRecord]) throws -> Void) rethrows {
        while let batch = next() {
            try handler(batch)
        }
    }
}

// MARK: - QueryBuilder Cursor Extension

extension QueryBuilder {
    
    /// Execute query and return a cursor for batch iteration
    /// Memory-efficient for large result sets
    ///
    /// - Parameter batchSize: Number of records per batch (default: 100)
    /// - Returns: A cursor for iterating over results in batches
    ///
    /// ## Example
    /// ```swift
    /// let cursor = try db.query()
    ///     .where("status", equals: .string("active"))
    ///     .cursor(batchSize: 50)
    ///
    /// while let batch = cursor.next() {
    ///     for record in batch {
    ///         process(record)
    ///     }
    /// }
    /// ```
    public func cursor(batchSize: Int = 100) throws -> QueryCursor {
        let result = try execute()
        let records = try result.records
        return QueryCursor(records: records, batchSize: batchSize)
    }
    
    /// Execute query and process results in batches
    /// More memory-efficient than loading all records at once
    ///
    /// - Parameters:
    ///   - batchSize: Number of records per batch (default: 100)
    ///   - handler: Closure called for each batch
    /// - Returns: Total number of records processed
    ///
    /// ## Example
    /// ```swift
    /// let processed = try db.query()
    ///     .where("type", equals: .string("order"))
    ///     .forEachBatch(size: 50) { batch in
    ///         for record in batch {
    ///             exportToCSV(record)
    ///         }
    ///     }
    /// print("Processed \(processed) records")
    /// ```
    @discardableResult
    public func forEachBatch(size: Int = 100, handler: ([BlazeDataRecord]) throws -> Void) throws -> Int {
        let cursor = try cursor(batchSize: size)
        var totalProcessed = 0
        
        while let batch = cursor.next() {
            try handler(batch)
            totalProcessed += batch.count
        }
        
        return totalProcessed
    }
    
    /// Execute query with pagination support
    /// Returns a specific page of results
    ///
    /// - Parameters:
    ///   - page: Page number (1-indexed)
    ///   - pageSize: Number of records per page
    /// - Returns: Records for the specified page
    ///
    /// ## Example
    /// ```swift
    /// // Get page 3 of results (records 21-30)
    /// let page3 = try db.query()
    ///     .orderBy("createdAt", descending: true)
    ///     .page(3, size: 10)
    /// ```
    public func page(_ page: Int, size: Int) throws -> [BlazeDataRecord] {
        guard page > 0 && size > 0 else {
            throw BlazeDBError.invalidInput(reason: "Page must be >= 1 and size must be > 0")
        }
        
        let skipCount = (page - 1) * size
        
        // Use existing offset/limit functionality
        let originalOffset = offsetValue
        let originalLimit = limitValue
        
        offsetValue = skipCount
        limitValue = size
        
        defer {
            offsetValue = originalOffset
            limitValue = originalLimit
        }
        
        let result = try execute()
        return try result.records
    }
}

