//  StorageLayout.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation
import CryptoKit

public enum AnyBlazeCodable: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case uuid(UUID)

    var value: AnyHashable {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .date(let v): return v
        case .uuid(let v): return v
        }
    }

    init(_ anyHashable: AnyHashable) {
        switch anyHashable {
        case let v as String: self = .string(v)
        case let v as Int: self = .int(v)
        case let v as Double: self = .double(v)
        case let v as Bool: self = .bool(v)
        case let v as Date: self = .date(v)
        case let v as UUID: self = .uuid(v)
        default:
            fatalError("Unsupported type: \(type(of: anyHashable))")
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
        }
    }
}

struct StorageLayout: Codable {
    var indexMap: [UUID: Int]
    var nextPageIndex: Int
    // CHANGE: Now uses CompoundIndexKey for single/compound indexes
    var secondaryIndexes: [String: [CompoundIndexKey: [UUID]]]
    var version: Int
    var metaData: [String: BlazeDocumentField] = [:]
    var fieldTypes: [String: String] = [:] // field name to type name

    enum CodingKeys: String, CodingKey {
        case indexMap
        case nextPageIndex
        case secondaryIndexes
        case version
        case metaData
        case fieldTypes
    }

    // Convert from runtime [String: [AnyHashable: Set<UUID>]]
    init(indexMap: [UUID: Int], nextPageIndex: Int, secondaryIndexes: [String: [AnyHashable: Set<UUID>]]) {
        self.indexMap = indexMap
        self.nextPageIndex = nextPageIndex
        self.secondaryIndexes = secondaryIndexes.mapValues { innerDict in
            Dictionary(uniqueKeysWithValues: innerDict.map { key, value in
                (CompoundIndexKey(single: key), Array(value))
            })
        }
        self.version = 1
    }

    // Convert from runtime [String: [CompoundIndexKey: Set<UUID>]]
    init(indexMap: [UUID: Int], nextPageIndex: Int, compoundIndexes: [String: [CompoundIndexKey: Set<UUID>]]) {
        self.indexMap = indexMap
        self.nextPageIndex = nextPageIndex
        self.secondaryIndexes = compoundIndexes.mapValues { innerDict in
            Dictionary(uniqueKeysWithValues: innerDict.map { key, value in
                (key, Array(value))
            })
        }
        self.version = 1
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        indexMap = try container.decode([UUID: Int].self, forKey: .indexMap)
        nextPageIndex = try container.decode(Int.self, forKey: .nextPageIndex)
        secondaryIndexes = try container.decodeIfPresent([String: [CompoundIndexKey: [UUID]]].self, forKey: .secondaryIndexes) ?? [:]
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        metaData = try container.decodeIfPresent([String: BlazeDocumentField].self, forKey: .metaData) ?? [:]
        fieldTypes = try container.decodeIfPresent([String: String].self, forKey: .fieldTypes) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(indexMap, forKey: .indexMap)
        try container.encode(nextPageIndex, forKey: .nextPageIndex)
        try container.encode(secondaryIndexes, forKey: .secondaryIndexes)
        try container.encode(version, forKey: .version)
        try container.encode(metaData, forKey: .metaData)
        try container.encode(fieldTypes, forKey: .fieldTypes)
    }

    // For migration: converts to [String: [AnyHashable: Set<UUID>]] if needed (for legacy)
    func toLegacyRuntimeIndexes() -> [String: [AnyHashable: Set<UUID>]] {
        return secondaryIndexes.mapValues { innerDict in
            Dictionary(uniqueKeysWithValues: innerDict.map { key, value in
                if key.components.count == 1 {
                    return (key.components[0].value, Set(value))
                } else {
                    let tupleValue = key.components.map { $0.value }
                    return (AnyHashable(tupleValue), Set(value))
                }
            })
        }
    }

    static func load(from url: URL) throws -> StorageLayout {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StorageLayout.self, from: data)
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        print("💾 Saving layout JSON size:", data.count)
        try data.write(to: url)
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

            migrated.secondaryIndexes = legacyIndexes.mapValues { innerDict in
                Dictionary(uniqueKeysWithValues: innerDict.map { key, value in
                    (CompoundIndexKey(single: key), Array(value))
                })
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
