//
//  MetricEvent.swift
//  BlazeDB
//
//  Telemetry metric event (basic MVP)
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

/// A single telemetry event tracking a database operation
public struct MetricEvent: Codable, Identifiable {
    // TIER 1: Core metrics (always tracked)
    public let id: UUID
    public let timestamp: Date
    public let operation: String          // "insert", "fetch", "query", "update", "delete"
    public let duration: Double           // Milliseconds
    public let success: Bool
    public let collectionName: String
    
    // TIER 2: Optional details
    public let recordCount: Int?          // How many records affected
    public let errorMessage: String?      // If failed
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        operation: String,
        duration: Double,
        success: Bool,
        collectionName: String,
        recordCount: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.operation = operation
        self.duration = duration
        self.success = success
        self.collectionName = collectionName
        self.recordCount = recordCount
        self.errorMessage = errorMessage
    }
    
    /// Convert to BlazeDataRecord for storage
    func toRecord() -> BlazeDataRecord {
        var fields: [String: BlazeDocumentField] = [
            "id": .uuid(id),
            "timestamp": .date(timestamp),
            "operation": .string(operation),
            "duration": .double(duration),
            "success": .bool(success),
            "collectionName": .string(collectionName)
        ]
        
        if let recordCount = recordCount {
            fields["recordCount"] = .int(recordCount)
        }
        
        if let errorMessage = errorMessage {
            fields["errorMessage"] = .string(errorMessage)
        }
        
        return BlazeDataRecord(fields)
    }
    
    /// Create from BlazeDataRecord
    static func from(record: BlazeDataRecord) throws -> MetricEvent {
        guard let id = record.storage["id"]?.uuidValue,
              let timestamp = record.storage["timestamp"]?.dateValue,
              let operation = record.storage["operation"]?.stringValue,
              let duration = record.storage["duration"]?.doubleValue,
              let success = record.storage["success"]?.boolValue,
              let collectionName = record.storage["collectionName"]?.stringValue else {
            throw BlazeDBError.invalidData(reason: "Missing required fields in metric event record")
        }
        
        let recordCount = record.storage["recordCount"]?.intValue
        let errorMessage = record.storage["errorMessage"]?.stringValue
        
        return MetricEvent(
            id: id,
            timestamp: timestamp,
            operation: operation,
            duration: duration,
            success: success,
            collectionName: collectionName,
            recordCount: recordCount,
            errorMessage: errorMessage
        )
    }
}

// MARK: - Telemetry Summary

/// Summary of telemetry metrics
public struct TelemetrySummary {
    public let totalOperations: Int
    public let successRate: Double
    public let avgDuration: Double
    public let p50Duration: Double
    public let p95Duration: Double
    public let p99Duration: Double
    public let errorCount: Int
    public let operationBreakdown: [String: Int]
    public let recentOperations: [MetricEvent]
    
    public var description: String {
        var desc = """
        📊 BlazeDB Telemetry Summary
        \(String(repeating: "━", count: 50))
        Total Operations: \(totalOperations)
        Success Rate: \(String(format: "%.1f", successRate))%
        
        Performance:
          • Average: \(String(format: "%.2f", avgDuration))ms \(avgDuration < 10 ? "✅" : avgDuration < 50 ? "⚠️" : "🚨")
          • p50 (median): \(String(format: "%.2f", p50Duration))ms
          • p95: \(String(format: "%.2f", p95Duration))ms
          • p99: \(String(format: "%.2f", p99Duration))ms
        
        Operations:
        """
        
        let total = Double(totalOperations)
        for (op, count) in operationBreakdown.sorted(by: { $0.key < $1.key }) {
            let pct = (Double(count) / total) * 100
            desc += "\n  • \(op): \(count) (\(String(format: "%.0f", pct))%)"
        }
        
        if errorCount > 0 {
            desc += "\n\n⚠️  Errors: \(errorCount) (\(String(format: "%.1f", Double(errorCount) / total * 100))%)"
        }
        
        if !recentOperations.isEmpty {
            desc += "\n\nRecent Operations (last 3):"
            for (i, op) in recentOperations.prefix(3).enumerated() {
                let icon = op.success ? "✅" : "❌"
                desc += "\n  \(i + 1). \(icon) \(op.operation) - \(String(format: "%.2f", op.duration))ms"
            }
        }
        
        return desc
    }
}

/// Operation breakdown
public struct OperationBreakdown {
    public let operations: [String: OperationStats]
    
    public var description: String {
        var desc = "Operation Breakdown:\n"
        for (op, stats) in operations.sorted(by: { $0.key < $1.key }) {
            desc += "  • \(op): \(stats.percentage)% (\(stats.count) ops, avg \(String(format: "%.2f", stats.avgDuration))ms)\n"
        }
        return desc
    }
}

public struct OperationStats {
    public let count: Int
    public let percentage: Double
    public let avgDuration: Double
    public let totalDuration: Double
}

/// Error summary
public struct ErrorSummary {
    public let operation: String
    public let errorMessage: String
    public let timestamp: Date
    public let duration: Double
}

