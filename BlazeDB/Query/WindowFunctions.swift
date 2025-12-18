//
//  WindowFunctions.swift
//  BlazeDB
//
//  Window functions for analytical queries
//  ROW_NUMBER, RANK, DENSE_RANK, LAG, LEAD, SUM OVER, etc.
//
//  Created by Auto on 1/XX/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

// MARK: - Window Function Types

public enum WindowFunction {
    case rowNumber(partitionBy: [String]?, orderBy: [String])
    case rank(partitionBy: [String]?, orderBy: [String])
    case denseRank(partitionBy: [String]?, orderBy: [String])
    case lag(field: String, offset: Int, partitionBy: [String]?, orderBy: [String])
    case lead(field: String, offset: Int, partitionBy: [String]?, orderBy: [String])
    case sumOver(field: String, partitionBy: [String]?, orderBy: [String])
    case avgOver(field: String, partitionBy: [String]?, orderBy: [String])
    case countOver(partitionBy: [String]?, orderBy: [String])
    case minOver(field: String, partitionBy: [String]?, orderBy: [String])
    case maxOver(field: String, partitionBy: [String]?, orderBy: [String])
}

// MARK: - Window Function Result

public struct WindowFunctionResult {
    public let record: BlazeDataRecord
    public let windowValues: [String: BlazeDocumentField]  // Function name -> computed value
    
    public func getWindowValue(_ functionName: String) -> BlazeDocumentField? {
        return windowValues[functionName]
    }
}

// MARK: - QueryBuilder Window Functions Extension

extension QueryBuilder {
    
    /// Add window function to query
    @discardableResult
    public func window(_ function: WindowFunction, as alias: String) -> QueryBuilder {
        windowFunctions.append((function: function, alias: alias))
        return self
    }
    
    /// ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)
    @discardableResult
    public func rowNumber(partitionBy: [String]? = nil, orderBy: [String], as alias: String = "row_number") -> QueryBuilder {
        return window(.rowNumber(partitionBy: partitionBy, orderBy: orderBy), as: alias)
    }
    
    /// RANK() OVER (PARTITION BY ... ORDER BY ...)
    @discardableResult
    public func rank(partitionBy: [String]? = nil, orderBy: [String], as alias: String = "rank") -> QueryBuilder {
        return window(.rank(partitionBy: partitionBy, orderBy: orderBy), as: alias)
    }
    
    /// DENSE_RANK() OVER (PARTITION BY ... ORDER BY ...)
    @discardableResult
    public func denseRank(partitionBy: [String]? = nil, orderBy: [String], as alias: String = "dense_rank") -> QueryBuilder {
        return window(.denseRank(partitionBy: partitionBy, orderBy: orderBy), as: alias)
    }
    
    /// LAG(field, offset) OVER (PARTITION BY ... ORDER BY ...)
    @discardableResult
    public func lag(_ field: String, offset: Int = 1, partitionBy: [String]? = nil, orderBy: [String], as alias: String? = nil) -> QueryBuilder {
        let aliasName = alias ?? "lag_\(field)"
        return window(.lag(field: field, offset: offset, partitionBy: partitionBy, orderBy: orderBy), as: aliasName)
    }
    
    /// LEAD(field, offset) OVER (PARTITION BY ... ORDER BY ...)
    @discardableResult
    public func lead(_ field: String, offset: Int = 1, partitionBy: [String]? = nil, orderBy: [String], as alias: String? = nil) -> QueryBuilder {
        let aliasName = alias ?? "lead_\(field)"
        return window(.lead(field: field, offset: offset, partitionBy: partitionBy, orderBy: orderBy), as: aliasName)
    }
    
    /// SUM(field) OVER (PARTITION BY ... ORDER BY ...)
    @discardableResult
    public func sumOver(_ field: String, partitionBy: [String]? = nil, orderBy: [String], as alias: String? = nil) -> QueryBuilder {
        let aliasName = alias ?? "sum_\(field)"
        return window(.sumOver(field: field, partitionBy: partitionBy, orderBy: orderBy), as: aliasName)
    }
    
