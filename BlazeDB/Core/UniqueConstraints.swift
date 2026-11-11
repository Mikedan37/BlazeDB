//
//  UniqueConstraints.swift
//  BlazeDB
//
//  Unique constraint enforcement at database level
//  Optimized with index-based lookups
//
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// MARK: - Unique Constraint Manager

public class UniqueConstraintManager {
    private var uniqueFields: Set<String> = []
    private var uniqueCompoundFields: Set<String> = []  // "field1+field2"
    private let lock = NSLock()
    
    public init() {}
    
    /// Mark field as unique
    public func addUniqueField(_ field: String) {
        lock.lock()
        defer { lock.unlock() }
        uniqueFields.insert(field)
        BlazeLogger.info("Added unique constraint on field '\(field)'")
    }
    
    /// Mark compound fields as unique
    public func addUniqueCompoundFields(_ fields: [String]) {
        lock.lock()
        defer { lock.unlock() }
        let key = fields.joined(separator: "+")
        uniqueCompoundFields.insert(key)
        BlazeLogger.info("Added unique constraint on compound fields '\(key)'")
    }
    
    /// Remove unique constraint
    public func removeUniqueField(_ field: String) {
        lock.lock()
        defer { lock.unlock() }
        uniqueFields.remove(field)
        BlazeLogger.info("Removed unique constraint on field '\(field)'")
    }
    
    /// Check if field is unique
    public func isUniqueField(_ field: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return uniqueFields.contains(field)
    }
    
    /// Check if compound fields are unique
    public func isUniqueCompoundFields(_ fields: [String]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = fields.joined(separator: "+")
        return uniqueCompoundFields.contains(key)
    }

    func snapshotUniqueFields() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return uniqueFields.sorted()
    }

    func snapshotUniqueCompoundKeys() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return uniqueCompoundFields.sorted()
    }

    func removeUniqueCompoundFields(_ fields: [String]) {
        lock.lock()
        defer { lock.unlock() }
        uniqueCompoundFields.remove(fields.joined(separator: "+"))
    }
    
    /// Validate unique constraint before insert
    public func validateUnique(collection: DynamicCollection, record: BlazeDataRecord, excludeId: UUID? = nil) throws {
        // Snapshot configuration under lock so validation does not iterate the sets while another
        // thread mutates them (TSan: concurrent read/write on Set storage).
        let fieldsSnapshot: Set<String>
        let compoundSnapshot: Set<String>
        lock.lock()
        fieldsSnapshot = uniqueFields
        compoundSnapshot = uniqueCompoundFields
        lock.unlock()

        // Check single-field unique constraints
        for field in fieldsSnapshot {
            guard let value = record.storage[field] else { continue }
            
            // Check if another record has this value
            // Use query instead of direct index fetch (more reliable)
            let queryBuilder = QueryBuilder(collection: collection)
            queryBuilder.where(field, equals: value)
            let existing = try queryBuilder.execute()
            let records = try existing.records
            let conflicting = records.filter { record in
                guard let recordId = record.storage["id"]?.uuidValue else { return false }
                return recordId != excludeId
            }
            
            if !conflicting.isEmpty {
                throw BlazeDBError.uniqueConstraintViolation(
                    field: field,
                    value: value,
                    message: "Duplicate value '\(value)' for unique field '\(field)'"
                )
            }
        }
        
        // Check compound unique constraints
        for compoundKey in compoundSnapshot {
            let fields = compoundKey.components(separatedBy: "+")
            guard fields.allSatisfy({ record.storage[$0] != nil }) else { continue }
            
            // Build compound key
            let values = fields.compactMap { record.storage[$0] }
            guard values.count == fields.count else { continue }
            
            // Check for duplicates using compound index query
            let queryBuilder = QueryBuilder(collection: collection)
            for (index, field) in fields.enumerated() {
                queryBuilder.where(field, equals: values[index])
            }
            let existing = try queryBuilder.execute()
            let records = try existing.records
            let conflicting = records.filter { record in
                guard let recordId = record.storage["id"]?.uuidValue else { return false }
                return recordId != excludeId
            }
            
            if !conflicting.isEmpty {
                throw BlazeDBError.uniqueConstraintViolation(
                    field: compoundKey,
                    value: nil,
                    message: "Duplicate values for unique compound fields '\(compoundKey)'"
                )
            }
        }
    }

    /// Validate uniqueness against not-yet-written siblings in the same batch.
    /// Durable uniqueness is still checked separately via `validateUnique`.
    public func validateUniqueAgainstPending(
        record: BlazeDataRecord,
        pending: [BlazeDataRecord]
    ) throws {
        let fieldsSnapshot: Set<String>
        let compoundSnapshot: Set<String>
        lock.lock()
        fieldsSnapshot = uniqueFields
        compoundSnapshot = uniqueCompoundFields
        lock.unlock()

        let recordId = record.storage["id"]?.uuidValue

        for field in fieldsSnapshot {
            guard let value = record.storage[field] else { continue }
            let conflict = pending.contains { pendingRecord in
                guard pendingRecord.storage[field] == value else { return false }
                guard let pendingId = pendingRecord.storage["id"]?.uuidValue else { return true }
                return pendingId != recordId
            }
            if conflict {
                throw BlazeDBError.uniqueConstraintViolation(
                    field: field,
                    value: value,
                    message: "Duplicate value '\(value)' for unique field '\(field)' within batch"
                )
            }
        }

        for compoundKey in compoundSnapshot {
            let fields = compoundKey.components(separatedBy: "+")
            guard fields.allSatisfy({ record.storage[$0] != nil }) else { continue }
            let values = fields.compactMap { record.storage[$0] }
            guard values.count == fields.count else { continue }

            let conflict = pending.contains { pendingRecord in
                guard fields.allSatisfy({ pendingRecord.storage[$0] == record.storage[$0] }) else {
                    return false
                }
                guard let pendingId = pendingRecord.storage["id"]?.uuidValue else { return true }
                return pendingId != recordId
            }
            if conflict {
                throw BlazeDBError.uniqueConstraintViolation(
                    field: compoundKey,
                    value: nil,
                    message: "Duplicate values for unique compound fields '\(compoundKey)' within batch"
                )
            }
        }
    }
}

