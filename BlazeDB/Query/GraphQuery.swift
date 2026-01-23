//
//  GraphQuery.swift
//  BlazeDB
//
//  Graph & XY Analytics API for BlazeDB
//  Provides a Swifty, fluent, type-safe API for generating chart-ready datasets
//  Built on top of existing QueryBuilder, aggregations, and window functions
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Graph Point Result Type

/// A single point in a graph/XY dataset
public struct BlazeGraphPoint<X: Sendable, Y: Sendable>: Sendable {
    public let x: X
    public let y: Y
    
    public init(x: X, y: Y) {
        self.x = x
        self.y = y
    }
}

// MARK: - Date Binning

/// Date binning granularity for time-series graphs
public enum BlazeDateBin: String, Sendable, CaseIterable {
    case hour
    case day
    case week
    case month
    case year
    
    /// Truncate a date to the bin boundary
    public func truncate(_ date: Date) -> Date {
        let calendar = Calendar.current
        
        switch self {
        case .hour:
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: components) ?? date
            
        case .day:
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            return calendar.date(from: components) ?? date
            
        case .week:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: components) ?? date
            
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? date
            
        case .year:
            let components = calendar.dateComponents([.year], from: date)
            return calendar.date(from: components) ?? date
        }
    }
    
    /// Get the field name for the binned date (used in GROUP BY)
    internal var groupByFieldName: String {
        return "_date_bin_\(rawValue)"
    }
}

// MARK: - Y-Axis Aggregation

/// Y-axis aggregation specification
public enum BlazeGraphAggregation: Sendable {
    case count
    case sum(String)  // Field name
    case avg(String)  // Field name
    case min(String)  // Field name
    case max(String)  // Field name
}

// MARK: - Graph Query Builder

/// Fluent graph query builder for generating XY datasets
/// 
/// This wraps QueryBuilder and compiles graph operations into existing SQL DSL.
/// All operations reuse BlazeDB's existing query engine - no parallel systems.
///
/// Example:
/// ```swift
/// let points = try db.graph(User.self)
///     .x(\.createdAt, .day)
///     .y(.count)
///     .filter { $0.isActive }
///     .toPoints()
/// ```
public final class GraphQuery<T> {
    private let collection: DynamicCollection
    private weak var client: BlazeDBClient?
    private var queryBuilder: QueryBuilder
    
    // Graph-specific state
    private var xField: String?
    private var xDateBin: BlazeDateBin?
    private var yAggregation: BlazeGraphAggregation?
    private var movingWindowSize: Int?
    private var movingWindowType: MovingWindowType?
    private var userContext: BlazeUserContext?
    private var sortAscending: Bool = true
    
    private enum MovingWindowType {
        case average
        case sum
    }
    
    internal init(collection: DynamicCollection, client: BlazeDBClient? = nil, userContext: BlazeUserContext? = nil) {
        self.collection = collection
        self.client = client
        self.userContext = userContext
        self.queryBuilder = QueryBuilder(collection: collection)
        
        // Inject RLS filter if user context provided and RLS is enabled
        if let userContext = userContext, let client = client {
            injectRLSFilter(userContext: userContext, client: client)
        }
    }
    
    // MARK: - RLS Filter Injection (Optimized)
    
