//
//  QueryOptimizer.swift
//  BlazeDB
//
//  Cost-based query optimizer
//  Selects optimal query plan based on index availability and data statistics
//
import Foundation

/// Query execution plan
public struct QueryPlan {
    public let useIndex: String?
    public let scanOrder: ScanOrder
    public let estimatedCost: Double
    public let estimatedRows: Int
    
    public enum ScanOrder {
        case sequential
        case index
        case parallel
    }
    
    public init(useIndex: String?, scanOrder: ScanOrder, estimatedCost: Double, estimatedRows: Int) {
        self.useIndex = useIndex
        self.scanOrder = scanOrder
        self.estimatedCost = estimatedCost
        self.estimatedRows = estimatedRows
    }
}

/// Optimized query plan (uses QueryPlan from QueryOptimizer)
public typealias OptimizedQueryPlan = QueryPlan

/// Cost-based query optimizer
public class QueryOptimizer {
    
    /// Extract filter fields from query filters
    /// Uses the tracked filterFields from QueryBuilder if available, otherwise falls back to heuristic
    private static func extractFilterFields(from query: QueryBuilder, collection: DynamicCollection) -> Set<String> {
        // Use tracked filter fields from QueryBuilder (most accurate)
        if !query.filterFields.isEmpty {
            return query.filterFields
        }
        
        // Fallback: Try to infer fields from index structure (heuristic)
        var filterFields: Set<String> = []
        if !query.filters.isEmpty && !collection.secondaryIndexes.isEmpty {
            // Extract field names from index keys
            for indexName in collection.secondaryIndexes.keys {
                let fields = indexName.components(separatedBy: "+")
                filterFields.formUnion(fields)
            }
        }
        
        return filterFields
    }
    
    /// Calculate index selectivity (how many records match)
    /// For equality queries, assumes uniform distribution: ~1/uniqueKeys
    /// Uses heuristic: if index has many unique keys relative to records, assume low selectivity (equality)
    /// Otherwise, assume higher selectivity (range queries or low cardinality)
    private static func estimateSelectivity(
        indexName: String,
        collection: DynamicCollection,
        totalRecords: Int
    ) -> Double {
        let index = collection.secondaryIndexes[indexName]
        let uniqueKeys = index?.count ?? 0
        
        if uniqueKeys == 0 || totalRecords == 0 {
            return 1.0  // Full scan
        }
        
        // Heuristic: if uniqueKeys is close to totalRecords, it's likely a unique/near-unique index
        // For such indexes, equality queries have very low selectivity: ~1/uniqueKeys
        let uniquenessRatio = Double(uniqueKeys) / Double(totalRecords)
        
        if uniquenessRatio > 0.5 {
            // High uniqueness: assume equality query with low selectivity
            // Selectivity = 1/uniqueKeys (each unique value appears approximately once)
            let selectivity = 1.0 / Double(uniqueKeys)
            return max(0.001, min(0.1, selectivity))  // Clamp between 0.1% and 10%
        } else {
            // Lower uniqueness: could be range query or low-cardinality field
            // For equality on low-cardinality: still use 1/uniqueKeys
            // For range queries, we'd want higher selectivity, but we can't detect that
            // So we use a conservative estimate: assume some values have duplicates
            // Average records per key = totalRecords/uniqueKeys
            // For equality: selectivity = avgRecordsPerKey / totalRecords = 1/uniqueKeys
            let selectivity = 1.0 / Double(uniqueKeys)
            // But allow higher selectivity for very low cardinality (e.g., boolean fields)
            return max(0.01, min(0.5, selectivity))  // Clamp between 1% and 50%
        }
    }
    
