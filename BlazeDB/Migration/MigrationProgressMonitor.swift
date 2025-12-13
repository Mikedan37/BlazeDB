//
//  MigrationProgressMonitor.swift
//  BlazeDB
//
//  Progress monitoring API for migration operations
//  Can be polled for UI updates
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Migration Progress

/// Progress information for migration operations
public struct MigrationProgress {
    public let currentTable: String?
    public let currentTableIndex: Int
    public let totalTables: Int
    public let recordsProcessed: Int
    public let recordsTotal: Int?
    public let bytesProcessed: Int64
    public let bytesTotal: Int64?
    public let startTime: Date
    public let estimatedTimeRemaining: TimeInterval?
    public let status: MigrationStatus
    public let error: Error?
    
    public var percentage: Double {
        if let total = recordsTotal, total > 0 {
            return Double(recordsProcessed) / Double(total) * 100.0
        }
        if let total = bytesTotal, total > 0 {
            return Double(bytesProcessed) / Double(total) * 100.0
        }
        return 0.0
    }
    
    public var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    public var description: String {
        var desc = "Migration Progress: \(status.rawValue)\n"
        if let table = currentTable {
            desc += "  Table: \(table) (\(currentTableIndex)/\(totalTables))\n"
        }
        desc += "  Records: \(recordsProcessed)"
        if let total = recordsTotal {
            desc += "/\(total) (\(String(format: "%.1f", percentage))%)"
        }
        desc += "\n"
        desc += "  Elapsed: \(String(format: "%.1f", elapsedTime))s\n"
        if let remaining = estimatedTimeRemaining {
            desc += "  Remaining: \(String(format: "%.1f", remaining))s\n"
        }
        if let error = error {
            desc += "  Error: \(error.localizedDescription)\n"
        }
        return desc
    }
}

/// Migration status
public enum MigrationStatus: String {
    case notStarted = "Not Started"
    case preparing = "Preparing"
    case migrating = "Migrating"
    case creatingIndexes = "Creating Indexes"
    case verifying = "Verifying"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

// MARK: - Progress Monitor

/// Thread-safe progress monitor for migration operations
public class MigrationProgressMonitor {
    private var progress: MigrationProgress
    private let lock = NSLock()
    private var observers: [UUID: (MigrationProgress) -> Void] = [:]
    
    public init() {
        self.progress = MigrationProgress(
            currentTable: nil,
            currentTableIndex: 0,
            totalTables: 0,
            recordsProcessed: 0,
            recordsTotal: nil,
            bytesProcessed: 0,
            bytesTotal: nil,
            startTime: Date(),
            estimatedTimeRemaining: nil,
            status: .notStarted,
            error: nil
        )
    }
    
    /// Get current progress (thread-safe)
    public func getProgress() -> MigrationProgress {
        lock.lock()
        defer { lock.unlock() }
        return progress
    }
    
    /// Update progress
    internal func update(
        currentTable: String? = nil,
        currentTableIndex: Int? = nil,
        totalTables: Int? = nil,
        recordsProcessed: Int? = nil,
        recordsTotal: Int? = nil,
        bytesProcessed: Int64? = nil,
        bytesTotal: Int64? = nil,
        status: MigrationStatus? = nil,
        error: Error? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        
        var newProgress = progress
        
        if let table = currentTable {
            newProgress = MigrationProgress(
                currentTable: table,
                currentTableIndex: currentTableIndex ?? progress.currentTableIndex,
                totalTables: totalTables ?? progress.totalTables,
                recordsProcessed: recordsProcessed ?? progress.recordsProcessed,
                recordsTotal: recordsTotal ?? progress.recordsTotal,
                bytesProcessed: bytesProcessed ?? progress.bytesProcessed,
                bytesTotal: bytesTotal ?? progress.bytesTotal,
                startTime: progress.startTime,
                estimatedTimeRemaining: calculateEstimatedTimeRemaining(
                    recordsProcessed: recordsProcessed ?? progress.recordsProcessed,
                    recordsTotal: recordsTotal ?? progress.recordsTotal,
                    elapsed: Date().timeIntervalSince(progress.startTime)
                ),
                status: status ?? progress.status,
                error: error ?? progress.error
            )
        } else {
            newProgress = MigrationProgress(
                currentTable: progress.currentTable,
                currentTableIndex: currentTableIndex ?? progress.currentTableIndex,
                totalTables: totalTables ?? progress.totalTables,
                recordsProcessed: recordsProcessed ?? progress.recordsProcessed,
                recordsTotal: recordsTotal ?? progress.recordsTotal,
                bytesProcessed: bytesProcessed ?? progress.bytesProcessed,
                bytesTotal: bytesTotal ?? progress.bytesTotal,
                startTime: progress.startTime,
                estimatedTimeRemaining: calculateEstimatedTimeRemaining(
                    recordsProcessed: recordsProcessed ?? progress.recordsProcessed,
                    recordsTotal: recordsTotal ?? progress.recordsTotal,
                    elapsed: Date().timeIntervalSince(progress.startTime)
                ),
                status: status ?? progress.status,
                error: error ?? progress.error
            )
        }
        
        progress = newProgress
        
        // Notify observers
        notifyObservers(newProgress)
    }
    
    /// Reset progress
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        progress = MigrationProgress(
            currentTable: nil,
            currentTableIndex: 0,
            totalTables: 0,
            recordsProcessed: 0,
            recordsTotal: nil,
            bytesProcessed: 0,
            bytesTotal: nil,
            startTime: Date(),
            estimatedTimeRemaining: nil,
            status: .notStarted,
            error: nil
        )
    }
    
    /// Add observer for progress updates
    public func addObserver(_ observer: @escaping (MigrationProgress) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        observers[id] = observer
        lock.unlock()
        return id
    }
    
    /// Remove observer
    public func removeObserver(_ id: UUID) {
        lock.lock()
        observers.removeValue(forKey: id)
        lock.unlock()
    }
    
    private func notifyObservers(_ progress: MigrationProgress) {
        let currentObservers = observers
        DispatchQueue.main.async {
            for observer in currentObservers.values {
                observer(progress)
            }
        }
    }
    
    private func calculateEstimatedTimeRemaining(
        recordsProcessed: Int,
        recordsTotal: Int?,
        elapsed: TimeInterval
    ) -> TimeInterval? {
        guard let total = recordsTotal, total > 0, recordsProcessed > 0, elapsed > 0 else {
            return nil
        }
        
        let rate = Double(recordsProcessed) / elapsed
        let remaining = Double(total - recordsProcessed) / rate
        return remaining > 0 ? remaining : nil
    }
}

// MARK: - Convenience Extensions

extension MigrationProgressMonitor {
    /// Start migration
    public func start(totalTables: Int, recordsTotal: Int? = nil, bytesTotal: Int64? = nil) {
        update(
            totalTables: totalTables,
            recordsTotal: recordsTotal,
            bytesTotal: bytesTotal,
            status: .preparing
        )
    }
    
    /// Update table progress
    public func updateTable(_ tableName: String, index: Int, recordsProcessed: Int) {
        update(
            currentTable: tableName,
            currentTableIndex: index,
            recordsProcessed: recordsProcessed,
            status: .migrating
        )
    }
    
    /// Complete migration
    public func complete(recordsProcessed: Int) {
        update(
            recordsProcessed: recordsProcessed,
            status: .completed
        )
    }
    
    /// Fail migration
    public func fail(_ error: Error) {
        update(
            status: .failed,
            error: error
        )
    }
    
    /// Cancel migration
    public func cancel() {
        update(status: .cancelled)
    }
}