    /// AVG(field) OVER (PARTITION BY ... ORDER BY ...)
    @discardableResult
    public func avgOver(_ field: String, partitionBy: [String]? = nil, orderBy: [String], as alias: String? = nil) -> QueryBuilder {
        let aliasName = alias ?? "avg_\(field)"
        return window(.avgOver(field: field, partitionBy: partitionBy, orderBy: orderBy), as: aliasName)
    }
    
    /// COUNT(*) OVER (PARTITION BY ... ORDER BY ...)
    @discardableResult
    public func countOver(partitionBy: [String]? = nil, orderBy: [String], as alias: String = "count_over") -> QueryBuilder {
        return window(.countOver(partitionBy: partitionBy, orderBy: orderBy), as: alias)
    }
    
    /// MIN(field) OVER (PARTITION BY ... ORDER BY ...)
    @discardableResult
    public func minOver(_ field: String, partitionBy: [String]? = nil, orderBy: [String], as alias: String? = nil) -> QueryBuilder {
        let aliasName = alias ?? "min_\(field)"
        return window(.minOver(field: field, partitionBy: partitionBy, orderBy: orderBy), as: aliasName)
    }
    
    /// MAX(field) OVER (PARTITION BY ... ORDER BY ...)
    @discardableResult
    public func maxOver(_ field: String, partitionBy: [String]? = nil, orderBy: [String], as alias: String? = nil) -> QueryBuilder {
        let aliasName = alias ?? "max_\(field)"
        return window(.maxOver(field: field, partitionBy: partitionBy, orderBy: orderBy), as: aliasName)
    }
    
    /// Execute query with window functions
    public func executeWithWindow() throws -> [WindowFunctionResult] {
        guard collection != nil else {
            throw BlazeDBError.transactionFailed("Collection not available")
        }
        
        // Get base results
        let queryResult = try execute()
        var results = try queryResult.records
        
        // Apply window functions
        guard !windowFunctions.isEmpty else {
            // No window functions, return results as-is
            return results.map { WindowFunctionResult(record: $0, windowValues: [:]) }
        }
        
        // Sort results for window function processing
        // Use orderBy from first window function if no explicit sort
        if sortOperations.isEmpty && !windowFunctions.isEmpty {
            // Extract orderBy from first window function
            let firstWindow = windowFunctions[0].function
            let orderByFields = getOrderByFields(from: firstWindow)
            if !orderByFields.isEmpty {
                results = sortRecords(results, by: orderByFields)
            }
        } else if !sortOperations.isEmpty {
            // Use explicit sort operations
            results = sortRecords(results, by: sortOperations.map { $0.descending ? "-\($0.field)" : $0.field })
        }
        
        // Apply each window function
        var windowResults: [WindowFunctionResult] = []
        
        for result in results {
            var windowValues: [String: BlazeDocumentField] = [:]
            
            for (function, alias) in windowFunctions {
                let value = try computeWindowFunction(function, for: result, in: results)
                windowValues[alias] = value
            }
            
            windowResults.append(WindowFunctionResult(record: result, windowValues: windowValues))
        }
        
        return windowResults
    }
    
    // MARK: - Internal Window Function Computation
    
