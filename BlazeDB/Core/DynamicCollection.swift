//  DynamicCollection.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.

import Foundation
import CryptoKit

extension DispatchQueue {
func syncThrowing<T>(_ block: () throws -> T) throws -> T {
    var result: Result<T, Error>!
    sync {
        result = Result { try block() }
    }
    return try result.get()
}
}

// MARK: - MetaStore Protocol
public protocol MetaStore {
func fetchMeta() throws -> [String: BlazeDocumentField]
func updateMeta(_ newMeta: [String: BlazeDocumentField]) throws
}

public enum BlazeDocumentField: Codable, Equatable, Hashable {
// Represents various supported value types in a dynamic document.
case string(String)                     // Text string
case int(Int)                           // Integer number
case double(Double)                     // Floating-point number
case bool(Bool)                         // Boolean value
case date(Date)                         // Date timestamp
case uuid(UUID)                         // Universally unique identifier
case data(Data)                         // Binary data
case array([BlazeDocumentField])        // Heterogeneous array of BlazeDocumentFields
case dictionary([String: BlazeDocumentField]) // Dictionary type

/// Returns the raw Swift value held by this field.
public var value: Any {
    switch self {
    case .string(let v): return v
    case .int(let v): return v
    case .double(let v): return v
    case .bool(let v): return v
    case .date(let v): return v
    case .uuid(let v): return v
    case .data(let v): return v
    case .array(let v): return v
    case .dictionary(let v): return v
    }
}

/// Attempts to decode a single value container into one of the supported types.
/// The types are tried in order of likelihood/simplicity.
public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    // Attempt each type in turn. First match wins.
    // Special handling for String vs Data: We check if it's a valid base64 string
    // that looks like encoded binary data before treating it as Data
    
    // Try non-string types first
    // IMPORTANT: Order matters! Try most specific types first
    if let v = try? container.decode(Bool.self) {
        // Bool must be before Int/Double (bools can decode as 0/1)
        self = .bool(v)
    } else if let v = try? container.decode(Int.self) {
        // Int must be before Double (ints can decode as doubles)
        // Int must be before Date (timestamps are numeric)
        self = .int(v)
    } else if let v = try? container.decode(Double.self) {
        // Double before Date (timestamps can be doubles)
        self = .double(v)
    } else if let v = try? container.decode(UUID.self) {
        self = .uuid(v)
    } else if let v = try? container.decode(Date.self) {
        // Date AFTER numeric types (timestamps decode as Int/Double first)
        self = .date(v)
    } else if let v = try? container.decode([BlazeDocumentField].self) {
        self = .array(v)
    } else if let v = try? container.decode([String: BlazeDocumentField].self) {
        self = .dictionary(v)
    } else if let stringValue = try? container.decode(String.self) {
        // For strings, check if it's base64-encoded Data
        // NOTE: Empty Data() and empty String "" both encode as "" in JSON
        // We can't reliably distinguish them, so we treat "" as String by default
        
        if !stringValue.isEmpty {
            // Base64 detection with multi-tier heuristic:
            // 1. Has padding (=, ==) → definitely base64
            // 2. No padding but long (>16 chars) with only base64 chars → likely base64
            // 3. Short strings without padding → treat as regular strings
            
            let hasPadding = stringValue.hasSuffix("=") || stringValue.hasSuffix("==")
            let isBase64Chars = stringValue.allSatisfy { char in
                char.isLetter || char.isNumber || char == "+" || char == "/" || char == "="
            }
            
            // Check character diversity (real base64 has varied chars)
            let uniqueChars = Set(stringValue)
            let hasLowEntropy = uniqueChars.count < 4  // e.g., "aaaa..." or "AAAA..."
            
            let isLikelyBase64: Bool
            if hasPadding && isBase64Chars && !hasLowEntropy {
                // Definitely base64 (has padding + diversity)
                isLikelyBase64 = true
            } else if !hasPadding && isBase64Chars && stringValue.count > 16 && !hasLowEntropy {
                // Probably base64 (long, no spaces/punctuation, diverse chars)
                isLikelyBase64 = true
            } else {
                // Probably a regular string (low diversity = repeated chars like "aaaa...")
                isLikelyBase64 = false
            }
            
            if isLikelyBase64, let data = Data(base64Encoded: stringValue) {
                // Successfully decoded as base64 → treat as Data
                self = .data(data)
            } else {
                // Regular string
                self = .string(stringValue)
            }
        } else {
            // Empty string → treat as String (can't distinguish from empty Data)
            self = .string(stringValue)
        }
    } else {
        throw DecodingError.typeMismatch(
            BlazeDocumentField.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid value type for BlazeDocumentField"
            )
        )
    }
}

/// Encodes the wrapped value based on its case into a single value container.
public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let v): try container.encode(v)
    case .int(let v): try container.encode(v)
    case .double(let v): try container.encode(v)
    case .bool(let v): try container.encode(v)
    case .date(let v): try container.encode(v)
    case .uuid(let v): try container.encode(v)
    case .data(let v): try container.encode(v)
    case .array(let v): try container.encode(v)
    case .dictionary(let v): try container.encode(v)
    }
}
}

public extension BlazeDocumentField {
    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case let .int(value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case let .double(value) = self { return value }
        // Also try to convert int to double
        if case let .int(value) = self { return Double(value) }
        return nil
    }

    var dateValue: Date? {
        if case let .date(value) = self { return value }
        // Handle dates that were stored as TimeInterval (Double)
        // Swift encodes Date as timeIntervalSinceReferenceDate, not timeIntervalSince1970!
        if case let .double(timestamp) = self { return Date(timeIntervalSinceReferenceDate: timestamp) }
        // Handle dates that were stored as whole-second timestamps (Int)
        if case let .int(timestamp) = self { return Date(timeIntervalSinceReferenceDate: Double(timestamp)) }
        // Handle dates that were stored as ISO8601 strings (from BlazeStorable/Codable)
        if case let .string(isoString) = self {
            // OPTIMIZED: Use cached formatter (no allocation!)
            return cachedISO8601Formatter.date(from: isoString)
        }
        return nil
    }

    var dataValue: Data? {
        if case let .data(value) = self { return value }
        
        // Compatibility: Handle edge cases where Data was stored as String
        if case let .string(value) = self {
            // Empty strings are treated as empty Data
            if value.isEmpty {
                return Data()
            }
            // Try to decode as base64 (for Data that wasn't caught by the decoder heuristic)
            if let data = Data(base64Encoded: value) {
                return data
            }
        }
        
        return nil
    }

    var uuidValue: UUID? {
        if case let .uuid(value) = self { return value }
        // Handle UUIDs that were stored as strings
        if case let .string(value) = self { return UUID(uuidString: value) }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        // Handle bools that were stored as integers (0/1)
        if case let .int(value) = self { return value != 0 }
        return nil
    }

    var arrayValue: [BlazeDocumentField]? {
        if case let .array(value) = self { return value }
        return nil
    }

    var dictionaryValue: [String: BlazeDocumentField]? {
        if case let .dictionary(value) = self { return value }
        return nil
    }
}

