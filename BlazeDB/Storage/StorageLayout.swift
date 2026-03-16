//  StorageLayout.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public enum AnyBlazeCodable: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case uuid(UUID)
    case data(Data)

    var value: AnyHashable {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .date(let v): return v
        case .uuid(let v): return v
        case .data(let v): return v as AnyHashable
        }
    }

    init(_ anyHashable: AnyHashable) {
        // Unwrap nested AnyHashable(AnyHashable(...)) and Optional(...)
        func unwrap(_ value: Any) -> Any {
            var current: Any = value
            while true {
                // If it's Optional, unwrap it
                let mirror = Mirror(reflecting: current)
                if mirror.displayStyle == .optional {
                    if let child = mirror.children.first {
                        current = child.value
                        continue
                    } else {
                        return current // nil optional stays as-is
                    }
                }
                // If it's AnyHashable, Mirror exposes the underlying storage as the first child
                if current is AnyHashable, let child = Mirror(reflecting: current).children.first {
                    current = child.value
                    continue
                }
                break
            }
            return current
        }

        let raw = unwrap(anyHashable)

        switch raw {
        case let v as AnyBlazeCodable:
            self = v
        case let v as String:
            self = .string(v)
        case let v as Substring:
            self = .string(String(v))
        case let v as Int:
            self = .int(v)
        case let v as Int8:
            self = .int(Int(v))
        case let v as Int16:
            self = .int(Int(v))
        case let v as Int32:
            self = .int(Int(v))
        case let v as Int64:
            self = .int(Int(truncatingIfNeeded: v))
        case let v as UInt:
            self = .int(Int(v))
        case let v as UInt8:
            self = .int(Int(v))
        case let v as UInt16:
            self = .int(Int(v))
        case let v as UInt32:
            self = .int(Int(v))
        case let v as UInt64:
            self = .int(Int(truncatingIfNeeded: v))
        case let v as Double:
            self = .double(v)
        case let v as Float:
            self = .double(Double(v))
        case let v as Bool:
            self = .bool(v)
        case let v as Date:
            self = .date(v)
        case let v as UUID:
            self = .uuid(v)
        case let v as Data:
            self = .data(v)
        default:
            // Do not crash tests; coerce to string for unsupported types
            assertionFailure("Unsupported AnyHashable base type: \(type(of: raw)); coercing to .string")
            self = .string(String(describing: raw))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do { self = .string(try container.decode(String.self)); return } catch {}
        do { self = .int(try container.decode(Int.self)); return } catch {}
        do { self = .double(try container.decode(Double.self)); return } catch {}
        do { self = .bool(try container.decode(Bool.self)); return } catch {}
        do { self = .date(try container.decode(Date.self)); return } catch {}
        do { self = .uuid(try container.decode(UUID.self)); return } catch {}
        do { self = .data(try container.decode(Data.self)); return } catch {}
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid type for AnyBlazeCodable")
    }

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
        }
    }
}

struct StorageLayout: Codable {
    var indexMap: [UUID: [Int]]  // Changed to support overflow chains
    var nextPageIndex: Int
    // CHANGE: Now uses CompoundIndexKey for single/compound indexes
    var secondaryIndexes: [String: [CompoundIndexKey: [UUID]]]
    var version: Int
    var encodingFormat: String = "blazeBinary"  // ✅ BlazeBinary is the default format!
    var metaData: [String: BlazeDocumentField] = [:]
    var fieldTypes: [String: String] = [:] // field name to type name
    var secondaryIndexDefinitions: [String: [String]] // persisted index definitions
    
    // NEW: Full-text search index (optional)
    var searchIndex: InvertedIndex?
    var searchIndexedFields: [String] = [] // Fields that are indexed for search
    
    // NEW: Page reuse for garbage collection (v3.0)
    var deletedPages: [Int] = []  // Array for ordered reuse (FIFO)

    enum CodingKeys: String, CodingKey {
        case indexMap
        case nextPageIndex
        case secondaryIndexes
        case version
        case encodingFormat
        case metaData
        case fieldTypes
        case secondaryIndexDefinitions
        case searchIndex
        case searchIndexedFields
        case deletedPages
    }