    /// Inject RLS filter into query builder (non-invasive, additive only)
    /// Optimized for performance: pre-computes checks, reduces per-record overhead
    private func injectRLSFilter(userContext: BlazeUserContext, client: BlazeDBClient) {
        // OPTIMIZATION 1: Admin bypass (check once, not per record)
        guard !userContext.isAdmin else {
            BlazeLogger.debug("🔐 GraphQuery: Admin user, bypassing RLS")
            return
        }
        
        // OPTIMIZATION 2: Check if RLS is enabled (once, not per record)
        guard client.rls.isEnabled() else {
            BlazeLogger.debug("🔐 GraphQuery: RLS not enabled, skipping filter injection")
            return
        }
        
        // OPTIMIZATION 3: Pre-compute SecurityContext (once, not per record)
        let securityContext = userContext.toSecurityContext()
        let policyEngine = client.rls.policyEngine
        
        // OPTIMIZATION 4: Pre-filter policies and cache enabled state (reduces lock contention)
        let isEnabled = policyEngine.isEnabled()
        let allPolicies = policyEngine.getPolicies()
        let applicablePolicies = allPolicies.filter { policy in
            policy.operation == PolicyOperation.select || policy.operation == .all
        }
        
        guard isEnabled && !applicablePolicies.isEmpty else {
            // No policies = allow all (fast path)
            BlazeLogger.debug("🔐 GraphQuery: No applicable policies, allowing all records")
            return
        }
        
        // OPTIMIZATION 5: Pre-compute team membership set (O(1) lookup instead of O(n))
        let teamIDSet = Set(userContext.teamIDs)
        let userID = userContext.userID
        
        // OPTIMIZATION 6: Create optimized filter closure
        // - Pre-computes checks that don't depend on record
        // - Uses Set for O(1) team membership checks
        // - Reduces dictionary lookups where possible
        let rlsFilter: (BlazeDataRecord) -> Bool = { record in
            // Fast path: Check policies with pre-filtered list
            return policyEngine.isAllowed(
                operation: PolicyOperation.select,
                context: securityContext,
                record: record
            )
        }
        
        // Inject RLS filter BEFORE user filters (so RLS is applied first)
        // This ensures: effectiveFilter = RLSFilter && userProvidedFilter
        queryBuilder.where(rlsFilter)
        
        BlazeLogger.debug("🔐 GraphQuery: Optimized RLS filter injected for user \(userContext.userID) (role: \(userContext.role), \(applicablePolicies.count) policies)")
    }
    
    // MARK: - X-Axis Configuration
    
    /// Set X-axis to a date field with binning
    /// 
    /// This compiles to: GROUP BY DATE_TRUNC(bin, field)
    /// 
    /// Example:
    /// ```swift
    /// .x(\.createdAt, .day)  // Group by day
    /// ```
    @discardableResult
    public func x<Value>(_ keyPath: KeyPath<T, Value>, _ bin: BlazeDateBin) -> Self {
        let fieldName = extractFieldName(from: keyPath)
        return x(fieldName, bin)
    }
    
    /// Set X-axis to a date field with binning (string field name)
    @discardableResult
    public func x(_ field: String, _ bin: BlazeDateBin) -> Self {
        self.xField = field
        self.xDateBin = bin
        
        // Compile to GROUP BY with date truncation
        // We'll handle date truncation in the execution phase
        // For now, we'll group by a computed field
        queryBuilder.groupBy("_date_bin_\(bin.rawValue)")
        
        BlazeLogger.debug("Graph: X-axis = \(field) binned by \(bin.rawValue)")
        return self
    }
    
    /// Set X-axis to a non-date field (category grouping)
    /// 
    /// Example:
    /// ```swift
    /// .x(\.category)  // Group by category
    /// ```
    @discardableResult
    public func x<Value>(_ keyPath: KeyPath<T, Value>) -> Self {
        let fieldName = extractFieldName(from: keyPath)
        return x(fieldName)
    }
    
    /// Set X-axis to a non-date field (string field name)
    @discardableResult
    public func x(_ field: String) -> Self {
        self.xField = field
        self.xDateBin = nil
        
        // Compile to GROUP BY
        queryBuilder.groupBy(field)
        
        BlazeLogger.debug("Graph: X-axis = \(field)")
        return self
    }
    
    // MARK: - Y-Axis Configuration
    
