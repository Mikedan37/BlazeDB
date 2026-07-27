//
//  QueryExecuting.swift
//  BlazeDB
//
//  Internal execution boundary for standard (scan → filter → sort → offset → limit) queries.
//  Public QueryBuilder APIs remain unchanged; this seam exists so future changes have one place
//  to route through without reaching into storage details from every call site.
//

import Foundation

/// Snapshot of a standard query ready for execution.
/// Join / aggregation / planner paths are not represented here yet.
internal struct QueryRequest {
    let loadRecords: () throws -> [BlazeDataRecord]
    let filters: [(BlazeDataRecord) -> Bool]
    let sortOperations: [SortOperation]
    let offset: Int
    let limit: Int?
}

/// Internal boundary for standard query execution.
internal protocol QueryExecuting {
    func execute(_ request: QueryRequest) throws -> QueryResult
}

/// Current scan/filter/sort/limit behavior, moved behind QueryExecuting.
internal struct LegacyQueryExecutor: QueryExecuting {
    func execute(_ request: QueryRequest) throws -> QueryResult {
        let startTime = Date()
        BlazeLogger.info(
            "Executing query with \(request.filters.count) filters, \(request.sortOperations.count) sorts, limit: \(request.limit.map { String($0) } ?? "none"), offset: \(request.offset)"
        )

        var records = try request.loadRecords()
        BlazeLogger.debug("Loaded \(records.count) records from storage")

        let preFilterCount = records.count
        if !request.filters.isEmpty {
            let combinedFilter: (BlazeDataRecord) -> Bool = { record in
                for filter in request.filters {
                    if !filter(record) { return false }
                }
                return true
            }
            records = records.filter(combinedFilter)

            if BlazeLogger.level >= .trace {
                var tempRecords = records
                for (index, filter) in request.filters.enumerated() {
                    let beforeCount = tempRecords.count
                    tempRecords = tempRecords.filter(filter)
                    let filtered = beforeCount - tempRecords.count
                    BlazeLogger.trace("Filter \(index + 1): removed \(filtered) records (\(tempRecords.count) remaining)")
                }
            }

            if preFilterCount > records.count {
                BlazeLogger.debug(
                    "Filters reduced \(preFilterCount) → \(records.count) records (\(String(format: "%.1f", Double(records.count) / Double(preFilterCount) * 100))% retained)"
                )
            }
        }

        if !request.sortOperations.isEmpty {
            BlazeLogger.debug("Sorting by \(request.sortOperations.count) field(s)")
            records = Self.applySorts(request.sortOperations, to: records)
        }

        if request.offset > 0 {
            let beforeOffset = records.count
            records = Array(records.dropFirst(Swift.min(request.offset, records.count)))
            BlazeLogger.debug("Offset: skipped \(beforeOffset - records.count) records (\(records.count) remaining)")
        }

        if let limit = request.limit {
            let beforeLimit = records.count
            records = Array(records.prefix(Swift.max(0, limit)))
            if beforeLimit > records.count {
                BlazeLogger.debug("Limit: reduced \(beforeLimit) → \(records.count) records")
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        BlazeLogger.info("Query complete: \(records.count) results in \(String(format: "%.2f", duration * 1000))ms")
        return .records(records)
    }

    private static func applySorts(_ sortOperations: [SortOperation], to records: [BlazeDataRecord]) -> [BlazeDataRecord] {
        records.sorted { (left: BlazeDataRecord, right: BlazeDataRecord) -> Bool in
            for sortOp in sortOperations {
                let leftValue = left.storage[sortOp.field]
                let rightValue = right.storage[sortOp.field]

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
}

extension QueryBuilder {
    /// Injectable standard-path executor (tests may wrap; production uses LegacyQueryExecutor).
    nonisolated(unsafe) internal static var standardQueryExecutor: any QueryExecuting = LegacyQueryExecutor()
}