public enum CompoundKeyComponent: Hashable, Codable {
case string(String)
case int(Int)
case double(Double)
case bool(Bool)
case date(Date)
case uuid(UUID)

public init(_ any: AnyHashable) {
    switch any {
    case let v as String: self = .string(v)
    case let v as Int: self = .int(v)
    case let v as Double: self = .double(v)
    case let v as Bool: self = .bool(v)
    case let v as Date: self = .date(v)
    case let v as UUID: self = .uuid(v)
    default: self = .string(String(describing: any))
    }
}
}

public struct CompoundIndexKey: Codable, Hashable {
public let components: [AnyBlazeCodable]

public init(_ values: [AnyHashable]) {
    self.components = values.map { AnyBlazeCodable($0) }
}
public init(single value: AnyHashable) {
    self.components = [AnyBlazeCodable(value)]
}
public init(_ values: [AnyBlazeCodable]) {
    self.components = values
}

public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.components = try container.decode([AnyBlazeCodable].self)
}
public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(components)
}
static func fromFields(_ document: [String: BlazeDocumentField], fields: [String]) -> CompoundIndexKey {
    let values = fields.map { field in
        guard let docField = document[field] else {
            return "" as AnyHashable // fallback to empty string if not found
        }
        switch docField {
        case .string(let v):
            return v as AnyHashable
        case .int(let v):
            return v as AnyHashable
        case .double(let v):
            return v as AnyHashable
        case .bool(let v):
            return v as AnyHashable
        case .date(let v):
            return v as AnyHashable
        case .uuid(let v):
            return v as AnyHashable
        case .data(let v):
            return v as AnyHashable  // Binary data can be used as compound key
        case .array, .dictionary:
            return "" as AnyHashable // fallback for unsupported types
        }
    }
    return CompoundIndexKey(values)
}
}

/// DynamicCollection: A fully dynamic, schema-less collection type backed by CBOR pages.
///
/// Supports:
///  - Arbitrary field storage
///  - Single-field and compound secondary indexes (multi-field indexes)
///  - Efficient fetch by indexed fields (including compound index lookups)
///  - Thread-safe concurrency via GCD barrier queues
public final class DynamicCollection {
    
    // OPTIMIZED: Cached ISO8601DateFormatter (created once, reused forever)
    private static let cachedISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
internal var indexMap: [UUID: Int] = [:]
internal let store: PageStore
internal let metaURL: URL
internal var nextPageIndex: Int = 0
internal var secondaryIndexes: [String: [CompoundIndexKey: Set<UUID>]] = [:]
internal let project: String
internal let queue = DispatchQueue(label: "com.yourorg.blazedb.dynamiccollection", attributes: .concurrent)
internal let encryptionKey: SymmetricKey

// MVCC: Version management for concurrent access
internal let versionManager: VersionManager
// TODO: Enable MVCC after implementing version persistence to disk
// TEMPORARY: Disabled to prevent data loss on reopen (version history doesn't persist yet)
internal var mvccEnabled: Bool = false  // ⚠️  DISABLED until persistence implemented
internal lazy var gcManager: AutomaticGCManager = {
    AutomaticGCManager(versionManager: versionManager)
}()

// Performance optimization: Batch metadata writes
internal var unsavedChanges = 0
private let metadataFlushThreshold = 1000  // Save every 1000 operations (10x faster for batches!)

// Cached search index to avoid reloading from disk on every save
internal var cachedSearchIndex: InvertedIndex?
internal var cachedSearchIndexedFields: [String] = []

    /// Publicly expose the metaURL
    public var metaURLPath: URL {
        return metaURL
    }

/// Publicly expose the store's fileURL
public var fileURL: URL {
    return store.fileURL
}