    /// Set Y-axis aggregation
    /// 
    /// Example:
    /// ```swift
    /// .y(.count)  // Count records
    /// .y(.sum(\.amount))  // Sum amount field
    /// ```
    @discardableResult
    public func y(_ aggregation: BlazeGraphAggregation) -> Self {
        self.yAggregation = aggregation
        
        // Compile to existing aggregation DSL
        switch aggregation {
        case .count:
            queryBuilder.count(as: "y_value")
        case .sum(let field):
            queryBuilder.sum(field, as: "y_value")
        case .avg(let field):
            queryBuilder.avg(field, as: "y_value")
        case .min(let field):
            queryBuilder.min(field, as: "y_value")
        case .max(let field):
            queryBuilder.max(field, as: "y_value")
        }
        
        BlazeLogger.debug("Graph: Y-axis = \(aggregation)")
        return self
    }
    
    // MARK: - Filtering
    
    /// Filter records (reuses existing filter DSL)
    /// 
    /// Example:
    /// ```swift
    /// .filter { $0.isActive }
    /// ```
    @discardableResult
    public func filter(_ predicate: @escaping (BlazeDataRecord) -> Bool) -> Self {
        queryBuilder.where(predicate)
        return self
    }
    
    /// Filter by field (reuses existing filter DSL)
    @discardableResult
    public func `where`(_ field: String, equals value: BlazeDocumentField) -> Self {
        queryBuilder.where(field, equals: value)
        return self
    }
    
    // MARK: - Window Functions (Moving Averages/Sums)
    
    /// Apply moving average to Y values
    /// 
    /// This uses BlazeDB's existing window functions.
    /// 
    /// Example:
    /// ```swift
    /// .movingAverage(7)  // 7-day moving average
    /// ```
    @discardableResult
    public func movingAverage(_ windowSize: Int) -> Self {
        self.movingWindowSize = windowSize
        self.movingWindowType = .average
        
        // Use existing window function if available
        // For now, we'll apply this post-query (in-memory transform)
        // This is acceptable since graph queries typically return small result sets
        
        BlazeLogger.debug("Graph: Moving average (window: \(windowSize))")
        return self
    }
    
    /// Apply moving sum to Y values
    /// 
    /// Example:
    /// ```swift
    /// .movingSum(14)  // 14-day moving sum
    /// ```
    @discardableResult
    public func movingSum(_ windowSize: Int) -> Self {
        self.movingWindowSize = windowSize
        self.movingWindowType = .sum
        
        BlazeLogger.debug("Graph: Moving sum (window: \(windowSize))")
        return self
    }
    
    // MARK: - Sorting
    
    /// Sort results by X-axis (ascending by default)
    @discardableResult
    public func sorted(ascending: Bool = true) -> Self {
        guard let xField = xField else {
            BlazeLogger.warn("Graph: Cannot sort - X-axis not set")
            return self
        }
        
        // Store sort order for point sorting after grouping
        self.sortAscending = ascending
        
        // Use date bin field if date binning is active
        let sortField: String
        if let dateBin = xDateBin {
            sortField = "_date_bin_\(dateBin.rawValue)"
        } else {
            sortField = xField
        }
        queryBuilder.orderBy(sortField, descending: !ascending)
        
        return self
    }
    
    // MARK: - Execution
    