    /// Optimize a query and return execution plan
    static func optimize(
        query: QueryBuilder,
        collection: DynamicCollection,
        estimatedRecordCount: Int
    ) -> OptimizedQueryPlan {
        
        // Analyze query to determine best plan
        let filters = query.filters
        let hasIndexes = !collection.secondaryIndexes.isEmpty
        let hasLimit = query.limitValue != nil
        let limitValue = query.limitValue ?? estimatedRecordCount
        
        // Honor forced index hints first
        let indexHints = query.getIndexHints()
        if query.shouldForceIndexSelection, let hint = indexHints.first {
            // User explicitly forced an index - use it unconditionally
            let indexName = hint.indexName
            if collection.secondaryIndexes[indexName] != nil {
                BlazeLogger.debug("🔍 [OPTIMIZER] FORCE INDEX '\(indexName)' honored")
                let selectivity = estimateSelectivity(
                    indexName: indexName,
                    collection: collection,
                    totalRecords: estimatedRecordCount
                )
                return QueryPlan(
                    useIndex: indexName,
                    scanOrder: .index,
                    estimatedCost: 0.0,  // Force always wins
                    estimatedRows: Int(Double(estimatedRecordCount) * selectivity)
                )
            } else {
                BlazeLogger.warn("⚠️ [OPTIMIZER] FORCE INDEX '\(indexName)' not found, falling back to cost-based selection")
            }
        }
        
        // Check if any filter can use an index
        var bestIndex: String? = nil
        var bestIndexCost: Double = Double.infinity
        
        // Apply index hints as preference (but don't force)
        if !indexHints.isEmpty {
            for hint in indexHints {
                if collection.secondaryIndexes[hint.indexName] != nil {
                    // Give hinted indexes a cost advantage (50% discount)
                    let selectivity = estimateSelectivity(
                        indexName: hint.indexName,
                        collection: collection,
                        totalRecords: estimatedRecordCount
                    )
                    let resultCount = Double(estimatedRecordCount) * selectivity
                    let baseCost = log2(Double(estimatedRecordCount)) + resultCount
                    let hintedCost = baseCost * 0.5  // 50% discount for hinted indexes
                    
                    if hintedCost < bestIndexCost {
                        bestIndexCost = hintedCost
                        bestIndex = hint.indexName
                        BlazeLogger.debug("🔍 [OPTIMIZER] USE INDEX hint '\(hint.indexName)' applied with cost \(hintedCost)")
                    }
                }
            }
        }
        
        if hasIndexes {
            let filterFields = extractFilterFields(from: query, collection: collection)
            BlazeLogger.debug("🔍 [OPTIMIZER] Filter fields: \(filterFields), Available indexes: \(collection.secondaryIndexes.keys)")
            
            for (indexName, indexData) in collection.secondaryIndexes {
                let indexFields = indexName.components(separatedBy: "+")
                let uniqueKeys = indexData.count
                
                // Check if any filter fields match index fields
                let matches = !filterFields.isDisjoint(with: Set(indexFields))
                BlazeLogger.debug("🔍 [OPTIMIZER] Index '\(indexName)': fields=\(indexFields), uniqueKeys=\(uniqueKeys), matches=\(matches)")
                
                if matches {
                    // Calculate index scan cost
                    // Index lookup: O(log n) for B-tree traversal
                    // Result retrieval: O(m) where m = selectivity * n
                    let selectivity = estimateSelectivity(
                        indexName: indexName,
                        collection: collection,
                        totalRecords: estimatedRecordCount
                    )
                    let resultCount = Double(estimatedRecordCount) * selectivity
                    
                    // Index cost: log(n) for lookup + m for results
                    let indexCost = log2(Double(estimatedRecordCount)) + resultCount
                    
                    // Apply limit discount (if limit is small relative to resultCount, index is more beneficial)
                    // If limit is smaller than expected results, we only pay for limit items
                    // If limit is larger, we still pay for all results (limit doesn't help)
                    let adjustedCost: Double
                    if hasLimit && Double(limitValue) < resultCount {
                        // Limit is smaller than expected results - only pay for limit items
                        adjustedCost = log2(Double(estimatedRecordCount)) + Double(limitValue)
                    } else {
                        // No limit or limit is larger - pay full cost
                        adjustedCost = indexCost
                    }
                    
                    BlazeLogger.debug("🔍 [OPTIMIZER] Index '\(indexName)': selectivity=\(selectivity), resultCount=\(resultCount), indexCost=\(indexCost), adjustedCost=\(adjustedCost)")
                    
                    if adjustedCost < bestIndexCost {
                        bestIndexCost = adjustedCost
                        bestIndex = indexName
                        BlazeLogger.debug("🔍 [OPTIMIZER] New best index: '\(indexName)' with cost \(adjustedCost)")
                    }
                }
            }
        }
        
        // Calculate sequential scan cost
        // Sequential scan: O(n) to read all records
        // With limit: O(min(n, limit))
        let sequentialCost = hasLimit ? Double(min(estimatedRecordCount, limitValue)) : Double(estimatedRecordCount)
        
        BlazeLogger.debug("🔍 [OPTIMIZER] Sequential cost: \(sequentialCost), Best index: \(bestIndex ?? "none"), Best index cost: \(bestIndexCost), Threshold: \(sequentialCost * 0.8)")
        
        // Determine best plan
        if let index = bestIndex, bestIndexCost < sequentialCost * 0.8 {
            // Use index (only if 20% better than sequential)
            let selectivity = estimateSelectivity(
                indexName: index,
                collection: collection,
                totalRecords: estimatedRecordCount
            )
            return QueryPlan(
                useIndex: index,
                scanOrder: .index,
                estimatedCost: bestIndexCost,
                estimatedRows: Int(Double(estimatedRecordCount) * selectivity)
            )
        } else if estimatedRecordCount > 1000 && !hasLimit {
            // Use parallel scan for large datasets without limit
            return QueryPlan(
                useIndex: nil,
                scanOrder: .parallel,
                estimatedCost: Double(estimatedRecordCount) / 8.0,  // Divide by cores
                estimatedRows: estimatedRecordCount
            )
        } else {
            // Sequential scan
            // Estimate rows: if we have filters, assume moderate selectivity (30-50% for range queries)
            // If no filters, return all rows (or limit if specified)
            let estimatedRows: Int
            if !filters.isEmpty {
                // Heuristic: range queries typically match 30-50% of records
                // Use 40% as a conservative estimate for range queries
                let selectivity = 0.4
                estimatedRows = hasLimit ? min(limitValue, Int(Double(estimatedRecordCount) * selectivity)) : Int(Double(estimatedRecordCount) * selectivity)
            } else {
                // No filters: return all rows (or limit)
                estimatedRows = hasLimit ? limitValue : estimatedRecordCount
            }
            
            return QueryPlan(
                useIndex: nil,
                scanOrder: .sequential,
                estimatedCost: sequentialCost,
                estimatedRows: estimatedRows
            )
        }
    }
    