    private enum IndexMapValue: Decodable {
        case int(Int)
        case double(Double)
        case string(String)
        case array([IndexMapValue])
        case object([String: IndexMapValue])
        case null

        private struct DynamicKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) {
                self.stringValue = stringValue
                self.intValue = nil
            }
            init?(intValue: Int) {
                self.stringValue = "\(intValue)"
                self.intValue = intValue
            }
        }

        init(from decoder: Decoder) throws {
            // Best-effort tolerant parsing: never throw on legacy/corrupted shapes.
            if var unkeyed = try? decoder.unkeyedContainer() {
                var array: [IndexMapValue] = []
                while !unkeyed.isAtEnd {
                    let nested = (try? unkeyed.decode(IndexMapValue.self)) ?? .null
                    array.append(nested)
                }
                self = .array(array)
                return
            }

            if let keyed = try? decoder.container(keyedBy: DynamicKey.self) {
                var object: [String: IndexMapValue] = [:]
                for key in keyed.allKeys {
                    object[key.stringValue] = (try? keyed.decode(IndexMapValue.self, forKey: key)) ?? .null
                }
                self = .object(object)
                return
            }

            if let container = try? decoder.singleValueContainer() {
                if container.decodeNil() {
                    self = .null
                    return
                }
                if let value = try? container.decode(Int.self) {
                    self = .int(value)
                    return
                }
                if let value = try? container.decode(Double.self) {
                    self = .double(value)
                    return
                }
                if let value = try? container.decode(String.self) {
                    self = .string(value)
                    return
                }
            }

            self = .null
        }
    }

    private static func flattenIndexMapValues(_ value: IndexMapValue) -> [Int] {
        switch value {
        case .int(let i):
            return [i]
        case .double(let d):
            guard d.rounded(.towardZero) == d else { return [] }
            return [Int(d)]
        case .string(let s):
            guard let i = Int(s) else { return [] }
            return [i]
        case .array(let values):
            return values.flatMap(flattenIndexMapValues)
        case .object(let object):
            if let pages = object["pages"] {
                return flattenIndexMapValues(pages)
            }
            if let value = object["value"] {
                return flattenIndexMapValues(value)
            }
            return []
        case .null:
            return []
        }
    }

    private static func extractUUID(from value: IndexMapValue) -> UUID? {
        switch value {
        case .string(let id):
            return UUID(uuidString: id)
        case .array(let values):
            for element in values {
                if let uuid = extractUUID(from: element) {
                    return uuid
                }
            }
            return nil
        case .object(let object):
            if let idValue = object["id"], let uuid = extractUUID(from: idValue) {
                return uuid
            }
            if let keyValue = object["key"], let uuid = extractUUID(from: keyValue) {
                return uuid
            }
            return nil
        case .int, .double, .null:
            return nil
        }
    }

    private static func decodeIndexMap(from container: KeyedDecodingContainer<CodingKeys>) throws -> [UUID: [Int]] {
        let raw = try container.decodeIfPresent(IndexMapValue.self, forKey: .indexMap) ?? .object([:])
        var parsed: [UUID: [Int]] = [:]

        switch raw {
        case .object(let map):
            // Shape: { "<uuid>": 1 | [1,2] | [[1],[2]] }
            for (key, value) in map {
                guard let uuid = UUID(uuidString: key) else { continue }
                parsed[uuid] = flattenIndexMapValues(value)
            }
        case .array(let entries):
            // Flat legacy shape: [ "<uuid>", [1,2], "<uuid>", [3], ... ]
            var flatCursor = 0
            while flatCursor + 1 < entries.count {
                if let uuid = extractUUID(from: entries[flatCursor]) {
                    parsed[uuid] = flattenIndexMapValues(entries[flatCursor + 1])
                }
                flatCursor += 2
            }

            // Legacy/canonical shape: [ { "id": "<uuid>", "pages": [...] }, ... ]
            // Also supports tuple-ish shape: [ ["<uuid>", ...], ... ]
            for entry in entries {
                switch entry {
                case .object(let obj):
                    guard
                        let idValue = obj["id"] ?? obj["key"],
                        let uuid = extractUUID(from: idValue)
                    else { continue }
                    let value = obj["pages"] ?? obj["value"] ?? .null
                    parsed[uuid] = flattenIndexMapValues(value)
                case .array(let pair):
                    guard pair.count >= 2 else { continue }
                    guard let uuid = extractUUID(from: pair[0]) else { continue }
                    parsed[uuid] = flattenIndexMapValues(pair[1])
                default:
                    continue
                }
            }
        default:
            break
        }
        return parsed
    }

    private struct CanonicalSecondaryIndexEntry: Decodable {
        let name: String
        let entries: [CanonicalSecondaryEntry]
    }

    private struct CanonicalSecondaryEntry: Decodable {
        let key: CompoundIndexKey
        let ids: [String]
    }

    private struct CanonicalKVEntry<T: Decodable>: Decodable {
        let key: String
        let value: T
    }

    private static func decodeSecondaryIndexes(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [String: [CompoundIndexKey: [UUID]]] {
        do {
            if let decoded = try container.decodeIfPresent([String: [CompoundIndexKey: [UUID]]].self, forKey: .secondaryIndexes) {
                return decoded
            }
        } catch {
            // Fall through to canonical format.
        }

        do {
            if let canonical = try container.decodeIfPresent([CanonicalSecondaryIndexEntry].self, forKey: .secondaryIndexes) {
                return canonical.reduce(into: [String: [CompoundIndexKey: [UUID]]]()) { acc, entry in
                    let inner = entry.entries.reduce(into: [CompoundIndexKey: [UUID]]()) { innerAcc, item in
                        innerAcc[item.key] = item.ids.compactMap(UUID.init(uuidString:))
                    }
                    acc[entry.name] = inner
                }
            }
        } catch {
            // Ignore malformed legacy/canonical secondary index payloads.
        }
        return [:]
    }

    private static func decodeMetaData(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [String: BlazeDocumentField] {
        if let decoded = try? container.decode([String: BlazeDocumentField].self, forKey: .metaData) {
            return decoded
        }
        if let canonical = try? container.decode([CanonicalKVEntry<BlazeDocumentField>].self, forKey: .metaData) {
            return canonical.reduce(into: [String: BlazeDocumentField]()) { acc, entry in
                acc[entry.key] = entry.value
            }
        }
        if let scalarCanonical = try? container.decode([CanonicalKVEntry<AnyBlazeCodable>].self, forKey: .metaData) {
            return scalarCanonical.reduce(into: [String: BlazeDocumentField]()) { acc, entry in
                let value: BlazeDocumentField
                switch entry.value {
                case .string(let v): value = .string(v)
                case .int(let v): value = .int(v)
                case .double(let v): value = .double(v)
                case .bool(let v): value = .bool(v)
                case .date(let v): value = .date(v)
                case .uuid(let v): value = .uuid(v)
                case .data(let v): value = .data(v)
                }
                acc[entry.key] = value
            }
        }
        return [:]
    }

    private static func decodeFieldTypes(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [String: String] {
        if let decoded = try? container.decode([String: String].self, forKey: .fieldTypes) {
            return decoded
        }
        if let canonical = try? container.decode([CanonicalKVEntry<String>].self, forKey: .fieldTypes) {
            return canonical.reduce(into: [String: String]()) { acc, entry in
                acc[entry.key] = entry.value
            }
        }
        return [:]
    }

    private static func decodeSecondaryIndexDefinitions(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [String: [String]] {
        if let decoded = try? container.decode([String: [String]].self, forKey: .secondaryIndexDefinitions) {
            return decoded
        }
        if let canonical = try? container.decode([CanonicalKVEntry<[String]>].self, forKey: .secondaryIndexDefinitions) {
            return canonical.reduce(into: [String: [String]]()) { acc, entry in
                acc[entry.key] = entry.value
            }
        }
        return [:]
    }

    // Convert from runtime [String: [AnyHashable: Set<UUID>]]
    init(indexMap: [UUID: [Int]], nextPageIndex: Int, secondaryIndexes: [String: [AnyHashable: Set<UUID>]]) {
        self.indexMap = indexMap
        self.nextPageIndex = nextPageIndex
        self.secondaryIndexes = secondaryIndexes.reduce(into: [:]) { acc, pair in
            let (indexName, inner) = pair
            var merged: [CompoundIndexKey: [UUID]] = [:]
            for (key, set) in inner {
                // Convert AnyHashable to CompoundIndexKey
                // For single-component keys, extract the value and create a CompoundIndexKey
                let component: AnyBlazeCodable
                // Extract base value from AnyHashable
                let mirror = Mirror(reflecting: key)
                if let baseValue = mirror.children.first?.value {
                    if let str = baseValue as? String {
                        component = .string(str)
                    } else if let int = baseValue as? Int {
                        component = .int(int)
                    } else if let double = baseValue as? Double {
                        component = .double(double)
                    } else if let bool = baseValue as? Bool {
                        component = .bool(bool)
                    } else if let date = baseValue as? Date {
                        component = .date(date)
                    } else if let uuid = baseValue as? UUID {
                        component = .uuid(uuid)
                    } else if let data = baseValue as? Data {
                        component = .data(data)
                    } else {
                        component = .string("")  // Fallback for unknown types
                    }
                } else {
                    component = .string("")  // Fallback if extraction fails
                }
                let ckey = CompoundIndexKey([component])
                var arr = merged[ckey] ?? []
                arr.append(contentsOf: set)
                // de-duplicate while preserving no particular order
                merged[ckey] = Array(Set(arr))
            }
            acc[indexName] = merged
        }
        self.version = 1
        self.encodingFormat = "blazeBinary"  // ✅ Set correct format
        self.secondaryIndexDefinitions = [:]
        self.deletedPages = []  // ✅ Initialize deletedPages
    }

    // Convert from runtime [String: [CompoundIndexKey: Set<UUID>]]
    init(
        indexMap: [UUID: [Int]], 
        nextPageIndex: Int, 
        compoundIndexes: [String: [CompoundIndexKey: Set<UUID>]],
        searchIndex: InvertedIndex? = nil,
        searchIndexedFields: [String] = []
    ) {
        self.indexMap = indexMap
        self.nextPageIndex = nextPageIndex
        self.encodingFormat = "blazeBinary"  // ✅ Set correct format
        self.secondaryIndexes = compoundIndexes.reduce(into: [:]) { acc, pair in
            let (indexName, inner) = pair
            var merged: [CompoundIndexKey: [UUID]] = [:]
            for (ckey, set) in inner {
                var arr = merged[ckey] ?? []
                arr.append(contentsOf: set)
                merged[ckey] = Array(Set(arr))
            }
            acc[indexName] = merged
        }
        self.version = 1
        self.secondaryIndexDefinitions = [:]
        self.searchIndex = searchIndex
        self.searchIndexedFields = searchIndexedFields
        self.deletedPages = []  // ✅ Initialize deletedPages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        do {
            indexMap = try Self.decodeIndexMap(from: container)
        } catch {
            // Be tolerant to historical/corrupted indexMap encodings and let recovery paths rebuild state.
            BlazeLogger.warn("indexMap decode failed; continuing with empty indexMap for recovery: \(error)")
            indexMap = [:]
        }
        nextPageIndex = try container.decodeIfPresent(Int.self, forKey: .nextPageIndex) ?? 0
        secondaryIndexes = Self.decodeSecondaryIndexes(from: container)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        encodingFormat = try container.decodeIfPresent(String.self, forKey: .encodingFormat) ?? "blazeBinary"  // ✅ Default to blazeBinary
        metaData = Self.decodeMetaData(from: container)
        fieldTypes = Self.decodeFieldTypes(from: container)
        secondaryIndexDefinitions = Self.decodeSecondaryIndexDefinitions(from: container)
        searchIndex = try container.decodeIfPresent(InvertedIndex.self, forKey: .searchIndex)
        searchIndexedFields = try container.decodeIfPresent([String].self, forKey: .searchIndexedFields) ?? []
        deletedPages = try container.decodeIfPresent([Int].self, forKey: .deletedPages) ?? []  // ✅ Decode deletedPages
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(indexMap, forKey: .indexMap)
        try container.encode(nextPageIndex, forKey: .nextPageIndex)
        try container.encode(secondaryIndexes, forKey: .secondaryIndexes)
        try container.encode(version, forKey: .version)
        try container.encode(encodingFormat, forKey: .encodingFormat)  // ✅ Encode it!
        try container.encode(metaData, forKey: .metaData)
        try container.encode(fieldTypes, forKey: .fieldTypes)
        try container.encode(secondaryIndexDefinitions, forKey: .secondaryIndexDefinitions)
        try container.encodeIfPresent(searchIndex, forKey: .searchIndex)
        try container.encode(searchIndexedFields, forKey: .searchIndexedFields)
        try container.encode(deletedPages, forKey: .deletedPages)  // ✅ Encode deletedPages
    }

    // For migration: converts to [String: [AnyHashable: Set<UUID>]] if needed (for legacy)
    func toLegacyRuntimeIndexes() -> [String: [AnyHashable: Set<UUID>]] {
        return secondaryIndexes.reduce(into: [:]) { acc, pair in
            let (indexName, inner) = pair
            var merged: [AnyHashable: Set<UUID>] = [:]
            for (key, value) in inner {
                if key.components.count == 1 {
                    // Convert BlazeDocumentField to AnyHashable for legacy format
                    let base: AnyHashable
                    switch key.components[0] {
                    case .string(let v): base = v
                    case .int(let v): base = v
                    case .double(let v): base = v
                    case .bool(let v): base = v
                    case .date(let v): base = v
                    case .uuid(let v): base = v
                    case .data(let v): base = v as AnyHashable
                    case .vector(let v): base = v as AnyHashable
                    case .null: base = "" as AnyHashable
                    case .array, .dictionary: base = "" as AnyHashable  // Not supported in legacy format
                    }
                    var existing = merged[base] ?? []
                    existing.formUnion(value)
                    merged[base] = existing
                } else {
                    // For multi-component keys, create a tuple-like AnyHashable
                    // Convert each component to its base value
                    let tupleValues: [AnyHashable] = key.components.map { component in
                        switch component {
                        case .string(let v): return v as AnyHashable
                        case .int(let v): return v as AnyHashable
                        case .double(let v): return v as AnyHashable
                        case .bool(let v): return v as AnyHashable
                        case .date(let v): return v as AnyHashable
                        case .uuid(let v): return v as AnyHashable
                        case .data(let v): return v as AnyHashable
                        case .vector(let v): return v as AnyHashable
                        case .null: return "" as AnyHashable
                        case .array, .dictionary: return "" as AnyHashable
                        }
                    }
                    let base = AnyHashable(tupleValues)
                    var existing = merged[base] ?? []
                    existing.formUnion(value)
                    merged[base] = existing
                }
            }
            acc[indexName] = merged
        }
    }

    static func load(from url: URL) throws -> StorageLayout {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            // Prefer secure-wrapper decode when present, but do not verify signature
            // in this legacy helper (verification is handled by loadSecure()).
            if let secureLayout = try? decoder.decode(StorageLayout.SecureLayout.self, from: data) {
                return secureLayout.layout
            }

            return try decoder.decode(StorageLayout.self, from: data)
        } catch {
            // Check if file simply doesn't exist (new database) vs actual corruption
            if !FileManager.default.fileExists(atPath: url.path) {
                BlazeLogger.debug("Initializing new database (no layout file found at \(url.lastPathComponent))")
            } else {
                BlazeLogger.warn("Corrupted layout at \(url.lastPathComponent). Rebuilding default layout. Error: \(error)")
            }
            return StorageLayout.empty() // Return safe defaults
        }
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // DON'T use .prettyPrinted - causes size variations
        let data = try encoder.encode(self)
        BlazeLogger.debug("Saving layout JSON size: \(data.count)")
        
        // Use atomic write to prevent partial/corrupt metadata files.
        #if os(iOS) || os(tvOS) || os(watchOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        
        BlazeLogger.debug("Atomically saved layout to \(url.lastPathComponent)")
    }

    static func upgradeIfNeeded(from url: URL) throws -> StorageLayout {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try decoding to check version
        let basic = try decoder.decode(StorageLayout.self, from: data)

        // If current version is okay, return it
        if basic.version >= 1 {
            return basic
        }

        // Otherwise, run actual migration logic
        var migrated = basic

        if migrated.version == 0 {
            // Transform legacy secondaryIndexes using AnyHashable keys into CompoundIndexKey format
            let legacyIndexes: [String: [AnyHashable: Set<UUID>]] = migrated.toLegacyRuntimeIndexes()
            migrated.secondaryIndexes = legacyIndexes.reduce(into: [:]) { acc, pair in
                let (indexName, inner) = pair
                var merged: [CompoundIndexKey: [UUID]] = [:]
                for (key, set) in inner {
                    // Convert AnyHashable to CompoundIndexKey
                    // For single-component keys, extract the value and create a CompoundIndexKey
                    let component: AnyBlazeCodable
                    // Extract base value from AnyHashable
                    let mirror = Mirror(reflecting: key)
                    if let baseValue = mirror.children.first?.value {
                        if let str = baseValue as? String {
                            component = .string(str)
                        } else if let int = baseValue as? Int {
                            component = .int(int)
                        } else if let double = baseValue as? Double {
                            component = .double(double)
                        } else if let bool = baseValue as? Bool {
                            component = .bool(bool)
                        } else if let date = baseValue as? Date {
                            component = .date(date)
                        } else if let uuid = baseValue as? UUID {
                            component = .uuid(uuid)
                        } else if let data = baseValue as? Data {
                            component = .data(data)
                        } else {
                            component = .string("")  // Fallback for unknown types
                        }
                    } else {
                        component = .string("")  // Fallback if extraction fails
                    }
                    let ckey = CompoundIndexKey([component])
                    var arr = merged[ckey] ?? []
                    arr.append(contentsOf: set)
                    merged[ckey] = Array(Set(arr))
                }
                acc[indexName] = merged
            }
            // Update version
            migrated.version = 1
        }

        return migrated
    }
}

struct FieldDefinition {
    let typeName: String
}

extension StorageLayout {
    var fields: [FieldDefinition] {
        return fieldTypes.map { FieldDefinition(typeName: $0.value) }
    }
}

extension StorageLayout {
    static func empty() -> StorageLayout {
        return StorageLayout(
            indexMap: [:],
            nextPageIndex: 0,
            secondaryIndexes: [:],
            version: 1,
            encodingFormat: "blazeBinary",  // ✅ Set correct format
            metaData: [:],
            fieldTypes: [:],
            secondaryIndexDefinitions: [:],
            searchIndex: nil,
            searchIndexedFields: []
        )
    }
}

extension StorageLayout {
    init(
        indexMap: [UUID: [Int]] = [:],
        nextPageIndex: Int = 0,
        secondaryIndexes: [String: [CompoundIndexKey: [UUID]]] = [:],
        version: Int = 1,
        encodingFormat: String = "blazeBinary",  // ✅ Set correct format
        metaData: [String: BlazeDocumentField] = [:],
        fieldTypes: [String: String] = [:],
        secondaryIndexDefinitions: [String: [String]] = [:],
        searchIndex: InvertedIndex? = nil,
        searchIndexedFields: [String] = []
    ) {
        self.indexMap = indexMap
        self.nextPageIndex = nextPageIndex
        self.secondaryIndexes = secondaryIndexes
        self.version = version
        self.encodingFormat = encodingFormat
        self.metaData = metaData
        self.fieldTypes = fieldTypes
        self.secondaryIndexDefinitions = secondaryIndexDefinitions
        self.searchIndex = searchIndex
        self.searchIndexedFields = searchIndexedFields
        self.deletedPages = []  // ✅ Initialize deletedPages
    }
}