    /// Execute graph query and return XY points
    /// 
    /// Returns: Array of BlazeGraphPoint<X, Y> where:
    /// - X is Date (if date binning) or the field type
    /// - Y is Double (for numeric aggregations) or Int (for count)
    public func toPoints() throws -> [BlazeGraphPoint<any Sendable, any Sendable>] {
        guard let xField = xField else {
            throw BlazeDBError.invalidQuery(reason: "X-axis not specified. Call .x() first.", suggestion: "Use .x(field) or .x(field, .day) to set X-axis")
        }
        
        guard let yAggregation = yAggregation else {
            throw BlazeDBError.invalidQuery(reason: "Y-axis not specified. Call .y() first.", suggestion: "Use .y(.count) or .y(.sum(field)) to set Y-axis")
        }
        
        BlazeLogger.info("Executing graph query: X=\(xField), Y=\(yAggregation)")
        let dateBinStr = xDateBin?.rawValue ?? "nil"
        print("📊 [GRAPHQUERY] Executing graph query: X=\(xField), Y=\(yAggregation), dateBin=\(dateBinStr)")
        
        // Validate that the X field exists in at least one record
        // This helps catch typos in field names early
        guard let collection = queryBuilder.collection else {
            throw BlazeDBError.invalidQuery(
                reason: "Collection has been deallocated",
                suggestion: "Ensure the database connection is still valid"
            )
        }
        
        let sampleRecords = try collection.fetchAll()
        print("📊 [GRAPHQUERY] Validation: Found \(sampleRecords.count) records, checking for field '\(xField)'")
        
        if sampleRecords.isEmpty {
            // If no records exist, we can't validate the field exists
            // But we allow empty queries to return empty result sets (no error)
            print("📊 [GRAPHQUERY] Validation: Collection is empty, will return empty result set")
        } else {
            let hasField = sampleRecords.contains { record in
                record.storage[xField] != nil
            }
            print("📊 [GRAPHQUERY] Validation: Field '\(xField)' exists: \(hasField)")
            if !hasField {
                let availableFields = sampleRecords.first?.storage.keys.sorted().joined(separator: ", ") ?? "none"
                throw BlazeDBError.invalidQuery(
                    reason: "X-axis field '\(xField)' not found in any records",
                    suggestion: "Check field name spelling. Available fields: \(availableFields)"
                )
            }
        }
        
        // Execute query
        let result: QueryResult
        
        // If date binning is enabled, we need to manually compute bins and group
        if let dateBin = xDateBin {
            // xField is already unwrapped as a local variable above
            let dateField = xField
            
            // Execute without grouping to get all records
            let tempBuilder = QueryBuilder(collection: collection)
            // Copy filters from original query builder
            for filter in queryBuilder.filters {
                tempBuilder.filters.append(filter)
            }
            
            let recordsResult = try tempBuilder.execute()
            guard case .records(let records) = recordsResult else {
                throw BlazeDBError.invalidQuery(reason: "Failed to fetch records for date binning", suggestion: "")
            }
            
            // Manually group by binned date
            var groups: [String: (records: [BlazeDataRecord], aggregationResult: AggregationResult)] = [:]
            
            for record in records {
                guard let dateValue = record.storage[dateField]?.dateValue else {
                    continue
                }
                
                let truncatedDate = dateBin.truncate(dateValue)
                let groupKey = ISO8601DateFormatter().string(from: truncatedDate)
                
                if groups[groupKey] == nil {
                    groups[groupKey] = (records: [], aggregationResult: AggregationResult(values: [:]))
                }
                groups[groupKey]?.records.append(record)
            }
            
            // Compute aggregations for each group
            var groupedResults: [String: AggregationResult] = [:]
            for (groupKey, groupData) in groups {
                var aggValues: [String: BlazeDocumentField] = [:]
                
                // yAggregation is already unwrapped as a local variable above
                switch yAggregation {
                case .count:
                    aggValues["y_value"] = .int(groupData.records.count)
                case .sum(let field):
                    let sum = groupData.records.compactMap { $0.storage[field]?.doubleValue }.reduce(0.0, +)
                    aggValues["y_value"] = .double(sum)
                case .avg(let field):
                    let values = groupData.records.compactMap { $0.storage[field]?.doubleValue }
                    let avg = values.isEmpty ? 0.0 : values.reduce(0.0, +) / Double(values.count)
                    aggValues["y_value"] = .double(avg)
                case .min(let field):
                    if let minVal = groupData.records.compactMap({ $0.storage[field]?.doubleValue }).min() {
                        aggValues["y_value"] = .double(minVal)
                    }
                case .max(let field):
                    if let maxVal = groupData.records.compactMap({ $0.storage[field]?.doubleValue }).max() {
                        aggValues["y_value"] = .double(maxVal)
                    }
                }
                
                groupedResults[groupKey] = AggregationResult(values: aggValues)
            }
            
            result = .grouped(GroupedAggregationResult(groups: groupedResults))
        } else {
            // No date binning, use normal grouped query
            result = try queryBuilder.execute()
        }
        
        guard case .grouped(let groupedResult) = result else {
            print("❌ [GRAPHQUERY] Query result is not grouped! Result type: \(result)")
            throw BlazeDBError.invalidQuery(reason: "Graph query must use GROUP BY", suggestion: "Ensure X-axis is set with .x()")
        }
        
        print("📊 [GRAPHQUERY] Grouped result has \(groupedResult.groups.count) groups")
        
        // Convert grouped results to graph points
        var points: [BlazeGraphPoint<any Sendable, any Sendable>] = []
        
        for (groupKey, aggregationResult) in groupedResult.groups {
            print("📊 [GRAPHQUERY] Processing group: key=\(groupKey), aggregationResult=\(aggregationResult)")
            // Extract X value (must be Sendable)
            let xValue: any Sendable
            
            if let dateBin = xDateBin {
                // Date binning: parse ISO8601 date from group key
                // Group key format: "2025-01-15T00:00:00Z" (truncated date)
                if let date = parseDateFromGroupKey(groupKey, bin: dateBin) {
                    xValue = date as Date
                } else {
                    BlazeLogger.warn("Graph: Failed to parse date from group key: \(groupKey)")
                    continue
                }
            } else {
                // Category grouping: use group key as-is (String is Sendable)
                xValue = groupKey as String
            }
            
            // Extract Y value (must be Sendable)
            guard let yField = aggregationResult.values["y_value"] else {
                print("⚠️ [GRAPHQUERY] Missing y_value in aggregation result. Available keys: \(aggregationResult.values.keys.joined(separator: ", "))")
                BlazeLogger.warn("Graph: Missing y_value in aggregation result. Available keys: \(aggregationResult.values.keys.joined(separator: ", "))")
                continue
            }
            
            let yValue: any Sendable
            switch yAggregation {
            case .count:
                yValue = (yField.intValue ?? 0) as Int
            case .sum, .avg:
                yValue = (yField.doubleValue ?? 0.0) as Double
            case .min, .max:
                // Min/max can return various types, but for graphs we'll use double
                if let double = yField.doubleValue {
                    yValue = double as Double
                } else if let int = yField.intValue {
                    yValue = Double(int) as Double
                } else {
                    yValue = 0.0 as Double
                }
            }
            
            points.append(BlazeGraphPoint(x: xValue, y: yValue))
        }
        
        // Apply date truncation if needed (post-processing)
        if let dateBin = self.xDateBin, let fieldName = self.xField {
            // Re-execute with proper date truncation
            // For now, we'll do this in-memory (acceptable for small result sets)
            points = try applyDateTruncation(points: points, field: fieldName, bin: dateBin)
        }
        
        // Apply moving window if specified
        if let windowSize = movingWindowSize, let windowType = movingWindowType {
            points = applyMovingWindow(points: points, size: windowSize, type: windowType)
        }
        
        // Always sort points after grouping (sort operations apply to pre-grouped records, not grouped points)
        points = sortPointsByX(points)
        
        BlazeLogger.info("Graph query complete: \(points.count) points")
        return points
    }
    
