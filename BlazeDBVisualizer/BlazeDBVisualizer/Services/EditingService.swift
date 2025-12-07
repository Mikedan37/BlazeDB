//
//  EditingService.swift
//  BlazeDBVisualizer
//
//  Manages all database editing operations
//  ✅ Insert, update, delete records
//  ✅ Bulk operations
//  ✅ Undo support
//  ✅ Audit logging
//
//  Created by Michael Danylchuk on 11/14/25.
//

import Foundation
import BlazeDB

// MARK: - Edit Operation

enum EditOperation {
    case insert(record: BlazeDataRecord, id: UUID)
    case update(id: UUID, oldData: BlazeDataRecord, newData: BlazeDataRecord)
    case delete(id: UUID, data: BlazeDataRecord)
    case bulkUpdate(ids: [UUID], field: String, oldValues: [BlazeDocumentField], newValue: BlazeDocumentField)
    case bulkDelete(records: [(UUID, BlazeDataRecord)])
    
    var description: String {
        switch self {
        case .insert: return "Insert record"
        case .update: return "Update record"
        case .delete: return "Delete record"
        case .bulkUpdate(let ids, let field, _, _): return "Update \(field) in \(ids.count) records"
        case .bulkDelete(let records): return "Delete \(records.count) records"
        }
    }
}

// MARK: - Undo Entry

struct UndoEntry: Identifiable {
    let id = UUID()
    let operation: EditOperation
    let timestamp: Date
    let expiresAt: Date
    
    init(operation: EditOperation, undoTimeout: TimeInterval = 30) {
        self.operation = operation
        self.timestamp = Date()
        self.expiresAt = Date().addingTimeInterval(undoTimeout)
    }
    
    var isExpired: Bool {
        Date() > expiresAt
    }
    
    var timeRemaining: TimeInterval {
        max(0, expiresAt.timeIntervalSince(Date()))
    }
}

// MARK: - Editing Service

