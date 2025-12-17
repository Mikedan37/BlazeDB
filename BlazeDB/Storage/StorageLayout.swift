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
        } else if let v = try? container.decode(Data.self) {
            self = .data(v)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid type for AnyBlazeCodable")
        }
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

        // Handle backward compatibility: old format [UUID: Int] vs new format [UUID: [Int]]
        if let oldFormat = try? container.decodeIfPresent([UUID: Int].self, forKey: .indexMap) {
            // Convert old format to new format
            indexMap = oldFormat.mapValues { [$0] }
        } else {
            indexMap = try container.decodeIfPresent([UUID: [Int]].self, forKey: .indexMap) ?? [:]
        }
        nextPageIndex = try container.decodeIfPresent(Int.self, forKey: .nextPageIndex) ?? 0
        secondaryIndexes = try container.decodeIfPresent([String: [CompoundIndexKey: [UUID]]].self, forKey: .secondaryIndexes) ?? [:]
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        encodingFormat = try container.decodeIfPresent(String.self, forKey: .encodingFormat) ?? "blazeBinary"  // ✅ Default to blazeBinary
        metaData = try container.decodeIfPresent([String: BlazeDocumentField].self, forKey: .metaData) ?? [:]
        fieldTypes = try container.decodeIfPresent([String: String].self, forKey: .fieldTypes) ?? [:]
        secondaryIndexDefinitions = try container.decodeIfPresent([String: [String]].self, forKey: .secondaryIndexDefinitions) ?? [:]
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
            let layout = try decoder.decode(StorageLayout.self, from: data)
            return layout
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
        
        // Use atomic write with data protection to prevent corruption
        // .atomic writes to temp file first, then renames (safe from crashes)
        // .completeFileProtection ensures data is flushed before returning
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        
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