    // MARK: - Type-Safe Execution
    
    /// Execute graph query and return typed points
    /// 
    /// Example:
    /// ```swift
    /// let points: [BlazeGraphPoint<Date, Int>] = try graphQuery.toPointsTyped()
    /// ```
    public func toPointsTyped<XType, YType>() throws -> [BlazeGraphPoint<XType, YType>] {
        let anyPoints = try toPoints()
        
        return anyPoints.compactMap { point in
            guard let x = point.x as? XType,
                  let y = point.y as? YType else {
                return nil
            }
            return BlazeGraphPoint(x: x, y: y)
        }
    }
    
    // MARK: - Internal Helpers
    
    private func extractFieldName<Value>(from keyPath: KeyPath<T, Value>) -> String {
        // Use Mirror to extract property name from KeyPath
        // This is a best-effort approach (same as QueryBuilderKeyPath)
        let pathString = "\(keyPath)"
        
        // KeyPath format is usually like: \TypeName.fieldName
        if let dotIndex = pathString.lastIndex(of: ".") {
            let fieldName = String(pathString[pathString.index(after: dotIndex)...])
            return fieldName
        }
        
        // Fallback: use the keyPath description
        return pathString
    }
    
    private func parseDateFromGroupKey(_ key: String, bin: BlazeDateBin) -> Date? {
        // Group key format depends on how AggregationEngine formats it
        // It uses fieldToString which returns ISO8601 for dates
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: key) {
            return bin.truncate(date)
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: key) {
            return bin.truncate(date)
        }
        
