//
//  OrderingIndex+Advanced.swift
//  BlazeDB
//
//  Advanced ordering features: multiple fields, relative moves, bulk operations
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Multiple Ordering Fields

extension OrderingIndex {
    /// Get ordering index for a specific category/context
    /// - Parameters:
    ///   - record: BlazeDataRecord
    ///   - categoryField: Field name for category (e.g., "category")
    ///   - categoryValue: Category value to filter by
    ///   - fieldName: Base ordering field name (default: "orderingIndex")
    /// - Returns: Ordering index for the category, or nil if not found
    public static func getIndex(
        from record: BlazeDataRecord,
        categoryField: String,
        categoryValue: String,
        fieldName: String = "orderingIndex"
    ) -> Double? {
        // Check if record belongs to category
        guard let recordCategory = record.storage[categoryField]?.stringValue,
              recordCategory == categoryValue else {
            let recordID = record.storage["id"]?.uuidValue?.uuidString ?? "unknown"
            BlazeLogger.trace("OrderingIndex.getIndex: record \(recordID) not in category '\(categoryValue)'")
            return nil
        }
        
        // Use category-specific field name: "orderingIndex_category"
        let categoryFieldName = "\(fieldName)_\(categoryValue)"
        return getIndex(from: record, fieldName: categoryFieldName)
    }
    
    /// Set ordering index for a specific category
    /// - Parameters:
    ///   - index: Ordering index value
    ///   - record: BlazeDataRecord
    ///   - categoryField: Field name for category
    ///   - categoryValue: Category value
    ///   - fieldName: Base ordering field name (default: "orderingIndex")
    /// - Returns: Modified record with category-specific ordering index
    public static func setIndex(
        _ index: Double,
        on record: BlazeDataRecord,
        categoryField: String,
        categoryValue: String,
        fieldName: String = "orderingIndex"
    ) -> BlazeDataRecord {
        let categoryFieldName = "\(fieldName)_\(categoryValue)"
        BlazeLogger.debug("OrderingIndex.setIndex: setting \(categoryFieldName) = \(index) for category '\(categoryValue)'")
        return setIndex(index, on: record, fieldName: categoryFieldName)
    }
}

// MARK: - Relative Moves

extension OrderingIndex {
    /// Calculate index for moving up N positions
    /// - Parameters:
    ///   - currentIndex: Current ordering index
    ///   - positions: Number of positions to move up (default: 1)
    /// - Returns: New ordering index
    public static func moveUp(from currentIndex: Double, positions: Int = 1) -> Double {
        // Subtract positions * 1.0
        let result = max(0.0, currentIndex - Double(positions))
        BlazeLogger.debug("OrderingIndex.moveUp: \(currentIndex) up \(positions) positions = \(result)")
        return result
    }
    
    /// Calculate index for moving down N positions
    /// - Parameters:
    ///   - currentIndex: Current ordering index
    ///   - positions: Number of positions to move down (default: 1)
    /// - Returns: New ordering index
    public static func moveDown(from currentIndex: Double, positions: Int = 1) -> Double {
        // Add positions * 1.0
        let result = currentIndex + Double(positions)
        BlazeLogger.debug("OrderingIndex.moveDown: \(currentIndex) down \(positions) positions = \(result)")
        return result
    }
}

// MARK: - Bulk Reordering

/// Bulk reordering operation
public struct BulkReorderOperation {
    public let recordId: UUID
    public let newIndex: Double
    
    public init(recordId: UUID, newIndex: Double) {
        self.recordId = recordId
        self.newIndex = newIndex
    }
}

/// Result of bulk reordering operation
public struct BulkReorderResult {
    public let successful: Int
    public let failed: Int
    public let errors: [(UUID, Error)]
    
    public init(successful: Int, failed: Int, errors: [(UUID, Error)]) {
        self.successful = successful
        self.failed = failed
        self.errors = errors
    }
}