    /// Get estimated record count (would use statistics in production)
    static func estimateRecordCount(collection: DynamicCollection) -> Int {
        return collection.indexMap.count
    }
}

/// Extension to QueryBuilder for optimizer integration
extension QueryBuilder {
    
    /// Get optimized query plan
    func getOptimizedPlan(collection: DynamicCollection) -> OptimizedQueryPlan {
        let estimatedCount = QueryOptimizer.estimateRecordCount(collection: collection)
        return QueryOptimizer.optimize(
            query: self,
            collection: collection,
            estimatedRecordCount: estimatedCount
        )
    }
    
    /// Execute query using optimized plan
    func executeWithOptimizer() throws -> QueryResult {
        guard let collection = collection else {
            throw BlazeDBError.invalidData(reason: "Query builder's collection has been deallocated. Recreate the query from a live database.")
        }
        
        let plan = getOptimizedPlan(collection: collection)
        
        // Execute based on plan
        switch plan.scanOrder {
        case .index:
            // Use index-based execution
            if let indexName = plan.useIndex {
                return try executeWithIndex(indexName)
            }
            return try execute()
        case .parallel:
            // Use parallel execution (if available)
            // Note: executeParallel is async, so we'd need async version
            // For now, fall back to standard execution
            return try execute()
        case .sequential:
            // Use standard execution
            return try execute()
        }
    }
    
