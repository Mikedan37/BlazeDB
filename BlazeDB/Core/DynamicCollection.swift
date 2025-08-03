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
    case .array(let v): return v
    case .dictionary(let v): return v
    }
}

/// Attempts to decode a single value container into one of the supported types.
/// The types are tried in order of likelihood/simplicity.
public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    // Attempt each type in turn. First match wins.
    if let v = try? container.decode(String.self) {
        self = .string(v)
    } else if let v = try? container.decode(Int.self) {
        self = .int(v)
    } else if let v = try? container.decode(Double.self) {
        self = .double(v)
    } else if let v = try? container.decode(Bool.self) {
        self = .bool(v)
    } else if let v = try? container.decode(Date.self) {
        self = .date(v)
    } else if let v = try? container.decode(UUID.self) {
        self = .uuid(v)
    } else if let v = try? container.decode([BlazeDocumentField].self) {
        self = .array(v)
    } else if let v = try? container.decode([String: BlazeDocumentField].self) {
        self = .dictionary(v)
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
    case .array(let v): try container.encode(v)
    case .dictionary(let v): try container.encode(v)
    }
}
}

extension BlazeDocumentField {
var stringValue: String? {
    if case let .string(value) = self { return value }
    return nil
}

var intValue: Int? {
    if case let .int(value) = self { return value }
    return nil
}

var uuidValue: UUID? {
    if case let .uuid(value) = self { return value }
    return nil
}

var boolValue: Bool? {
    if case let .bool(value) = self { return value }
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
        // Try to get the value, otherwise empty string
        if let val = document[field]?.value as? AnyHashable {
            return val
        } else {
            return "" as AnyHashable // fallback to empty string if not found
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
private var indexMap: [UUID: Int] = [:]
internal let store: PageStore
private let metaURL: URL
private var nextPageIndex: Int = 0
private var secondaryIndexes: [String: [CompoundIndexKey: Set<UUID>]] = [:]
private let project: String
private let queue = DispatchQueue(label: "com.yourorg.blazedb.dynamiccollection", attributes: .concurrent)
private let encryptionKey: SymmetricKey

/// Publicly expose the metaURL as `meta`
public var meta: URL {
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
    let layoutExists = FileManager.default.fileExists(atPath: metaURL.path)

    if layoutExists {
        do {
            let layout = try StorageLayout.load(from: metaURL)
            self.indexMap = layout.indexMap
            self.nextPageIndex = layout.nextPageIndex
            self.secondaryIndexes = layout.toRuntimeIndexes()
        } catch {
            print("❌ Failed to load layout from disk. Deleting corrupted file and starting fresh. Error: \(error)")
            try? FileManager.default.removeItem(at: metaURL)
            self.indexMap = [:]
            self.nextPageIndex = 0
            self.secondaryIndexes = [:]
            try saveLayout()
        }
    } else {
        print("🆕 No layout found. Starting fresh.")
        self.indexMap = [:]
        self.nextPageIndex = 0
        self.secondaryIndexes = [:]
        try saveLayout()
    }
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
    }
}
public func createIndex(on field: String) throws {
    try createIndex(on: [field])
}

// Insertion logic supports all configured compound indexes (multi-field).
// For every index in `secondaryIndexes`, the key is split into fields, and the correct compound index key is generated.
public func insert(_ data: BlazeDataRecord) throws -> UUID {
    return try queue.sync(flags: .barrier) {
        let id = UUID()
        print("🪪 Inserting record with ID: \(id)")
        var document: [String: BlazeDocumentField] = [:]
        for (key, value) in data.storage {
            document[key] = value
        }
        document["id"] = .uuid(id)
        document["createdAt"] = .date(Date())
        document["project"] = .string(project)
        let encoded = try JSONEncoder().encode(document)
        try store.writePage(index: nextPageIndex, plaintext: encoded)
        indexMap[id] = nextPageIndex
        // For each index (including compound), update the index with the correct key.
        for (compound, _) in secondaryIndexes {
            let fields = compound.components(separatedBy: "+")
            let indexKey = CompoundIndexKey.fromFields(document, fields: fields)
            secondaryIndexes[compound, default: [:]][indexKey, default: []].insert(id)
        }
        nextPageIndex += 1
        try saveLayout()
        return id
    }
}

/// Fetch a record by ID. Public version, synchronizes access via queue.
public func fetch(id: UUID) throws -> BlazeDataRecord? {
    return try queue.sync {
        return try _fetchNoSync(id: id)
    }
}

/// Internal, non-synchronized version of fetch(id:). Must only be called from within queue.sync/barrier blocks.
/// Used internally to avoid nested sync calls and potential deadlocks.
private func _fetchNoSync(id: UUID) throws -> BlazeDataRecord? {
    print("🔍 Attempting to fetch record with ID: \(id)")
    guard let index = indexMap[id] else { return nil }
    do {
        let data = try store.readPage(index: index)
        // Treat empty or zero-filled data as "not found"
        let trimmedData = data.prefix { $0 != 0 }
        if trimmedData.isEmpty { return nil }
        let decoded = try JSONDecoder().decode([String: BlazeDocumentField].self, from: Data(trimmedData))
        print("✅ Successfully fetched record with ID: \(id)")
        return BlazeDataRecord(decoded)
    } catch {
        print("❌ Failed to decode record for id \(id): \(error)")
        return nil
    }
}

public func fetchAll() throws -> [BlazeDataRecord] {
    return try queue.sync {
        print("📦 Fetching all records. indexMap contains \(indexMap.count) entries.")
        var records: [BlazeDataRecord] = []
        for id in indexMap.keys {
            guard let record = try? _fetchNoSync(id: id) else { continue }
            records.append(record)
        }
        return records
    }
}

public func fetchAll(byProject project: String) throws -> [BlazeDataRecord] {
    return try queue.sync {
        print("📦 Fetching all records for project: \(project)")
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
    try queue.sync(flags: .barrier) {
        guard let pageIndex = indexMap[id] else {
            throw NSError(domain: "DynamicCollection", code: 404, userInfo: [NSLocalizedDescriptionKey: "Record not found"])
        }
        // Remove old keys from all indexes
        if let oldDoc = try? _fetchNoSync(id: id)?.storage {
            for (compound, _) in secondaryIndexes {
                let fields = compound.components(separatedBy: "+")
                let oldKey = CompoundIndexKey.fromFields(oldDoc, fields: fields)
                secondaryIndexes[compound]?[oldKey]?.remove(id)
                if let set = secondaryIndexes[compound]?[oldKey], set.isEmpty {
                    secondaryIndexes[compound]?.removeValue(forKey: oldKey)
                }
            }
        }
        var document = data.storage
        document["id"] = .string(id.uuidString)
        document["updatedAt"] = .string(Date().description)
        // Add to all indexes
        for (compound, _) in secondaryIndexes {
            let fields = compound.components(separatedBy: "+")
            let indexKey = CompoundIndexKey.fromFields(document, fields: fields)
            secondaryIndexes[compound, default: [:]][indexKey, default: []].insert(id)
        }
        let encoded = try JSONEncoder().encode(document)
        try store.writePage(index: pageIndex, plaintext: encoded)
        try saveLayout()
    }
}

public func contains(_ id: UUID) -> Bool {
    return queue.sync {
        return indexMap[id] != nil
    }
}

public func filter(_ isMatch: (BlazeDataRecord) -> Bool) throws -> [BlazeDataRecord] {
    return try queue.sync {
        return try fetchAll().filter(isMatch)
    }
}

/// Runs a BlazeQuery over all records, returning those for which the query applies.
public func runQuery(_ query: BlazeQuery<[String: BlazeDocumentField]>) throws -> [BlazeDataRecord] {
    return try queue.sync {
        let records = try fetchAll()
        return query.apply(to: records.map { $0.storage }).compactMap { dict in
            BlazeDataRecord(dict)
        }
    }
}

public func runQueryChained(_ query: BlazeQuery<[String: BlazeDocumentField]>) throws -> [BlazeDataRecord] {
    return try queue.sync {
        let records = try fetchAll()
        return query.apply(to: records.map { $0.storage }).compactMap { dict in
            BlazeDataRecord(dict)
        }
    }
}

public func runQuerySorted(_ query: BlazeQuery<[String: BlazeDocumentField]>) throws -> [BlazeDataRecord] {
    return try queue.sync {
        let records = try fetchAll()
        return query.apply(to: records.map { $0.storage }).compactMap { dict in
            BlazeDataRecord(dict)
        }
    }
}

public func runQueryRanged(_ query: BlazeQuery<[String: BlazeDocumentField]>) throws -> [BlazeDataRecord] {
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

public func delete(id: UUID) throws {
    try queue.sync(flags: .barrier) {
        guard let _ = indexMap[id] else { return }
        // Remove from all indexes (AGGRESSIVE CLEANUP)
        if let oldDoc = try? _fetchNoSync(id: id)?.storage {
            for (compound, _) in secondaryIndexes {
                let fields = compound.components(separatedBy: "+")
                let oldKey = CompoundIndexKey.fromFields(oldDoc, fields: fields)
                secondaryIndexes[compound]?[oldKey]?.remove(id)
                if let set = secondaryIndexes[compound]?[oldKey], set.isEmpty {
                    secondaryIndexes[compound]?.removeValue(forKey: oldKey)
                }
            }
        }
        indexMap[id] = nil
        try saveLayout()
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
/// Fetches all records matching a compound (multi-field) index.
/// - Parameters:
///   - fields: List of fields that were indexed together (order matters).
///   - values: List of values to match (order and count must match fields).
/// - Returns: Records matching all indexed fields and values.
/// - Example: fetch(byIndexedFields: ["status", "priority"], values: ["inProgress", 5])
/// - Note: Compound index lookups require both the fields and values in the same order as the index was created.
/// - Assertion: If fields.count != values.count, the lookup will not match any records.
public func fetch(byIndexedFields fields: [String], values: [AnyHashable]) throws -> [BlazeDataRecord] {
    let compoundKey = fields.joined(separator: "+")
    let indexKey = CompoundIndexKey(values)
    return try queue.sync {
        guard let uuids = secondaryIndexes[compoundKey]?[indexKey], !uuids.isEmpty else {
            return []
        }
        return try uuids.compactMap { try _fetchNoSync(id: $0) }
    }
}

public func persist() throws {
    try queue.sync(flags: .barrier) {
        try saveLayout()
    }
}

private func saveLayout() throws {
    // Save the current layout, including secondaryIndexes
    let layout = StorageLayout(indexMap: indexMap, nextPageIndex: nextPageIndex, secondaryIndexes: secondaryIndexes)
    print("📝 Saving layout: indexMap count = \(indexMap.count), nextPageIndex = \(nextPageIndex), secondaryIndexes count = \(secondaryIndexes.count)")
    do {
        try layout.save(to: metaURL)
    } catch {
        print("❌ Failed to save layout: \(error)")
        throw error
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
        // Use _fetchNoSync to avoid nested sync
        guard var record = try _fetchNoSync(id: id) else { return }
        var storage = record.storage
        storage["isDeleted"] = .bool(true)
        try update(id: id, with: BlazeDataRecord(storage))
    }
}

/// Permanently removes all soft-deleted records from disk.
public func purge() throws {
    try queue.sync(flags: .barrier) {
        // Use fetchAll (which now uses _fetchNoSync internally, so this is fine)
        let toDelete = try fetchAll().compactMap { record -> UUID? in
            if let isDeleted = record.storage["isDeleted"]?.value as? Bool, isDeleted {
                return record.storage["id"]?.value as? UUID
            }
            return nil
        }
        for id in toDelete {
            try delete(id: id)
        }
    }
}

public func query() -> BlazeQueryContext {
    return BlazeQueryContext(collection: self)
}
}

// MARK: - MetaStore Conformance
extension DynamicCollection: MetaStore {
public func fetchMeta() throws -> [String: BlazeDocumentField] {
    let layout = try StorageLayout.load(from: meta)
    return layout.metaData
}

public func updateMeta(_ newMeta: [String: BlazeDocumentField]) throws {
    var layout = try StorageLayout.load(from: meta)
    layout.metaData = newMeta
    try layout.save(to: meta)
}
}

public struct BlazeQueryContext {
private let collection: DynamicCollection
private let query = BlazeQuery<[String: BlazeDocumentField]>()

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
private let builder: BlazeQuery<T>
private var field: String?

public init(builder: BlazeQuery<T>, field: String? = nil) {
    self.builder = builder
    self.field = field
}

// Example function to allow chaining (customize later)
public func equals(_ value: BlazeDocumentField) -> BlazeQuery<T> {
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
            (try? JSONEncoder().encode(record.storage).count) ?? 0
        }.max() ?? 0) ?? 0
    }
}

public var pageWarningCount: Int {
    return queue.sync {
        do {
            let all = try fetchAll()
            let count = all.filter {
                guard let encodedSize = try? JSONEncoder().encode($0.storage).count else {
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
        let indexKey = CompoundIndexKey([value])
        guard let uuids = secondaryIndexes[field]?[indexKey], !uuids.isEmpty else {
            return []
        }
        return try uuids.compactMap { try _fetchNoSync(id: $0) }
    }
}

public func fetchAllIDs() throws -> [UUID] {
    return try queue.sync {
        return Array(indexMap.keys)
    }
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