// MARK: - BlazeDBClient Unique Constraints Extension

extension BlazeDBClient {
    nonisolated(unsafe) private static var uniqueConstraintManagerKey: UInt8 = 0
    
    private var uniqueConstraintManager: UniqueConstraintManager {
        AssociatedObjects.getOrCreate(self, key: &Self.uniqueConstraintManagerKey) {
            UniqueConstraintManager()
        }
    }
    
    /// Metadata keys for unique constraints. The in-memory manager is per client
    /// instance, so the catalog has to carry these or the next open accepts duplicates.
    static let uniqueFieldsMetaKey = "_uniqueFields"
    static let uniqueCompoundFieldsMetaKey = "_uniqueCompoundFields"

    /// Create unique index (enforces uniqueness)
    public func createUniqueIndex(on field: String) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        try ensureNotClosed()

        // Create index first
        try collection.createIndex(on: field)
        
        // Mark as unique. A failed catalog write must not drop a constraint that was already durable.
        let alreadyUnique = uniqueConstraintManager.isUniqueField(field)
        uniqueConstraintManager.addUniqueField(field)
        do {
            try persistUniqueConstraints()
        } catch {
            if !alreadyUnique {
                uniqueConstraintManager.removeUniqueField(field)
            }
            throw error
        }
        