    /// Execute query using specific index
    private func executeWithIndex(_ indexName: String) throws -> QueryResult {
        guard let collection = collection else {
            throw BlazeDBError.invalidData(reason: "Query builder's collection has been deallocated. Recreate the query from a live database.")
        }
        
        let startTime = Date()
        
        // Parse index fields (compound indexes use + separator)
        let indexFields = indexName.components(separatedBy: "+")
        
        // Simple case: single field index with equality filter
        if indexFields.count == 1, let field = indexFields.first {
            // Find equality filter for this field
            if let eqDescriptor = filterDescriptors.first(where: { $0.field == field && $0.operation == "eq" }),
               let hashableValue = eqDescriptor.hashableValue {
                
                BlazeLogger.info("📊 [INDEX] Using index '\(indexName)' for field '\(field)'")
                
                // Step 1: Fetch records using index
                var records = try collection.fetch(byIndexedField: field, value: hashableValue)
                BlazeLogger.debug("📊 [INDEX] Index lookup returned \(records.count) records")
                
                // Step 2: Apply remaining filters (skip the one we used for index lookup)
                let remainingFilters: [(BlazeDataRecord) -> Bool] = filters.enumerated().compactMap { (index, filter) in
                    // Skip filter that was used for index lookup
                    if index < filterDescriptors.count {
                        let desc = filterDescriptors[index]
                        if desc.field == field && desc.operation == "eq" {
                            return nil
                        }
                    }
                    return filter
                }
                
                if !remainingFilters.isEmpty {
                    let combinedFilter: (BlazeDataRecord) -> Bool = { record in
                        for filter in remainingFilters {
                            if !filter(record) { return false }
                        }
                        return true
                    }
                    let beforeFilter = records.count
                    records = records.filter(combinedFilter)
                    BlazeLogger.debug("📊 [INDEX] After remaining filters: \(beforeFilter) → \(records.count) records")
                }
                
                // Step 3: Apply sorts
                if !sortOperations.isEmpty {
                    records = applySorts(to: records)
                }
                
                // Step 4: Apply offset
                if offsetValue > 0 {
                    records = Array(records.dropFirst(Swift.min(offsetValue, records.count)))
                }
                
                // Step 5: Apply limit
                if let limit = limitValue {
                    records = Array(records.prefix(Swift.max(0, limit)))
                }
                
                let duration = Date().timeIntervalSince(startTime)
                BlazeLogger.info("📊 [INDEX] Query complete: \(records.count) results in \(String(format: "%.2f", duration * 1000))ms (used index '\(indexName)')")
                
                return .records(records)
            }
        }
        
        // Compound index case: multiple fields
        if indexFields.count > 1 {
            // Find equality filters for all index fields
            var fieldValues: [(String, AnyHashable)] = []
            
            for field in indexFields {
                if let eqDescriptor = filterDescriptors.first(where: { $0.field == field && $0.operation == "eq" }),
                   let hashableValue = eqDescriptor.hashableValue {
                    fieldValues.append((field, hashableValue))
                }
            }
            
            // Only use compound index if we have values for ALL fields
            if fieldValues.count == indexFields.count {
                BlazeLogger.info("📊 [INDEX] Using compound index '\(indexName)'")
                
                let values = fieldValues.map { $0.1 }
                var records = try collection.fetch(byIndexedFields: indexFields, values: values)
                BlazeLogger.debug("📊 [INDEX] Compound index lookup returned \(records.count) records")
                
                // Apply remaining filters (skip the ones we used for index)
                let usedFields = Set(indexFields)
                let remainingFilters: [(BlazeDataRecord) -> Bool] = filters.enumerated().compactMap { (index, filter) in
                    if index < filterDescriptors.count {
                        let desc = filterDescriptors[index]
                        if usedFields.contains(desc.field) && desc.operation == "eq" {
                            return nil
                        }
                    }
                    return filter
                }
                
                if !remainingFilters.isEmpty {
                    let combinedFilter: (BlazeDataRecord) -> Bool = { record in
                        for filter in remainingFilters {
                            if !filter(record) { return false }
                        }
                        return true
                    }
                    records = records.filter(combinedFilter)
                }
                
                // Apply sorts, offset, limit
                if !sortOperations.isEmpty {
                    records = applySorts(to: records)
                }
                if offsetValue > 0 {
                    records = Array(records.dropFirst(Swift.min(offsetValue, records.count)))
                }
                if let limit = limitValue {
                    records = Array(records.prefix(Swift.max(0, limit)))
                }
                
                let duration = Date().timeIntervalSince(startTime)
                BlazeLogger.info("📊 [INDEX] Query complete: \(records.count) results in \(String(format: "%.2f", duration * 1000))ms (used compound index)")
                
                return .records(records)
            }
        }
        
        // Fall back to standard execution if index can't be used
        BlazeLogger.debug("📊 [INDEX] Falling back to standard execution for index '\(indexName)' (no matching equality filters)")
        return try execute()
    }
    