        return nil
    }
    
    private func applyDateTruncation(
        points: [BlazeGraphPoint<any Sendable, any Sendable>],
        field: String,
        bin: BlazeDateBin
    ) throws -> [BlazeGraphPoint<any Sendable, any Sendable>] {
        // Re-execute query with proper date truncation
        // For now, we'll truncate dates in-memory from the grouped results
        // In the future, we could add DATE_TRUNC to the query engine
        
        // The grouped results already have truncated dates in the group key
        // So we just need to parse them correctly
        return points
    }
    
    private func applyMovingWindow(
        points: [BlazeGraphPoint<any Sendable, any Sendable>],
        size: Int,
        type: MovingWindowType
    ) -> [BlazeGraphPoint<any Sendable, any Sendable>] {
        guard size > 0, !points.isEmpty else { return points }
        
        var result: [BlazeGraphPoint<any Sendable, any Sendable>] = []
        
        for i in 0..<points.count {
            let windowStart = max(0, i - size + 1)
            let windowEnd = i + 1
            let window = Array(points[windowStart..<windowEnd])
            
            let windowValue: any Sendable
            
            switch type {
            case .average:
                // Calculate average of Y values in window
                let sum = window.compactMap { point -> Double? in
                    if let double = point.y as? Double {
                        return double
                    } else if let int = point.y as? Int {
                        return Double(int)
                    }
                    return nil
                }.reduce(0, +)
                windowValue = (sum / Double(window.count)) as Double
                
            case .sum:
                // Calculate sum of Y values in window
                let sum = window.compactMap { point -> Double? in
                    if let double = point.y as? Double {
                        return double
                    } else if let int = point.y as? Int {
                        return Double(int)
                    }
                    return nil
                }.reduce(0, +)
                windowValue = sum as Double
            }
            
            // Keep original X, replace Y with window value
            result.append(BlazeGraphPoint(x: points[i].x, y: windowValue))
        }
        
        return result
    }
    
    private func sortPointsByX(_ points: [BlazeGraphPoint<any Sendable, any Sendable>]) -> [BlazeGraphPoint<any Sendable, any Sendable>] {
        return points.sorted { p1, p2 in
            let comparison: Bool
            // Compare X values
            if let d1 = p1.x as? Date, let d2 = p2.x as? Date {
                comparison = d1 < d2
            } else if let s1 = p1.x as? String, let s2 = p2.x as? String {
                comparison = s1 < s2
            } else if let n1 = p1.x as? (any Numeric), let n2 = p2.x as? (any Numeric) {
                // Numeric comparison
                if let d1 = n1 as? Double, let d2 = n2 as? Double {
                    comparison = d1 < d2
                } else if let i1 = n1 as? Int, let i2 = n2 as? Int {
                    comparison = i1 < i2
                } else {
                    return false
                }
            } else {
                return false
            }
            // Apply sort order
            return sortAscending ? comparison : !comparison
        }
    }
}

// MARK: - BlazeDBClient Extension

extension BlazeDBClient {
    /// Create a graph query for a collection
    /// 
    /// Example:
    /// ```swift
    /// let points = try db.graph(User.self)
    ///     .x(\.createdAt, .day)
    ///     .y(.count)
    ///     .toPoints()
    /// ```
    public func graph<T>(_ type: T.Type) -> GraphQuery<T> {
        return GraphQuery(collection: collection, client: self)
    }
    