@MainActor
class EditingService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var undoStack: [UndoEntry] = []
    @Published var lastOperation: String?
    @Published var isProcessing = false
    @Published var error: Error?
    
    // MARK: - Private Properties
    
    private var db: BlazeDBClient?
    private var dbPath: String?
    private let auditService: AuditLogService
    private let undoTimeout: TimeInterval = 30
    private var cleanupTimer: Timer?
    
    // MARK: - Settings
    
    struct Settings {
        var autoBackupBeforeEdit = true
        var requireConfirmationForDelete = true
        var maxBulkOperationSize = 1000
        var enableAuditLogging = true
    }
    
    var settings = Settings()
    
    // MARK: - Initialization
    
    init(auditService: AuditLogService = AuditLogService.shared) {
        self.auditService = auditService
        startCleanupTimer()
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
    
    // MARK: - Database Connection
    
    func connect(dbPath: String, password: String) throws {
        let url = URL(fileURLWithPath: dbPath)
        let name = url.deletingPathExtension().lastPathComponent
        self.db = try BlazeDBClient(name: name, fileURL: url, password: password)
        self.dbPath = dbPath
    }
    
    func disconnect() {
        db = nil
        dbPath = nil
        undoStack.removeAll()
    }
    
    // MARK: - Insert Operations
    
    func insertRecord(_ data: BlazeDataRecord) async throws -> UUID {
        guard let db = db else { throw EditingError.notConnected }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Create backup if needed
        if settings.autoBackupBeforeEdit && undoStack.isEmpty {
            try await createSafetyBackup()
        }
        
        // Insert record (offload synchronous BlazeDB operations to background)
        let (id, operation) = try await Task.detached {
            let id = try db.insert(data)
            try db.persist()
            let operation = EditOperation.insert(record: data, id: id)
            return (id, operation)
        }.value
        
        // Add to undo stack
        addToUndoStack(operation)
        
        // Audit log
        if settings.enableAuditLogging {
            auditService.log(operation: .insert, recordID: id, newValue: data.storage)
        }
        
        lastOperation = "Record created"
        return id
    }
    
    // MARK: - Update Operations
    
    func updateRecord(id: UUID, with newData: BlazeDataRecord) async throws {
        guard let db = db else { throw EditingError.notConnected }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Create backup if needed
        if settings.autoBackupBeforeEdit && undoStack.isEmpty {
            try await createSafetyBackup()
        }
        
        // Update record (offload to background)
        let (oldRecord, operation) = try await Task.detached {
            guard let oldRecord = try db.fetch(id: id) else {
                throw EditingError.recordNotFound(id: id)
            }
            try db.update(id: id, with: newData)
            try db.persist()
            let operation = EditOperation.update(id: id, oldData: oldRecord, newData: newData)
            return (oldRecord, operation)
        }.value
        
        // Add to undo stack
        addToUndoStack(operation)
        
        // Audit log
        if settings.enableAuditLogging {
            auditService.log(operation: .update, recordID: id, oldValue: oldRecord.storage, newValue: newData.storage)
        }
        
        lastOperation = "Record updated"
    }
    
    func updateField(id: UUID, field: String, value: BlazeDocumentField) async throws {
        guard let db = db else { throw EditingError.notConnected }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Create backup if needed
        if settings.autoBackupBeforeEdit && undoStack.isEmpty {
            try await createSafetyBackup()
        }
        
        // Update field (offload to background)
        let (oldRecord, newRecord, operation) = try await Task.detached {
            guard let oldRecord = try db.fetch(id: id) else {
                throw EditingError.recordNotFound(id: id)
            }
            try db.updateFields(id: id, fields: [field: value])
            try db.persist()
            guard let newRecord = try db.fetch(id: id) else {
                throw EditingError.recordNotFound(id: id)
            }
            let operation = EditOperation.update(id: id, oldData: oldRecord, newData: newRecord)
            return (oldRecord, newRecord, operation)
        }.value
        
        // Add to undo stack
        addToUndoStack(operation)
        
        // Audit log
        if settings.enableAuditLogging {
            auditService.log(operation: .update, recordID: id, oldValue: oldRecord.storage, newValue: newRecord.storage)
        }
        
        lastOperation = "Field '\(field)' updated"
    }
    
    // MARK: - Delete Operations
    
    func deleteRecord(id: UUID) async throws {
        guard let db = db else { throw EditingError.notConnected }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Create backup if needed
        if settings.autoBackupBeforeEdit && undoStack.isEmpty {
            try await createSafetyBackup()
        }
        
        // Delete record (offload to background)
        let (record, operation) = try await Task.detached {
            guard let record = try db.fetch(id: id) else {
                throw EditingError.recordNotFound(id: id)
            }
            try db.delete(id: id)
            try db.persist()
            let operation = EditOperation.delete(id: id, data: record)
            return (record, operation)
        }.value
        
        // Add to undo stack
        addToUndoStack(operation)
        
        // Audit log
        if settings.enableAuditLogging {
            auditService.log(operation: .delete, recordID: id, oldValue: record.storage)
        }
        
        lastOperation = "Record deleted"
    }
    
    // MARK: - Bulk Operations
    
    func bulkUpdateField(ids: [UUID], field: String, value: BlazeDocumentField) async throws {
        guard let db = db else { throw EditingError.notConnected }
        guard ids.count <= settings.maxBulkOperationSize else {
            throw EditingError.bulkOperationTooLarge(count: ids.count, max: settings.maxBulkOperationSize)
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Create backup if needed
        if settings.autoBackupBeforeEdit && undoStack.isEmpty {
            try await createSafetyBackup()
        }
        
        // Bulk update (offload to background)
        let (updated, operation) = try await Task.detached {
            // Get old values for undo
            var oldValues: [BlazeDocumentField] = []
            for id in ids {
                if let record = try db.fetch(id: id),
                   let oldValue = record.storage[field] {
                    oldValues.append(oldValue)
                } else {
                    oldValues.append(.string("")) // Placeholder for missing
                }
            }
            
            // Update all records
            var updated = 0
            for id in ids {
                do {
                    try db.updateFields(id: id, fields: [field: value])
                    updated += 1
                } catch {
                    print("⚠️ Failed to update record \(id): \(error)")
                }
            }
            try db.persist()
            
            let operation = EditOperation.bulkUpdate(ids: ids, field: field, oldValues: oldValues, newValue: value)
            return (updated, operation)
        }.value
        
        // Add to undo stack
        addToUndoStack(operation)
        
        // Audit log
        if settings.enableAuditLogging {
            auditService.log(operation: .bulkUpdate, details: "Updated \(field) in \(updated) records")
        }
        
        lastOperation = "Updated \(updated) records"
    }
    
    func bulkDelete(ids: [UUID]) async throws {
        guard let db = db else { throw EditingError.notConnected }
        guard ids.count <= settings.maxBulkOperationSize else {
            throw EditingError.bulkOperationTooLarge(count: ids.count, max: settings.maxBulkOperationSize)
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Create backup if needed
        if settings.autoBackupBeforeEdit && undoStack.isEmpty {
            try await createSafetyBackup()
        }
        
        // Bulk delete (offload to background)
        let (deleted, operation) = try await Task.detached {
            // Get records for undo
            var records: [(UUID, BlazeDataRecord)] = []
            for id in ids {
                if let record = try db.fetch(id: id) {
                    records.append((id, record))
                }
            }
            
            // Delete all records
            var deleted = 0
            for id in ids {
                do {
                    try db.delete(id: id)
                    deleted += 1
                } catch {
                    print("⚠️ Failed to delete record \(id): \(error)")
                }
            }
            try db.persist()
            
            let operation = EditOperation.bulkDelete(records: records)
            return (deleted, operation)
        }.value
        
        // Add to undo stack
        addToUndoStack(operation)
        
        // Audit log
        if settings.enableAuditLogging {
            auditService.log(operation: .bulkDelete, details: "Deleted \(deleted) records")
        }
        
        lastOperation = "Deleted \(deleted) records"
    }
    
    // MARK: - Undo
    
    func undo() async throws {
        guard let entry = undoStack.last else { return }
        guard !entry.isExpired else {
            undoStack.removeLast()
            throw EditingError.undoExpired
        }
        guard let db = db else { throw EditingError.notConnected }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Perform undo operation (offload to background)
        try await Task.detached {
            switch entry.operation {
            case .insert(_, let id):
                // Undo insert by deleting
                try? db.delete(id: id)
                
            case .update(let id, let oldData, _):
                // Undo update by restoring old data
                try? db.update(id: id, with: oldData)
                
            case .delete(let id, let data):
                // Undo delete by reinserting
                try? db.insert(data, id: id)
                
            case .bulkUpdate(let ids, let field, let oldValues, _):
                // Undo bulk update by restoring old values
                for (index, id) in ids.enumerated() {
                    if index < oldValues.count {
                        try? db.updateFields(id: id, fields: [field: oldValues[index]])
                    }
                }
                
            case .bulkDelete(let records):
                // Undo bulk delete by reinserting all
                for (id, record) in records {
                    try? db.insert(record, id: id)
                }
            }
            
            try db.persist()
        }.value
        
        // Remove from undo stack
        undoStack.removeLast()
        
        // Audit log
        if settings.enableAuditLogging {
            auditService.log(operation: .undo, details: "Undid: \(entry.operation.description)")
        }
        
        lastOperation = "Undid: \(entry.operation.description)"
    }
    
    func canUndo() -> Bool {
        guard let entry = undoStack.last else { return false }
        return !entry.isExpired
    }
    
    // MARK: - Helpers
    
    private func addToUndoStack(_ operation: EditOperation) {
        let entry = UndoEntry(operation: operation, undoTimeout: undoTimeout)
        undoStack.append(entry)
    }
    
    private func createSafetyBackup() async throws {
        guard let dbPath = dbPath else { return }
        
        let backupService = BackupRestoreService.shared
        
        // Create unique backup name with timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let backupName = "auto_before_edit_\(timestamp)"
        
        print("💾 Creating safety backup: \(backupName)")
        _ = try backupService.createBackup(dbPath: dbPath, name: backupName)
        print("✅ Safety backup created")
        
        // Audit log
        if settings.enableAuditLogging {
            auditService.log(operation: .backup, details: "Automatic safety backup before first edit: \(backupName)")
        }
    }
    
    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.cleanupExpiredUndos()
        }
    }
    
    private func cleanupExpiredUndos() {
        undoStack.removeAll { $0.isExpired }
    }
}

// MARK: - Editing Error

enum EditingError: LocalizedError {
    case notConnected
    case recordNotFound(id: UUID)
    case bulkOperationTooLarge(count: Int, max: Int)
    case undoExpired
    case invalidFieldType(field: String, expectedType: String, actualValue: String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to database"
        case .recordNotFound(let id):
            return "Record not found: \(id)"
        case .bulkOperationTooLarge(let count, let max):
            return "Bulk operation too large: \(count) records (max: \(max))"
        case .undoExpired:
            return "Undo window expired (30 seconds)"
        case .invalidFieldType(let field, let expectedType, let actualValue):
            return "Invalid type for field '\(field)': expected \(expectedType), got '\(actualValue)'"
        }
    }
}