    public init(store: PageStore, metaURL: URL, project: String, encryptionKey: SymmetricKey) throws {
        self.store = store
        self.metaURL = metaURL
        self.project = project
        self.encryptionKey = encryptionKey
        self.versionManager = VersionManager()  // Initialize MVCC
        let layoutExists = FileManager.default.fileExists(atPath: metaURL.path)

        if layoutExists {
            do {
                let layout = try StorageLayout.load(from: metaURL)
                self.indexMap = layout.indexMap
                self.nextPageIndex = layout.nextPageIndex
                self.secondaryIndexes = layout.toRuntimeIndexes()
                
                // Cache search index to avoid reloading on every save
                self.cachedSearchIndex = layout.searchIndex
                self.cachedSearchIndexedFields = layout.searchIndexedFields
                
                BlazeLogger.debug("DynamicCollection init: Loaded layout with \(self.indexMap.count) records, nextPageIndex=\(self.nextPageIndex)")
                
                // ✅ FIXED: Auto-migration now stores format in JSON field, not as binary prefix
                do {
                    try self.performAutoMigrationIfNeeded()
                } catch {
                    BlazeLogger.warn("AutoMigration error (non-fatal): \(error)")
                }
                
                // --- Begin: Ensure persisted secondary index data is restored correctly ---
                // Load full secondary index data from .indexes file if present
                let indexFile = metaURL.appendingPathExtension("indexes")
                if let data = try? Data(contentsOf: indexFile),
                   let decoded = try? JSONDecoder().decode([String: [CompoundIndexKey: [UUID]]].self, from: data) {
                    // Merge loaded indexes into self.secondaryIndexes
                    self.secondaryIndexes = decoded.mapValues { $0.mapValues(Set.init) }
                    BlazeLogger.info("Restored persisted secondary indexes from .indexes file (\(self.secondaryIndexes.count) indexes).")
                } else if !layout.secondaryIndexes.isEmpty {
                    var merged = self.secondaryIndexes
                    var restoredEntryCount = 0
                    for (compoundKey, persisted) in layout.secondaryIndexes {
                        var restored: [CompoundIndexKey: Set<UUID>] = [:]
                        for (key, uuids) in persisted {
                            if var existing = restored[key] {
                                existing.formUnion(uuids)
                                restored[key] = existing
                            } else {
                                restored[key] = Set(uuids)
                            }
                            restoredEntryCount += uuids.count
                        }
                        if var current = merged[compoundKey] {
                            for (k, set) in restored {
                                if var existing = current[k] {
                                    existing.formUnion(set)
                                    current[k] = existing
                                } else {
                                    current[k] = set
                                }
                            }
                            merged[compoundKey] = current
                        } else {
                            merged[compoundKey] = restored
                        }
                    }
                    self.secondaryIndexes = merged
                    BlazeLogger.info("Restored persisted secondary indexes from layout (\(merged.count) indexes, ~\(restoredEntryCount) uuids).")
                } else {
                    // Only warn if we HAVE index definitions but they're not persisted
                    // If there are no definitions at all, this is expected for new/simple databases
                    if !layout.secondaryIndexDefinitions.isEmpty {
                        BlazeLogger.warn("No persisted secondary indexes found in layout or .indexes; using definitions only.")
                    } else {
                        BlazeLogger.trace("No secondary indexes defined (this is normal for new databases).")
                    }
                }
                // --- End: Ensure persisted secondary index data is restored correctly ---
                // --- Begin: Conditionally rebuild missing/empty secondary indexes ---
                var didRebuildAny = false
                
                // Only rebuild if we have records and definitions
                if !self.indexMap.isEmpty && !layout.secondaryIndexDefinitions.isEmpty {
                    for (compoundKey, fields) in layout.secondaryIndexDefinitions {
                        let needsRebuild: Bool = {
                            guard let inner = self.secondaryIndexes[compoundKey] else { return true }
                            return inner.isEmpty
                        }()
                        if needsRebuild {
                            var indexEntries: [CompoundIndexKey: Set<UUID>] = [:]
                            for id in self.indexMap.keys {
                                if let record = try? self._fetchNoSync(id: id) {
                                let doc = record.storage
                                let rawKey = CompoundIndexKey.fromFields(doc, fields: fields)
                                let normalizedComponents = rawKey.components.map { component -> AnyBlazeCodable in
                                    switch component {
                                    case .string(let s): return AnyBlazeCodable(s)
                                    case .int(let i): return AnyBlazeCodable(i)
                                    case .double(let d): return AnyBlazeCodable(d)
                                    case .bool(let b): return AnyBlazeCodable(b)
                                    case .date(let d): return AnyBlazeCodable(d)
                                    case .uuid(let u): return AnyBlazeCodable(u)
                                    case .data(let data): return AnyBlazeCodable(data)
                                    default: return AnyBlazeCodable(String(describing: component))
                                    }
                                }
                                let indexKey = CompoundIndexKey(normalizedComponents)
                                var set = indexEntries[indexKey] ?? Set<UUID>()
                                set.insert(id)
                                indexEntries[indexKey] = set
                            }
                        }
                        self.secondaryIndexes[compoundKey] = indexEntries
                        didRebuildAny = true
                    }
                    }
                    if didRebuildAny {
                        BlazeLogger.warn("⚠️ Rebuilding indexes during init - THIS CALLS saveLayout()!")
                        try saveLayout()
                        BlazeLogger.warn("⚠️ saveLayout() completed in init")
                    }
                }
                // --- End: Conditional rebuild ---
            } catch {
                BlazeLogger.error("Failed to load layout from disk. Deleting corrupted file and starting fresh. Error: \(error)")
                try? FileManager.default.removeItem(at: metaURL)
                self.indexMap = [:]
                self.nextPageIndex = 0
                self.secondaryIndexes = [:]
                self.cachedSearchIndex = nil
                self.cachedSearchIndexedFields = []
                try saveLayout()
            }
        } else {
            BlazeLogger.info("No layout found. Starting fresh.")
            self.indexMap = [:]
            self.nextPageIndex = 0
            self.secondaryIndexes = [:]
            self.cachedSearchIndex = nil
            self.cachedSearchIndexedFields = []
            try saveLayout()
        }
    }

/// Initializes a DynamicCollection using a preloaded StorageLayout.
init(store: PageStore, layout: StorageLayout, metaURL: URL, project: String, encryptionKey: SymmetricKey) {
    self.store = store
    self.metaURL = metaURL
    self.project = project
    self.encryptionKey = encryptionKey
    self.versionManager = VersionManager()  // Initialize MVCC
    self.indexMap = layout.indexMap
    self.nextPageIndex = layout.nextPageIndex
    // Start with persisted runtime indexes
    self.secondaryIndexes = layout.toRuntimeIndexes()
    // Cache search index
    self.cachedSearchIndex = layout.searchIndex
    self.cachedSearchIndexedFields = layout.searchIndexedFields
    // --- Begin: Rebuild missing or empty secondary indexes after reload ---
    var didRebuildAny = false
    for (compoundKey, fields) in layout.secondaryIndexDefinitions {
        let needsRebuild: Bool = {
            guard let inner = self.secondaryIndexes[compoundKey] else { return true }
            return inner.isEmpty
        }()
        if needsRebuild {
            BlazeLogger.info("Rebuilding missing compound index '\(compoundKey)' ...")
            var rebuilt: [CompoundIndexKey: Set<UUID>] = [:]
            for id in self.indexMap.keys {
                if let record = try? self._fetchNoSync(id: id) {
                    let doc = record.storage
                    let key = CompoundIndexKey.fromFields(doc, fields: fields)
                    rebuilt[key, default: []].insert(id)
                }
            }
            self.secondaryIndexes[compoundKey] = rebuilt
            didRebuildAny = true
        }
    }
    if didRebuildAny {
        do {
            try self.saveLayout()
        } catch {
            BlazeLogger.warn("Failed to save layout after index rebuild: \(error)")
        }
    }
    // --- End: Rebuild missing or empty secondary indexes ---
}

/// Creates a secondary index for a set of fields. Supports compound indexes (multi-field).
/// Example: createIndex(on: ["status", "priority"])
/// - Parameter fields: The fields to index together. Order matters for compound indexes.
/// - Note: If called multiple times with same fields/order, is idempotent.
/// - Assertion: Compound index keys are `<field1>+<field2>+...` and are used for both insertion and query.
public func createIndex(on fields: [String]) throws {
    let key = fields.joined(separator: "+")
    try queue.sync(flags: .barrier) {
        if secondaryIndexes[key] == nil {
            secondaryIndexes[key] = [:]
        }
        
        // Rebuild index for all existing records
        BlazeLogger.debug("Rebuilding index '\(key)' for \(indexMap.count) existing records")
        for (id, pageIndex) in indexMap {
            do {
                // Read and decode record (data is already decrypted by PageStore)
                let data = try store.readPage(index: pageIndex)
                guard let data = data, !data.isEmpty else {
                    BlazeLogger.debug("No data found for record \(id) at page \(pageIndex)")
                    continue
                }
                
                // Check if page is completely empty (all zeros)
                guard !data.allSatisfy({ $0 == 0 }) else {
                    BlazeLogger.debug("Empty data for record \(id) at page \(pageIndex)")
                    continue
                }
                
                // ✅ FIX: Don't trim BlazeBinary data! It contains legitimate 0x00 bytes!
                // Use BlazeBinaryDecoder (matches encoding!)
                let record = try BlazeBinaryDecoder.decode(data)
                let document = record.storage
                
                // Check if all required fields exist
                guard fields.allSatisfy({ document[$0] != nil }) else {
                    BlazeLogger.debug("Skipping record \(id) for index '\(key)' — missing one or more fields")
                    continue
                }
                
                // Build index key (same logic as insert())
                let rawKey = CompoundIndexKey.fromFields(document, fields: fields)
                let normalizedComponents = rawKey.components.map { component -> AnyBlazeCodable in
                    switch component {
                    case .string(let s): return AnyBlazeCodable(s)
                    case .int(let i): return AnyBlazeCodable(i)
                    case .double(let d): return AnyBlazeCodable(d)
                    case .bool(let b): return AnyBlazeCodable(b)
                    case .date(let d): return AnyBlazeCodable(d)
                    case .uuid(let u): return AnyBlazeCodable(u)
                    case .data(let data): return AnyBlazeCodable(data)
                    default:
                        BlazeLogger.warn("Unsupported index component type for index '\(key)'")
                        return AnyBlazeCodable("")
                    }
                }
                let indexKey = CompoundIndexKey(normalizedComponents)
                
                // Add to index (Set, not Array)
                if secondaryIndexes[key]?[indexKey] == nil {
                    secondaryIndexes[key]?[indexKey] = Set()
                }
                secondaryIndexes[key]?[indexKey]?.insert(id)
                
            } catch {
                BlazeLogger.warn("Failed to rebuild index '\(key)' for record \(id): \(error)")
            }
        }
        
        BlazeLogger.info("Rebuilt index '\(key)' with \(secondaryIndexes[key]?.count ?? 0) unique keys")
        
        // Persist the definition into the layout
        var layout = (try? StorageLayout.load(from: metaURL)) ?? StorageLayout(indexMap: indexMap, nextPageIndex: nextPageIndex, compoundIndexes: secondaryIndexes)
        layout.secondaryIndexDefinitions[key] = fields
        do {
            try layout.save(to: metaURL)
            BlazeLogger.debug("Saved index definition for '\(key)'")
        } catch {
            BlazeLogger.error("Failed to save index definition for '\(key)': \(error)")
            throw error
        }
    }
}
public func createIndex(on field: String) throws {
    try createIndex(on: [field])
}

// Insertion logic supports all configured compound indexes (multi-field).
// For every index in `secondaryIndexes`, the key is split into fields, and the correct compound index key is generated.
public func insert(_ data: BlazeDataRecord) throws -> UUID {
    // MVCC Path: Use versioned insert with snapshot isolation
    if mvccEnabled {
        return try queue.sync(flags: .barrier) {
            var document = data.storage
            let id: UUID
            if let providedID = document["id"]?.uuidValue {
                id = providedID
            } else if let stringID = document["id"]?.stringValue, let parsed = UUID(uuidString: stringID) {
                id = parsed
            } else {
                id = UUID()
                document["id"] = .uuid(id)
            }
            if document["createdAt"] == nil {
                document["createdAt"] = .date(Date())
            }
            document["project"] = .string(project)
            
            // Create MVCC transaction
            let tx = MVCCTransaction(versionManager: versionManager, pageStore: store)
            let record = BlazeDataRecord(document)
            try tx.write(recordID: id, record: record)
            try tx.commit()
            
            // Trigger automatic GC (Phase 4)
            gcManager.onTransactionCommit()
            
            // Also update old indexMap for compatibility
            if let version = versionManager.getVersion(recordID: id, snapshot: .max) {
                indexMap[id] = version.pageNumber
            }
            
            unsavedChanges += 1
            if unsavedChanges >= metadataFlushThreshold {
                try saveLayout()
                unsavedChanges = 0
            }
            
            return id
        }
    }
    
    // Legacy Path: Original single-version implementation
    return try queue.sync(flags: .barrier) {
        var document = data.storage
        let id: UUID
        if let providedID = document["id"]?.uuidValue {
            id = providedID
        } else if let stringID = document["id"]?.stringValue, let parsed = UUID(uuidString: stringID) {
            id = parsed
        } else {
            id = UUID()
            document["id"] = .uuid(id)
        }
        // Only set createdAt if not already provided
        if document["createdAt"] == nil {
            document["createdAt"] = .date(Date())
        }
        document["project"] = .string(project)
        // Use BlazeBinaryEncoder for encoding (matches decoder!)
        let encoded = try BlazeBinaryEncoder.encode(BlazeDataRecord(document))
        try store.writePage(index: nextPageIndex, plaintext: encoded)
        indexMap[id] = nextPageIndex

        // Update all configured secondary indexes in memory immediately
        for (compound, _) in secondaryIndexes {
            let fields = compound.components(separatedBy: "+")
            guard fields.allSatisfy({ document[$0] != nil }) else {
                BlazeLogger.warn("Skipping index \(compound) for id \(id) — missing one or more fields.")
                continue
            }
            let rawKey = CompoundIndexKey.fromFields(document, fields: fields)
            let normalizedComponents = rawKey.components.map { component -> AnyBlazeCodable in
                switch component {
                case .string(let s): return AnyBlazeCodable(s)
                case .int(let i): return AnyBlazeCodable(i)
                case .double(let d): return AnyBlazeCodable(d)
                case .bool(let b): return AnyBlazeCodable(b)
                case .date(let d): return AnyBlazeCodable(d)
                case .uuid(let u): return AnyBlazeCodable(u)
                case .data(let data): return AnyBlazeCodable(data)
                default: return AnyBlazeCodable(String(describing: component))
                }
            }
            let indexKey = CompoundIndexKey(normalizedComponents)
            var inner = secondaryIndexes[compound] ?? [:]
            var set = inner[indexKey] ?? Set<UUID>()
            set.insert(id)
            inner[indexKey] = set
            secondaryIndexes[compound] = inner
        }

        nextPageIndex += 1
        unsavedChanges += 1
        
        // Clear fetchAll cache after write
        clearFetchAllCache()
        
        // Batch metadata writes for performance (save every N operations)
        if unsavedChanges >= metadataFlushThreshold {
            try saveLayout()
            unsavedChanges = 0
        }
        
        // NEW: Update search index if enabled
        let record = BlazeDataRecord(document)
        try? updateSearchIndexOnInsert(record)
        
        return id
    }
}

/// Fetch a record by ID. Public version, synchronizes access via queue.
public func fetch(id: UUID) throws -> BlazeDataRecord? {
    // MVCC Path: Use snapshot isolation (CONCURRENT READS! 🚀)
    if mvccEnabled {
        // No barrier needed - reads are concurrent!
        let tx = MVCCTransaction(versionManager: versionManager, pageStore: store)
        return try tx.read(recordID: id)
    }
    
    // Legacy Path: Original single-version (serial)
    return try queue.sync {
        return try _fetchNoSync(id: id)
    }
}

/// Internal, non-synchronized version of fetch(id:). Must only be called from within queue.sync/barrier blocks.
/// Used internally to avoid nested sync calls and potential deadlocks.
internal func _fetchNoSync(id: UUID) throws -> BlazeDataRecord? {
    BlazeLogger.debug("Attempting to fetch record with ID: \(id)")
    guard let index = indexMap[id] else {
        return nil
    }
    do {
        let data = try store.readPage(index: index)
        guard let data = data else {
            BlazeLogger.warn("No data found for page index \(index)")
            return nil
        }
        // Check if page is completely empty (all zeros)
        if data.allSatisfy({ $0 == 0 }) {
            return nil
        }
        // ✅ FIX: Don't trim BlazeBinary data! It contains legitimate 0x00 bytes!
        // Use BlazeBinaryDecoder (not JSON!)
        let record = try BlazeBinaryDecoder.decode(data)
        BlazeLogger.info("Successfully fetched record with ID: \(id)")
        return record
    } catch {
        BlazeLogger.error("Failed to decode record for id \(id): \(error)")
        if let pageIndex = indexMap[id] {
            BlazeLogger.debug("   Page index: \(pageIndex)")
        }
        return nil
    }
}

public func fetchAll() throws -> [BlazeDataRecord] {
    // MVCC Path: Fetch all visible records at current snapshot
    if mvccEnabled {
        let tx = MVCCTransaction(versionManager: versionManager, pageStore: store)
        return try tx.readAll()
    }
    
    // OPTIMIZED: Use parallel fetch for massive speedup!
    return try _fetchAllOptimized()
}

public func fetchAll(byProject project: String) throws -> [BlazeDataRecord] {
    return try queue.sync {
        var records: [BlazeDataRecord] = []
        for id in indexMap.keys {
            guard let record = try? _fetchNoSync(id: id) else { continue }
            if let storedProject = record.storage["project"]?.stringValue, storedProject == project {
                records.append(record)
            }
        }
        return records
    }
}

public func update(id: UUID, with data: BlazeDataRecord) throws {
    // MVCC Path: Create new version for update
    if mvccEnabled {
        try queue.sync(flags: .barrier) {
            // Read current version
            let tx = MVCCTransaction(versionManager: versionManager, pageStore: store)
            guard let current = try tx.read(recordID: id) else {
                throw BlazeDBError.recordNotFound(id: id)
            }
            
            // Merge updates with current data
            var merged = current.storage
            for (key, value) in data.storage {
                merged[key] = value
            }
            
            // Write new version
            let updatedRecord = BlazeDataRecord(merged)
            try tx.write(recordID: id, record: updatedRecord)
            try tx.commit()
            
            // Trigger automatic GC (Phase 4)
            gcManager.onTransactionCommit()
            
            // Update indexMap
            if let version = versionManager.getVersion(recordID: id, snapshot: .max) {
                indexMap[id] = version.pageNumber
            }
            
            unsavedChanges += 1
            if unsavedChanges >= metadataFlushThreshold {
                try saveLayout()
                unsavedChanges = 0
            }
        }
        return
    }
    
    // Legacy Path: Original implementation
    try queue.sync(flags: .barrier) {
        try _updateNoSync(id: id, with: data)
    }
}

public func contains(_ id: UUID) -> Bool {
    // MVCC Path: Check if record is visible at current snapshot
    if mvccEnabled {
        let snapshot = versionManager.getCurrentVersion()
        return versionManager.getVersion(recordID: id, snapshot: snapshot) != nil
    }
    
    // Legacy Path: Use indexMap
    return queue.sync {
        return indexMap[id] != nil
    }
}

public func filter(_ isMatch: (BlazeDataRecord) -> Bool) throws -> [BlazeDataRecord] {
    // OPTIMIZED: Use parallel filter for large datasets
    return try filterOptimized(isMatch)
}

/// Runs a BlazeQueryLegacy over all records, returning those for which the query applies.
public func runQuery(_ query: BlazeQueryLegacy<[String: BlazeDocumentField]>) throws -> [BlazeDataRecord] {
    return try queue.sync {
        let records = try fetchAll()
        return query.apply(to: records.map { $0.storage }).compactMap { dict in
            BlazeDataRecord(dict)
        }
    }
}

public func runQueryChained(_ query: BlazeQueryLegacy<[String: BlazeDocumentField]>) throws -> [BlazeDataRecord] {
    return try queue.sync {
        let records = try fetchAll()
        return query.apply(to: records.map { $0.storage }).compactMap { dict in
            BlazeDataRecord(dict)
        }
    }
}

public func runQuerySorted(_ query: BlazeQueryLegacy<[String: BlazeDocumentField]>) throws -> [BlazeDataRecord] {
    return try queue.sync {
        let records = try fetchAll()
        return query.apply(to: records.map { $0.storage }).compactMap { dict in
            BlazeDataRecord(dict)
        }
    }
}

public func runQueryRanged(_ query: BlazeQueryLegacy<[String: BlazeDocumentField]>) throws -> [BlazeDataRecord] {
    return try queue.sync {
        let records = try fetchAll()
        return query.apply(to: records.map { $0.storage }).compactMap { dict in
            BlazeDataRecord(dict)
        }
    }
}

public func fetchAllSorted(by key: String, ascending: Bool = true) throws -> [BlazeDataRecord] {
    return try queue.sync {
        let records = try fetchAll()
        return records.sorted {
            guard let lhs = $0.storage[key], let rhs = $1.storage[key] else { return false }
            if ascending {
                return String(describing: lhs) < String(describing: rhs)
            } else {
                return String(describing: lhs) > String(describing: rhs)
            }
        }
    }
}

internal func _deleteNoSync(id: UUID) throws {
    guard let _ = indexMap[id] else { return }

    // 🔒 Atomic delete: backup state before modifications
    let indexBackup = secondaryIndexes
    let indexMapBackup = indexMap
    
    do {
        // Remove from all indexes (persisting mutations)
        if let record = try? _fetchNoSync(id: id) {
            let oldDoc = record.storage
            for (compound, _) in secondaryIndexes {
                let fields = compound.components(separatedBy: "+")
                let oldKey = CompoundIndexKey.fromFields(oldDoc, fields: fields)
                if var inner = secondaryIndexes[compound] {
                    if var set = inner[oldKey] {
                        set.remove(id)
                        if set.isEmpty {
                            inner.removeValue(forKey: oldKey)
                        } else {
                            inner[oldKey] = set
                        }
                        secondaryIndexes[compound] = inner
                    }
                }
            }
        }

        indexMap[id] = nil
        
        unsavedChanges += 1
        if unsavedChanges >= metadataFlushThreshold {
            try saveLayout()
            unsavedChanges = 0
        }
        
        // NEW: Update search index if enabled
        try? updateSearchIndexOnDelete(id)
        
        // Success - changes persisted
    } catch {
        // 🔒 Restore state on failure
        BlazeLogger.warn("Delete failed, restoring index state: \(error)")
        secondaryIndexes = indexBackup
        indexMap = indexMapBackup
        throw error
    }
}

public func delete(id: UUID) throws {
    // MVCC Path: Mark version as deleted
    if mvccEnabled {
        try queue.sync(flags: .barrier) {
            let tx = MVCCTransaction(versionManager: versionManager, pageStore: store)
            try tx.delete(recordID: id)
            try tx.commit()
            
            // Trigger automatic GC (Phase 4)
            gcManager.onTransactionCommit()
            
            // Update indexMap (remove from index)
            indexMap.removeValue(forKey: id)
            
            unsavedChanges += 1
            if unsavedChanges >= metadataFlushThreshold {
                try saveLayout()
                unsavedChanges = 0
            }
        }
        return
    }
    
    // Legacy Path: Original implementation
    try queue.sync(flags: .barrier) {
        try _deleteNoSync(id: id)
    }
}

/// Destroys the entire collection, including data and layout files.
public func destroy() throws {
    try queue.sync(flags: .barrier) {
        try? FileManager.default.removeItem(at: store.fileURL)
        try? FileManager.default.removeItem(at: metaURL)
        indexMap = [:]
        nextPageIndex = 0
        secondaryIndexes = [:]
    }
}

/// Fetch records using a compound index defined on multiple fields.
/// - Parameters:
///   - fields: List of fields that were indexed together (order matters).
///   - values: List of values to match (order and count must match fields).
/// - Returns: Records matching all indexed fields and values.
/// - Example: fetch(byIndexedFields: ["status", "priority"], values: ["inProgress", 5])
public func fetch(byIndexedFields fields: [String], values: [AnyHashable]) throws -> [BlazeDataRecord] {
    guard fields.count == values.count else {
        BlazeLogger.error("Fields and values count mismatch: \(fields.count) fields, \(values.count) values")
        throw BlazeDBError.transactionFailed("Fields and values count mismatch: \(fields.count) fields, \(values.count) values")
    }
    let compoundKey = fields.joined(separator: "+")

    // Normalize values into AnyBlazeCodable (consistent with insert logic)
    let normalizedComponents: [AnyBlazeCodable] = values.map { value in
        switch value {
        case let s as String: return AnyBlazeCodable(s)
        case let i as Int: return AnyBlazeCodable(i)
        case let d as Double: return AnyBlazeCodable(d)
        case let b as Bool: return AnyBlazeCodable(b)
        case let date as Date: return AnyBlazeCodable(date)
        case let uuid as UUID: return AnyBlazeCodable(uuid)
        case let data as Data: return AnyBlazeCodable(data)
        default: return AnyBlazeCodable(String(describing: value))
        }
    }

    let indexKey = CompoundIndexKey(normalizedComponents)

    return try queue.sync {
        guard let uuids = secondaryIndexes[compoundKey]?[indexKey], !uuids.isEmpty else {
            return []
        }
        return try uuids.compactMap { try _fetchNoSync(id: $0) }
    }
}

public func persist() throws {
    try queue.sync(flags: .barrier) {
        // First, ensure all page writes are flushed to disk
        try store.synchronize()
        
        // Then save the metadata
        try saveLayout()
        unsavedChanges = 0
    }
}

internal func saveLayout() throws {
    // Load existing layout to preserve encodingFormat and other fields!
    var layout = (try? StorageLayout.load(from: metaURL)) ?? StorageLayout(
        indexMap: indexMap, 
        nextPageIndex: nextPageIndex, 
        compoundIndexes: secondaryIndexes,
        searchIndex: cachedSearchIndex,
        searchIndexedFields: cachedSearchIndexedFields
    )
    
    // Update fields (preserving encodingFormat!)
    layout.indexMap = indexMap
    layout.nextPageIndex = nextPageIndex
    layout.secondaryIndexes = secondaryIndexes.mapValues { inner in
        inner.mapValues { Array($0) }
    }
    layout.searchIndex = cachedSearchIndex
    layout.searchIndexedFields = cachedSearchIndexedFields
    
    do {
        try layout.save(to: metaURL)
        BlazeLogger.debug("Saved layout: \(indexMap.count) records, nextPageIndex=\(nextPageIndex), \(secondaryIndexes.count) indexes")
    } catch {
        BlazeLogger.error("Failed to save layout: \(error)")
        throw error
    }
}

// Ensure unsaved changes are flushed on cleanup
deinit {
    if unsavedChanges > 0 {
        do {
            try saveLayout()
            BlazeLogger.debug("Flushed \(unsavedChanges) unsaved changes during deinit")
        } catch {
            BlazeLogger.error("⚠️ CRITICAL: Failed to flush \(unsavedChanges) changes during deinit: \(error)")
            BlazeLogger.error("⚠️ Metadata may be inconsistent. Call db.persist() explicitly before deallocation.")
        }
    }
}

/// Dumps the raw CBOR data for each page index in the collection.
public func rawDump() throws -> [Int: Data] {
    var result: [Int: Data] = [:]
    for (_, index) in indexMap {
        let data = try store.readPage(index: index)
        result[index] = data
    }
    return result
}

/// Soft-deletes a record by marking it as deleted.
public func softDelete(id: UUID) throws {
    try queue.sync(flags: .barrier) {
        guard let record = try _fetchNoSync(id: id) else { return }
        var storage = record.storage
        storage["isDeleted"] = .bool(true)
        try _updateNoSync(id: id, with: BlazeDataRecord(storage))
    }
}

/// Permanently removes all soft-deleted records from disk.
public func purge() throws {
    try queue.sync(flags: .barrier) {
        let allIDs = Array(indexMap.keys)
        for id in allIDs {
            if let record = try? _fetchNoSync(id: id),
               let isDeleted = record.storage["isDeleted"]?.boolValue, isDeleted {
                try? _deleteNoSync(id: id)
            }
        }
    }
}

internal func _updateNoSync(id: UUID, with data: BlazeDataRecord) throws {
    guard let pageIndex = indexMap[id] else {
        throw NSError(domain: "DynamicCollection", code: 404, userInfo: [NSLocalizedDescriptionKey: "Record not found"])
    }

    // 🔒 Atomic update: backup state before modifications
    let indexBackup = secondaryIndexes
    
    do {
        // Remove old keys
        if let record = try? _fetchNoSync(id: id) {
            let oldDoc = record.storage
            for (compound, _) in secondaryIndexes {
                let fields = compound.components(separatedBy: "+")
                let oldKey = CompoundIndexKey.fromFields(oldDoc, fields: fields)
                if var inner = secondaryIndexes[compound] {
                    if var set = inner[oldKey] {
                        set.remove(id)
                        if set.isEmpty {
                            inner.removeValue(forKey: oldKey)
                        } else {
                            inner[oldKey] = set
                        }
                        secondaryIndexes[compound] = inner
                    }
                }
            }
        }

        // Apply new data
        var document = data.storage
        document["id"] = .uuid(id)
        document["updatedAt"] = .date(Date())

        // Add to indexes
        for (compound, _) in secondaryIndexes {
            let fields = compound.components(separatedBy: "+")
            let indexKey = CompoundIndexKey.fromFields(document, fields: fields)
            var inner = secondaryIndexes[compound] ?? [:]
            var set = inner[indexKey] ?? Set<UUID>()
            set.insert(id)
            inner[indexKey] = set
            secondaryIndexes[compound] = inner
        }

        // 🔒 Write to disk BEFORE committing index changes
        // Use BlazeBinaryEncoder for encoding (matches decoder!)
        let encoded = try BlazeBinaryEncoder.encode(BlazeDataRecord(document))
        try store.writePage(index: pageIndex, plaintext: encoded)
        
        // Clear fetchAll cache after write
        clearFetchAllCache()
        
        unsavedChanges += 1
        if unsavedChanges >= metadataFlushThreshold {
            try saveLayout()
            unsavedChanges = 0
        }
        
        // NEW: Update search index if enabled
        let updatedRecord = BlazeDataRecord(document)
        try? updateSearchIndexOnUpdate(updatedRecord)
        
        // Success - index changes are persisted
    } catch {
        // 🔒 Restore index state on failure
        BlazeLogger.warn("Update failed, restoring index state: \(error)")
        secondaryIndexes = indexBackup
        throw error
    }
}

public func query() -> BlazeQueryContext {
    return BlazeQueryContext(collection: self)
}
}