        BlazeLogger.info("Created unique index on field '\(field)'")
    }
    
    /// Create unique compound index
    public func createUniqueCompoundIndex(on fields: [String]) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        try ensureNotClosed()

        // Create compound index first
        try collection.createIndex(on: fields)
        
        // Mark as unique. A failed catalog write must not drop a constraint that was already durable.
        let alreadyUnique = uniqueConstraintManager.isUniqueCompoundFields(fields)
        uniqueConstraintManager.addUniqueCompoundFields(fields)
        do {
            try persistUniqueConstraints()
        } catch {
            if !alreadyUnique {
                uniqueConstraintManager.removeUniqueCompoundFields(fields)
            }
            throw error
        }
        
        BlazeLogger.info("Created unique compound index on fields '\(fields.joined(separator: ", "))'")
    }

    /// Reload durable unique constraints after open. Missing keys mean none were declared.
    func restoreUniqueConstraints() throws {
        let meta = try collection.fetchMeta()
        if case .array(let fields)? = meta[Self.uniqueFieldsMetaKey] {
            for field in fields {
                if case .string(let name) = field, !name.isEmpty {
                    uniqueConstraintManager.addUniqueField(name)
                }
            }
        }
        if case .array(let compounds)? = meta[Self.uniqueCompoundFieldsMetaKey] {
            for compound in compounds {
                guard case .string(let key) = compound, !key.isEmpty else { continue }
                uniqueConstraintManager.addUniqueCompoundFields(key.components(separatedBy: "+"))
            }
        }
    }

    /// Copy durable unique-constraint metadata onto a replacement catalog.
    /// VACUUM rebuilds the meta file from inserted rows and would otherwise drop these keys.
    func copyUniqueConstraintMetadata(to metaURL: URL, signingKey: SymmetricKey) throws {
        let preserved = try preservedUniqueConstraintMetadata()
        guard !preserved.isEmpty else { return }
        guard FileManager.default.fileExists(atPath: metaURL.path) else { return }

        var layout = try StorageLayout.loadSecure(
            from: metaURL,
            signingKey: signingKey,
            password: password,
            salt: kdfSalt,
            allowUnsignedLayoutFallback: true
        )
        for (key, value) in preserved {
            layout.metaData[key] = value
        }
        try layout.saveSecure(to: metaURL, signingKey: signingKey)
    }

    private func persistUniqueConstraints() throws {
        var meta = try collection.fetchMeta()
        let fields = uniqueConstraintManager.snapshotUniqueFields()
        let compounds = uniqueConstraintManager.snapshotUniqueCompoundKeys()
        if fields.isEmpty {
            meta.removeValue(forKey: Self.uniqueFieldsMetaKey)
        } else {
            meta[Self.uniqueFieldsMetaKey] = .array(fields.map { .string($0) })
        }
        if compounds.isEmpty {
            meta.removeValue(forKey: Self.uniqueCompoundFieldsMetaKey)
        } else {
            meta[Self.uniqueCompoundFieldsMetaKey] = .array(compounds.map { .string($0) })
        }
        try collection.updateMeta(meta)
    }

    private func preservedUniqueConstraintMetadata() throws -> [String: BlazeDocumentField] {
        let meta = try collection.fetchMeta()
        var preserved: [String: BlazeDocumentField] = [:]
        for key in [Self.uniqueFieldsMetaKey, Self.uniqueCompoundFieldsMetaKey] {
            if let value = meta[key] {
                preserved[key] = value
            }
        }
        return preserved
    }
    
    /// Validate unique constraints before insert/update
    internal func validateUniqueConstraints(in record: BlazeDataRecord, excludeId: UUID? = nil) throws {
        try uniqueConstraintManager.validateUnique(collection: collection, record: record, excludeId: excludeId)
    }

    /// Validate unique constraints against other prepared records in the same batch.
    internal func validateUniqueConstraintsAgainstPending(
        in record: BlazeDataRecord,
        pending: [BlazeDataRecord]
    ) throws {
        try uniqueConstraintManager.validateUniqueAgainstPending(record: record, pending: pending)
    }
}

// MARK: - BlazeDBError Unique Constraint Extension

extension BlazeDBError {
    public static func uniqueConstraintViolation(field: String, value: BlazeDocumentField?, message: String) -> BlazeDBError {
        var msg = "Unique constraint violation on '\(field)'"
        if let value = value {
            msg += " with value '\(value)'"
        }
        msg += ": \(message)"
        return .transactionFailed(msg)
    }
}