    private func computeWindowFunction(_ function: WindowFunction, for record: BlazeDataRecord, in allRecords: [BlazeDataRecord]) throws -> BlazeDocumentField {
        switch function {
        case .rowNumber(let partitionBy, let orderBy):
            return .int(computeRowNumber(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy))
            
        case .rank(let partitionBy, let orderBy):
            return .int(computeRank(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy))
            
        case .denseRank(let partitionBy, let orderBy):
            return .int(computeDenseRank(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy))
            
        case .lag(let field, let offset, let partitionBy, let orderBy):
            return computeLag(for: record, field: field, offset: offset, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
            
        case .lead(let field, let offset, let partitionBy, let orderBy):
            return computeLead(for: record, field: field, offset: offset, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
            
        case .sumOver(let field, let partitionBy, let orderBy):
            return .double(computeSumOver(for: record, field: field, in: allRecords, partitionBy: partitionBy, orderBy: orderBy))
            
        case .avgOver(let field, let partitionBy, let orderBy):
            return .double(computeAvgOver(for: record, field: field, in: allRecords, partitionBy: partitionBy, orderBy: orderBy))
            
        case .countOver(let partitionBy, let orderBy):
            return .int(computeCountOver(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy))
            
        case .minOver(let field, let partitionBy, let orderBy):
            return computeMinOver(for: record, field: field, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
            
        case .maxOver(let field, let partitionBy, let orderBy):
            return computeMaxOver(for: record, field: field, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
        }
    }
    
    private func computeRowNumber(for record: BlazeDataRecord, in allRecords: [BlazeDataRecord], partitionBy: [String]?, orderBy: [String]) -> Int {
        let partition = getPartition(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
        guard let recordId = record.storage["id"]?.uuidValue,
              let index = partition.firstIndex(where: { $0.storage["id"]?.uuidValue == recordId }) else {
            return 1
        }
        return index + 1
    }
    
    private func computeRank(for record: BlazeDataRecord, in allRecords: [BlazeDataRecord], partitionBy: [String]?, orderBy: [String]) -> Int {
        let partition = getPartition(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
        let sortedPartition = sortRecords(partition, by: orderBy)
        
        guard let recordId = record.storage["id"]?.uuidValue,
              let recordIndex = sortedPartition.firstIndex(where: { $0.storage["id"]?.uuidValue == recordId }) else {
            return 1
        }
        
        // Count how many records have same order values before this one
        var rank = 1
        for i in 0..<recordIndex {
            if !recordsEqual(sortedPartition[i], sortedPartition[recordIndex], by: orderBy) {
                rank = i + 1
            }
        }
        
        return rank
    }
    
    private func computeDenseRank(for record: BlazeDataRecord, in allRecords: [BlazeDataRecord], partitionBy: [String]?, orderBy: [String]) -> Int {
        let partition = getPartition(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
        let sortedPartition = sortRecords(partition, by: orderBy)
        
        guard let recordId = record.storage["id"]?.uuidValue,
              let recordIndex = sortedPartition.firstIndex(where: { $0.storage["id"]?.uuidValue == recordId }) else {
            return 1
        }
        
        // Count distinct order value groups before this one
        var denseRank = 1
        var seenValues: Set<String> = []
        
        for i in 0..<recordIndex {
            let valueKey = getOrderValueKey(sortedPartition[i], by: orderBy)
            if !seenValues.contains(valueKey) {
                seenValues.insert(valueKey)
                if !recordsEqual(sortedPartition[i], sortedPartition[recordIndex], by: orderBy) {
                    denseRank += 1
                }
            }
        }
        
        return denseRank
    }
    
    private func computeLag(for record: BlazeDataRecord, field: String, offset: Int, in allRecords: [BlazeDataRecord], partitionBy: [String]?, orderBy: [String]) -> BlazeDocumentField {
        let partition = getPartition(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
        let sortedPartition = sortRecords(partition, by: orderBy)
        
        guard let recordId = record.storage["id"]?.uuidValue,
              let recordIndex = sortedPartition.firstIndex(where: { $0.storage["id"]?.uuidValue == recordId }),
              recordIndex >= offset else {
            return .data(Data())  // NULL equivalent
        }
        
        let lagRecord = sortedPartition[recordIndex - offset]
        return lagRecord.storage[field] ?? .data(Data())
    }
    
    private func computeLead(for record: BlazeDataRecord, field: String, offset: Int, in allRecords: [BlazeDataRecord], partitionBy: [String]?, orderBy: [String]) -> BlazeDocumentField {
        let partition = getPartition(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
        let sortedPartition = sortRecords(partition, by: orderBy)
        
        guard let recordId = record.storage["id"]?.uuidValue,
              let recordIndex = sortedPartition.firstIndex(where: { $0.storage["id"]?.uuidValue == recordId }),
              recordIndex + offset < sortedPartition.count else {
            return .data(Data())  // NULL equivalent
        }
        
        let leadRecord = sortedPartition[recordIndex + offset]
        return leadRecord.storage[field] ?? .data(Data())
    }
    
    private func computeSumOver(for record: BlazeDataRecord, field: String, in allRecords: [BlazeDataRecord], partitionBy: [String]?, orderBy: [String]) -> Double {
        let partition = getPartition(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
        let sortedPartition = sortRecords(partition, by: orderBy)
        
        guard let recordId = record.storage["id"]?.uuidValue,
              let recordIndex = sortedPartition.firstIndex(where: { $0.storage["id"]?.uuidValue == recordId }) else {
            return 0
        }
        
        // Sum all values up to and including current record
        var sum: Double = 0
        for i in 0...recordIndex {
            if let value = sortedPartition[i].storage[field] {
                switch value {
                case .int(let v): sum += Double(v)
                case .double(let v): sum += v
                default: break
                }
            }
        }
        
        return sum
    }
    
    private func computeAvgOver(for record: BlazeDataRecord, field: String, in allRecords: [BlazeDataRecord], partitionBy: [String]?, orderBy: [String]) -> Double {
        let partition = getPartition(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
        let sortedPartition = sortRecords(partition, by: orderBy)
        
        guard let recordId = record.storage["id"]?.uuidValue,
              let recordIndex = sortedPartition.firstIndex(where: { $0.storage["id"]?.uuidValue == recordId }) else {
            return 0
        }
        
        // Average of all values up to and including current record
        var sum: Double = 0
        var count: Int = 0
        
        for i in 0...recordIndex {
            if let value = sortedPartition[i].storage[field] {
                switch value {
                case .int(let v):
                    sum += Double(v)
                    count += 1
                case .double(let v):
                    sum += v
                    count += 1
                default: break
                }
            }
        }
        
        return count > 0 ? sum / Double(count) : 0
    }
    
    private func computeCountOver(for record: BlazeDataRecord, in allRecords: [BlazeDataRecord], partitionBy: [String]?, orderBy: [String]) -> Int {
        let partition = getPartition(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
        let sortedPartition = sortRecords(partition, by: orderBy)
        
        guard let recordId = record.storage["id"]?.uuidValue,
              let recordIndex = sortedPartition.firstIndex(where: { $0.storage["id"]?.uuidValue == recordId }) else {
            return 0
        }
        
        // Count records up to and including current
        return recordIndex + 1
    }
    
    private func computeMinOver(for record: BlazeDataRecord, field: String, in allRecords: [BlazeDataRecord], partitionBy: [String]?, orderBy: [String]) -> BlazeDocumentField {
        let partition = getPartition(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
        let sortedPartition = sortRecords(partition, by: orderBy)
        
        guard let recordId = record.storage["id"]?.uuidValue,
              let recordIndex = sortedPartition.firstIndex(where: { $0.storage["id"]?.uuidValue == recordId }) else {
            return .data(Data())
        }
        
        // Find minimum value up to and including current record
        var minValue: BlazeDocumentField?
        
        for i in 0...recordIndex {
            if let value = sortedPartition[i].storage[field] {
                if minValue == nil {
                    minValue = value
                } else if compareFields(value, minValue!, isLessThan: true) {
                    minValue = value
                }
            }
        }
        
        return minValue ?? .data(Data())
    }
    
    private func computeMaxOver(for record: BlazeDataRecord, field: String, in allRecords: [BlazeDataRecord], partitionBy: [String]?, orderBy: [String]) -> BlazeDocumentField {
        let partition = getPartition(for: record, in: allRecords, partitionBy: partitionBy, orderBy: orderBy)
        let sortedPartition = sortRecords(partition, by: orderBy)
        
        guard let recordId = record.storage["id"]?.uuidValue,
              let recordIndex = sortedPartition.firstIndex(where: { $0.storage["id"]?.uuidValue == recordId }) else {
            return .data(Data())
        }
        
        // Find maximum value up to and including current record
        var maxValue: BlazeDocumentField?
        
        for i in 0...recordIndex {
            if let value = sortedPartition[i].storage[field] {
                if maxValue == nil {
                    maxValue = value
                } else if compareFields(value, maxValue!, isLessThan: false) {
                    maxValue = value
                }
            }
        }
        
        return maxValue ?? .data(Data())
    }
    
    // MARK: - Helper Methods
    
    private func getOrderByFields(from function: WindowFunction) -> [String] {
        switch function {
        case .rowNumber(_, let orderBy),
             .rank(_, let orderBy),
             .denseRank(_, let orderBy),
             .lag(_, _, _, let orderBy),
             .lead(_, _, _, let orderBy),
             .sumOver(_, _, let orderBy),
             .avgOver(_, _, let orderBy),
             .countOver(_, let orderBy),
             .minOver(_, _, let orderBy),
             .maxOver(_, _, let orderBy):
            return orderBy
        }
    }
    
    private func getPartition(for record: BlazeDataRecord, in allRecords: [BlazeDataRecord], partitionBy: [String]?, orderBy: [String]) -> [BlazeDataRecord] {
        guard let partitionBy = partitionBy, !partitionBy.isEmpty else {
            return allRecords
        }
        
        // Get partition key for this record
        let recordPartitionKey = getPartitionKey(record, by: partitionBy)
        
        // Filter records with same partition key
        return allRecords.filter { getPartitionKey($0, by: partitionBy) == recordPartitionKey }
    }
    
    private func getPartitionKey(_ record: BlazeDataRecord, by fields: [String]) -> String {
        return fields.compactMap { field in
            record.storage[field]?.serializedString()
        }.joined(separator: "|")
    }
    
    private func sortRecords(_ records: [BlazeDataRecord], by fields: [String]) -> [BlazeDataRecord] {
        return records.sorted { r1, r2 in
            for field in fields {
                let descending = field.hasPrefix("-")
                let actualField = descending ? String(field.dropFirst()) : field
                
                guard let v1 = r1.storage[actualField],
                      let v2 = r2.storage[actualField] else {
                    continue
                }
                
                let comparison = compareFields(v1, v2, isLessThan: true)
                if comparison {
                    return !descending
                } else if compareFields(v2, v1, isLessThan: true) {
                    return descending
                }
            }
            return false
        }
    }
    
    private func recordsEqual(_ r1: BlazeDataRecord, _ r2: BlazeDataRecord, by fields: [String]) -> Bool {
        for field in fields {
            let actualField = field.hasPrefix("-") ? String(field.dropFirst()) : field
            guard let v1 = r1.storage[actualField],
                  let v2 = r2.storage[actualField] else {
                return false
            }
            if v1 != v2 {
                return false
            }
        }
        return true
    }
    
    private func getOrderValueKey(_ record: BlazeDataRecord, by fields: [String]) -> String {
        return fields.compactMap { field in
            let actualField = field.hasPrefix("-") ? String(field.dropFirst()) : field
            guard let value = record.storage[actualField] else { return nil }
            // Convert to string for comparison key
            switch value {
            case .string(let v): return v
            case .int(let v): return String(v)
            case .double(let v): return String(v)
            case .date(let v): return ISO8601DateFormatter().string(from: v)
            case .uuid(let v): return v.uuidString
            case .bool(let v): return v ? "true" : "false"
            default: return String(describing: value)
            }
        }.joined(separator: "|")
    }
    
    private func compareFields(_ f1: BlazeDocumentField, _ f2: BlazeDocumentField, isLessThan: Bool) -> Bool {
        switch (f1, f2) {
        case (.int(let v1), .int(let v2)):
            return isLessThan ? v1 < v2 : v1 > v2
        case (.double(let v1), .double(let v2)):
            return isLessThan ? v1 < v2 : v1 > v2
        case (.string(let v1), .string(let v2)):
            return isLessThan ? v1 < v2 : v1 > v2
        case (.date(let v1), .date(let v2)):
            return isLessThan ? v1 < v2 : v1 > v2
        default:
            return false
        }
    }
}

#endif // !BLAZEDB_LINUX_CORE

// Note: windowFunctions property is defined in QueryBuilder.swift (gated)