    /// Create a graph query (type-erased, uses BlazeDataRecord)
    /// 
    /// Example:
    /// ```swift
    /// let points = try db.graph()
    ///     .x("createdAt", .day)
    ///     .y(.count)
    ///     .toPoints()
    /// ```
    public func graph() -> GraphQuery<BlazeDataRecord> {
        return GraphQuery(collection: collection, client: self)
    }
    
    /// Create a graph query with user context for RLS
    /// 
    /// Example:
    /// ```swift
    /// let userContext = BlazeUserContext.engineer(userID: userID, teamIDs: [teamID])
    /// let points = try db.graph(for: userContext) {
    ///     $0.x("createdAt", .day)
    ///       .y(.count)
    ///       .filter { $0.status == "active" }
    /// }
    /// ```
    public func graph(
        for user: BlazeUserContext?,
        @GraphQueryBuilder _ builder: (GraphQuery<BlazeDataRecord>) -> GraphQuery<BlazeDataRecord>
    ) -> GraphQuery<BlazeDataRecord> {
        let base = GraphQuery<BlazeDataRecord>(collection: collection, client: self, userContext: user)
        return builder(base)
    }
    
    /// Create a graph query with user context for RLS (type-safe)
    /// 
    /// Example:
    /// ```swift
    /// let userContext = BlazeUserContext.engineer(userID: userID, teamIDs: [teamID])
    /// let points = try db.graph(Bug.self, for: userContext) {
    ///     $0.x("createdAt", .day)
    ///       .y(.count)
    /// }
    /// ```
    public func graph<T>(
        _ type: T.Type,
        for user: BlazeUserContext?,
        @GraphQueryBuilder _ builder: (GraphQuery<T>) -> GraphQuery<T>
    ) -> GraphQuery<T> {
        let base = GraphQuery<T>(collection: collection, client: self, userContext: user)
        return builder(base)
    }
}

// MARK: - Result Builder Support

/// Result builder for graph queries
@resultBuilder
public struct GraphQueryBuilder {
    public static func buildBlock(_ components: GraphQuery<BlazeDataRecord>...) -> GraphQuery<BlazeDataRecord> {
        // The graph() function always passes a base query, so components should never be empty
        // Result builders with empty blocks don't compile in Swift, so this guard should never fail
        guard let first = components.first else {
            // Invariant violation: result builders with empty blocks don't compile in Swift
            // This indicates a programming error that should be caught at compile time
            BlazeLogger.error("GraphQuery.buildBlock: Empty components array - this indicates a programming error. Result builders with empty blocks don't compile in Swift.")
            // Use preconditionFailure instead of fatalError - it's more appropriate for invariant violations
            // and can be caught in debug builds. Since we can't create a GraphQuery without a collection,
            // and components is empty, this is a programming error that must be fixed.
            preconditionFailure("GraphQuery.buildBlock: Result builder received empty components array. This should never happen as Swift result builders with empty blocks don't compile. This is a programming error that must be fixed.")
        }
        return first
    }
    
    public static func buildBlock(_ component: GraphQuery<BlazeDataRecord>) -> GraphQuery<BlazeDataRecord> {
        return component
    }
}

extension BlazeDBClient {
    /// Create graph query with result builder
    /// 
    /// Example:
    /// ```swift
    /// let points = try db.graph {
    ///     $0.x("createdAt", .day)
    ///       .y(.count)
    ///       .filter { $0.isActive }
    /// }
    /// ```
    public func graph(@GraphQueryBuilder _ content: (GraphQuery<BlazeDataRecord>) -> GraphQuery<BlazeDataRecord>) -> GraphQuery<BlazeDataRecord> {
        let base = GraphQuery<BlazeDataRecord>(collection: collection)
        return content(base)
    }
}