    /// Execute query using index with explicit field/value (for internal use)
    internal func executeWithIndexedLookup(field: String, value: AnyHashable) throws -> QueryResult {
        guard let collection = collection else {
            throw BlazeDBError.invalidData(reason: "Query builder's collection has been deallocated. Recreate the query from a live database.")
        }
        
        let startTime = Date()
        BlazeLogger.info("📊 [INDEX] Executing with indexed lookup on '\(field)'")
        
        // Step 1: Fetch records using index
        var records = try collection.fetch(byIndexedField: field, value: value)
        BlazeLogger.debug("📊 [INDEX] Index lookup returned \(records.count) records")
        
        // Step 2: Apply remaining filters (skip the one we used for index lookup)
        if filters.count > 1 {
            let remainingFilters = filters.enumerated().compactMap { (index, filter) -> ((BlazeDataRecord) -> Bool)? in
                // Skip filter that was used for index lookup
                if index < filterDescriptors.count {
                    let desc = filterDescriptors[index]
                    if desc.field == field && desc.operation == "eq" {
                        return nil
                    }
                }
                return filter
            }
            
            if !remainingFilters.isEmpty {
                let combinedFilter: (BlazeDataRecord) -> Bool = { record in
                    for filter in remainingFilters {
                        if !filter(record) { return false }
                    }
                    return true
                }
                records = records.filter(combinedFilter)
                BlazeLogger.debug("📊 [INDEX] After remaining filters: \(records.count) records")
            }
        }
        
        // Step 3: Apply sorts
        if !sortOperations.isEmpty {
            records = applySorts(to: records)
        }
        
        // Step 4: Apply offset
        if offsetValue > 0 {
            records = Array(records.dropFirst(Swift.min(offsetValue, records.count)))
        }
        
        // Step 5: Apply limit
        if let limit = limitValue {
            records = Array(records.prefix(Swift.max(0, limit)))
        }
        
        let duration = Date().timeIntervalSince(startTime)
        BlazeLogger.info("📊 [INDEX] Query complete: \(records.count) results in \(String(format: "%.2f", duration * 1000))ms (used index)")
        
        return .records(records)
    }
    
    /// Sort records (shared helper)
    private func applySorts(to records: [BlazeDataRecord]) -> [BlazeDataRecord] {
        return records.sorted { (left: BlazeDataRecord, right: BlazeDataRecord) -> Bool in
            for sortOp in sortOperations {
                let leftValue = left.storage[sortOp.field]
                let rightValue = right.storage[sortOp.field]
                
                if leftValue == nil && rightValue == nil { continue }
                if leftValue == nil { return false }
                if rightValue == nil { return true }
                
                if leftValue == rightValue { continue }
                
                let comparison = compareFields(leftValue!, .lessThan, rightValue!)
                return sortOp.descending ? !comparison : comparison
            }
            return false
        }
    }
}