// MARK: - MetaStore Conformance
extension DynamicCollection: MetaStore {
    public func fetchMeta() throws -> [String: BlazeDocumentField] {
        let layout = try StorageLayout.load(from: metaURLPath)
        return layout.metaData
    }

    public func updateMeta(_ newMeta: [String: BlazeDocumentField]) throws {
        var layout = try StorageLayout.load(from: metaURLPath)
        layout.metaData = newMeta
        try layout.save(to: metaURLPath)
    }
}

public struct BlazeQueryContext {
private let collection: DynamicCollection
private let query = BlazeQueryLegacy<[String: BlazeDocumentField]>()

public init(collection: DynamicCollection) {
    self.collection = collection
}

public func `where`(_ field: String) -> BlazeFieldQueryBuilder<[String: BlazeDocumentField]> {
    return BlazeFieldQueryBuilder(builder: query, field: field)
}

public func execute() throws -> [BlazeDataRecord] {
    let all = try collection.fetchAll()
    let filtered = query.apply(to: all.map { $0.storage })
    return filtered.map { BlazeDataRecord($0) }
}
}

// Placeholder for BlazeFieldQueryBuilder<T>
public struct BlazeFieldQueryBuilder<T> {
private let builder: BlazeQueryLegacy<T>
private var field: String?

public init(builder: BlazeQueryLegacy<T>, field: String? = nil) {
    self.builder = builder
    self.field = field
}

// Example function to allow chaining (customize later)
public func equals(_ value: BlazeDocumentField) -> BlazeQueryLegacy<T> {
    var copy = builder
    if let field = self.field {
        copy = copy.addPredicate { record in
            guard let dict = record as? [String: BlazeDocumentField] else { return false }
            return dict[field] == value
        }
    }
    return copy
}
}

/// Persist the current layout to disk.

// MARK: - DynamicCollection Metrics

extension DynamicCollection {
public var pageCount: Int {
    return queue.sync {
        indexMap.values.unique.count
    }
}

public var orphanedPageCount: Int {
    return queue.sync {
        let usedPages = Set(indexMap.values)
        let allPages = Set(0..<nextPageIndex)
        return allPages.subtracting(usedPages).count
    }
}

public var recordCount: Int {
    return queue.sync {
        indexMap.count
    }
}

public var largestRecordSize: Int {
    return queue.sync {
        return (try? fetchAll().map { record in
            (try? BlazeBinaryEncoder.encode(record).count) ?? 0
        }.max() ?? 0) ?? 0
    }
}

public var pageWarningCount: Int {
    return queue.sync {
        do {
            let all = try fetchAll()
            let count = all.filter {
                guard let encodedSize = try? BlazeBinaryEncoder.encode($0).count else {
                    return false
                }
                return encodedSize >= 3900
            }.count
            return count
        } catch {
            return 0
        }
    }
}

/**
 Fetches all records where the value of a specific field (that has a secondary index) equals the provided value.
 
 - Parameters:
    - field: The name of the field to query. This field **must** have a secondary index created via `createIndex(on:)` beforehand, or the lookup will fail.
    - value: The value to search for. Must be `AnyHashable` and match the type of the indexed field.
 
 - Returns: An array of `BlazeDataRecord` objects whose `field` equals `value`. Returns an empty array if no records match or if the index or value is not present.
 
 - Note: This method is efficient as it leverages the secondary index. If the index for the field does not exist, this will always return an empty array.
*/
public func fetch(byIndexedField field: String, value: AnyHashable) throws -> [BlazeDataRecord] {
    // Synchronize access to collection state.
    return try queue.sync {
        // Build list of normalized values to try (handle cross-type storage)
        var valuesToTry: [AnyBlazeCodable] = []
        
        switch value {
        case let s as String:
            valuesToTry.append(AnyBlazeCodable(s))
            // Try as base64-encoded Data
            if let data = Data(base64Encoded: s) {
                valuesToTry.append(AnyBlazeCodable(data))
            }
        case let i as Int:
            valuesToTry.append(AnyBlazeCodable(i))
            // Ints might be stored as Doubles
            valuesToTry.append(AnyBlazeCodable(Double(i)))
            // Only try Bool conversion for 0 and 1
            if i == 0 {
                valuesToTry.append(AnyBlazeCodable(false))
            } else if i == 1 {
                valuesToTry.append(AnyBlazeCodable(true))
            }
        case let d as Double:
            valuesToTry.append(AnyBlazeCodable(d))
            // Doubles might be stored as Ints (if whole number)
            if d.truncatingRemainder(dividingBy: 1.0) == 0 {
                valuesToTry.append(AnyBlazeCodable(Int(d)))
            }
        case let b as Bool:
            valuesToTry.append(AnyBlazeCodable(b))
            // Bools might be stored as Ints
            valuesToTry.append(AnyBlazeCodable(b ? 1 : 0))
        case let date as Date:
            valuesToTry.append(AnyBlazeCodable(date))
            // Dates might be stored as Double (timestamp)
            valuesToTry.append(AnyBlazeCodable(date.timeIntervalSinceReferenceDate))
            // Dates might be stored as Int (whole-second timestamp)
            let timestamp = date.timeIntervalSinceReferenceDate
            if timestamp.truncatingRemainder(dividingBy: 1.0) == 0 {
                valuesToTry.append(AnyBlazeCodable(Int(timestamp)))
            }
        case let uuid as UUID:
            valuesToTry.append(AnyBlazeCodable(uuid))
            // UUIDs might be stored as Strings
            valuesToTry.append(AnyBlazeCodable(uuid.uuidString))
        case let data as Data:
            valuesToTry.append(AnyBlazeCodable(data))
            // Data might be stored as base64 String
            valuesToTry.append(AnyBlazeCodable(data.base64EncodedString()))
        default:
            BlazeLogger.warn("Unsupported index value type: \(type(of: value))")
            return []
        }
        
        // Try all normalized forms and collect all matching UUIDs
        var matchedUUIDs = Set<UUID>()
        for normalizedValue in valuesToTry {
            let indexKey = CompoundIndexKey([normalizedValue])
            if let uuids = secondaryIndexes[field]?[indexKey] {
                matchedUUIDs.formUnion(uuids)
            }
        }
        
        guard !matchedUUIDs.isEmpty else {
            return []
        }
        
        return try matchedUUIDs.compactMap { try _fetchNoSync(id: $0) }
    }
}

public func fetchAllIDs() throws -> [UUID] {
    return try queue.sync {
        return Array(indexMap.keys)
    }
}

// MARK: - Pagination Support

/// Fetch a page of records with offset and limit
/// - Parameters:
///   - offset: Number of records to skip
///   - limit: Maximum number of records to return
/// - Returns: Array of records for the requested page
public func fetchPage(offset: Int, limit: Int) throws -> [BlazeDataRecord] {
    return try queue.sync {
        let allIDs = Array(indexMap.keys)
        let sortedIDs = allIDs.sorted()  // Deterministic ordering
        
        guard offset < sortedIDs.count else {
            return []  // Offset beyond data
        }
        
        let endIndex = min(offset + limit, sortedIDs.count)
        let pageIDs = Array(sortedIDs[offset..<endIndex])
        
        return try pageIDs.compactMap { id in
            try _fetchNoSync(id: id)
        }
    }
}

/// Fetch records by a batch of IDs (efficient for pagination with known IDs)
/// - Parameter ids: Array of UUIDs to fetch
/// - Returns: Dictionary mapping UUID to record (nil for missing records)
public func fetchBatch(ids: [UUID]) throws -> [UUID: BlazeDataRecord] {
    return try queue.sync {
        var results: [UUID: BlazeDataRecord] = [:]
        for id in ids {
            if let record = try? _fetchNoSync(id: id) {
                results[id] = record
            }
        }
        return results
    }
}

/// Get total count of records without loading them all
/// - Returns: Total number of records in the collection
public func count() -> Int {
    // MVCC Path: Count visible records at current snapshot
    if mvccEnabled {
        let snapshot = versionManager.getCurrentVersion()
        let visibleIDs = versionManager.getAllVisibleRecordIDs(snapshot: snapshot)
        return visibleIDs.count
    }
    
    // Legacy Path: Use indexMap
    return queue.sync {
        return indexMap.count
    }
}

// MARK: - JOIN Operations

/// Join this collection with another collection
/// - Parameters:
///   - other: The collection to join with
///   - foreignKey: Field name in this collection that references the other collection
///   - primaryKey: Field name in the other collection to match against (typically "id")
///   - type: Type of join (inner, left, right, full)
/// - Returns: Array of joined records
/// - Note: Uses batch fetching for optimal performance (O(N+M) not O(N*M))
public func join(
    with other: DynamicCollection,
    on foreignKey: String,
    equals primaryKey: String = "id",
    type: JoinType = .inner
) throws -> [JoinedRecord] {
    return try queue.sync {
        BlazeLogger.debug("Performing \(type) join on \(foreignKey) = \(primaryKey)")
        
        // Step 1: Fetch all records from left (this) collection
        let leftRecords = try _fetchAllNoSync()
        
        // Step 2: Determine what to fetch from right collection
        let rightRecords: [UUID: BlazeDataRecord]
        
        if type == .right || type == .full {
            // For RIGHT/FULL joins, fetch ALL right records
            let allRightRecords = try other._fetchAllNoSync()
            
            // Build dictionary, handling potential duplicates
            var tempDict: [UUID: BlazeDataRecord] = [:]
            for record in allRightRecords {
                guard let id = record.storage["id"]?.uuidValue else { continue }
                // If duplicate, keep the first one (or use uniquingKeysWith to keep last)
                if tempDict[id] == nil {
                    tempDict[id] = record
                } else {
                    BlazeLogger.warn("Duplicate ID \(id) found in right collection during join - using first occurrence")
                }
            }
            rightRecords = tempDict
            BlazeLogger.debug("Fetched ALL \(rightRecords.count) right records for \(type) join")
        } else {
            // For INNER/LEFT joins, only fetch right records with matching foreign keys
            let foreignKeyValues = Set(leftRecords.compactMap { record -> UUID? in
                guard let field = record.storage[foreignKey] else { return nil }
                
                // Support both UUID and String representations
                switch field {
                case .uuid(let uuid):
                    return uuid
                case .string(let str):
                    return UUID(uuidString: str)
                default:
                    return nil
                }
            })
            
            BlazeLogger.debug("Collected \(foreignKeyValues.count) unique foreign key values for batch fetch")
            
            // Batch fetch from right collection
            rightRecords = try other.fetchBatch(ids: Array(foreignKeyValues))
        }
        
        // Step 4: Build joined results based on join type
        var results: [JoinedRecord] = []
        var matchedRightIDs = Set<UUID>()
        
        for leftRecord in leftRecords {
            guard let field = leftRecord.storage[foreignKey] else {
                // No foreign key in left record
                if type == .left || type == .full {
                    results.append(JoinedRecord(left: leftRecord, right: nil))
                }
                continue
            }
            
            // Extract foreign key value
            let foreignKeyValue: UUID?
            switch field {
            case .uuid(let uuid):
                foreignKeyValue = uuid
            case .string(let str):
                foreignKeyValue = UUID(uuidString: str)
            default:
                foreignKeyValue = nil
            }
            
            guard let fkValue = foreignKeyValue else {
                if type == .left || type == .full {
                    results.append(JoinedRecord(left: leftRecord, right: nil))
                }
                continue
            }
            
            // Look up right record
            if let rightRecord = rightRecords[fkValue] {
                // Match found!
                results.append(JoinedRecord(left: leftRecord, right: rightRecord))
                matchedRightIDs.insert(fkValue)
            } else {
                // No match
                if type == .left || type == .full {
                    results.append(JoinedRecord(left: leftRecord, right: nil))
                }
            }
        }
        
        // Step 5: For right/full joins, add unmatched right records
        if type == .right || type == .full {
            BlazeLogger.debug("Adding unmatched right records. Total right: \(rightRecords.count), Matched: \(matchedRightIDs.count)")
            for (rightID, rightRecord) in rightRecords {
                if !matchedRightIDs.contains(rightID) {
                    // Create empty left record for unmatched right
                    let emptyLeft = BlazeDataRecord([:])
                    results.append(JoinedRecord(left: emptyLeft, right: rightRecord))
                    BlazeLogger.debug("Added unmatched right record: \(rightID)")
                }
            }
        }
        
        BlazeLogger.info("Join complete: \(results.count) results from \(leftRecords.count) left × \(rightRecords.count) right")
        
        return results
    }
}

/// Internal helper: Fetch all records without synchronization (already in queue.sync)
internal func _fetchAllNoSync() throws -> [BlazeDataRecord] {
    var records: [BlazeDataRecord] = []
    for id in indexMap.keys {
        if let record = try? _fetchNoSync(id: id) {
            records.append(record)
        }
    }
    return records
}

// MARK: - Query Builder

/// Create a query builder for this collection
/// - Returns: QueryBuilder instance for chainable query construction
///
/// Example:
/// ```swift
/// let results = try collection.query()
///     .where("status", equals: .string("open"))
///     .where("priority", greaterThan: .int(2))
///     .orderBy("created_at", descending: true)
///     .limit(10)
///     .execute()
/// ```
public func query() -> QueryBuilder {
    return QueryBuilder(collection: self)
}
}

private extension Sequence where Element: Hashable {
var unique: [Element] {
    Array(Set(self))
}
}

// MARK: - StorageLayout Index Conversion helpers
extension StorageLayout {
func toRuntimeIndexes() -> [String: [CompoundIndexKey: Set<UUID>]] {
    return secondaryIndexes.mapValues { innerDict in
        Dictionary(uniqueKeysWithValues: innerDict.map { key, value in
            (key, Set(value))
        })
    }
}
}

