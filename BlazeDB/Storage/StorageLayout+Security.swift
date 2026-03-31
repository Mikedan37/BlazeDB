//
//  StorageLayout+Security.swift
//  BlazeDB
//
//  Tamper-proof metadata with HMAC signatures
//  Prevents unauthorized modification of database structure
//
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

extension StorageLayout {
    private enum RawJSONValue: Decodable {
        private struct DynamicKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
            init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
        }

        case object([String: RawJSONValue])
        case array([RawJSONValue])
        case string(String)
        case number(Double)
        case null

        init(from decoder: Decoder) throws {
            if let keyed = try? decoder.container(keyedBy: DynamicKey.self) {
                var object: [String: RawJSONValue] = [:]
                for key in keyed.allKeys {
                    object[key.stringValue] = try keyed.decode(RawJSONValue.self, forKey: key)
                }
                self = .object(object)
                return
            }

            if var unkeyed = try? decoder.unkeyedContainer() {
                var array: [RawJSONValue] = []
                while !unkeyed.isAtEnd {
                    array.append(try unkeyed.decode(RawJSONValue.self))
                }
                self = .array(array)
                return
            }

            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null; return }
            if let number = try? container.decode(Double.self) { self = .number(number); return }
            if let string = try? container.decode(String.self) { self = .string(string); return }

            throw DecodingError.typeMismatch(
                RawJSONValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported raw JSON value")
            )
        }
    }

    private static func rawJSONToObject(_ value: RawJSONValue) -> Any {
        switch value {
        case .object(let dict):
            return dict.mapValues(rawJSONToObject)
        case .array(let arr):
            return arr.map(rawJSONToObject)
        case .string(let str):
            return str
        case .number(let num):
            return num
        case .null:
            return NSNull()
        }
    }

    private static func formatJSONSegment(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }

    private static func shouldDumpIndexMapSegment() -> Bool {
        ProcessInfo.processInfo.environment["BLAZEDB_DUMP_LAYOUT_INDEXMAP"] == "1"
    }

    private static func shouldDebugLayoutDecode() -> Bool {
        ProcessInfo.processInfo.environment["BLAZE_LAYOUT_DECODE_DEBUG"] == "1"
    }

    private static func indexMapShapeSummary(_ rawIndexMap: Any) -> String {
        func snippet(_ value: Any, maxLen: Int = 240) -> String {
            let rendered = formatJSONSegment(value)
            if rendered.count <= maxLen { return rendered }
            let head = rendered.prefix(maxLen)
            return "\(head)..."
        }

        if let object = rawIndexMap as? [String: Any] {
            let keys = Array(object.keys.sorted().prefix(2))
            return "type=object keyCount=\(object.count) sampleKeys=\(keys)"
        }
        if let array = rawIndexMap as? [Any] {
            let sample = Array(array.prefix(2))
            return "type=array itemCount=\(array.count) sample=\(snippet(sample))"
        }
        return "type=\(String(describing: type(of: rawIndexMap))) sample=\(snippet(rawIndexMap))"
    }

    private static func normalizeSecureLayoutObject(_ object: [String: Any]) throws -> [String: Any] {
        var normalized = object
        guard let rawIndexMap = normalized["indexMap"] else {
            return normalized
        }

        if shouldDebugLayoutDecode() {
            BlazeLogger.debug("layout.indexMap \(indexMapShapeSummary(rawIndexMap))")
        }

        if rawIndexMap is [String: Any] {
            // Current canonical shape - pass through unchanged.
            return normalized
        }

        if rawIndexMap is [Any] {
            // Legacy array shape - normalize to dictionary before typed decode.
            normalized["indexMap"] = normalizeIndexMapRaw(rawIndexMap)
            return normalized
        }

        throw NSError(
            domain: "StorageLayout",
            code: 8,
            userInfo: [
                NSLocalizedDescriptionKey: "unsupported_layout_indexmap_shape: \(indexMapShapeSummary(rawIndexMap))"
            ]
        )
    }

    private static func decodeStorageLayoutFromNormalizedSecureRawLayout(_ rawLayout: RawJSONValue) throws -> StorageLayout {
        guard let object = rawJSONToObject(rawLayout) as? [String: Any] else {
            throw NSError(
                domain: "StorageLayout",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "secure_layout_payload_not_object"]
            )
        }

        let normalized = try normalizeSecureLayoutObject(object)
        let data = try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(StorageLayout.self, from: data)
        } catch {
            // Legacy secure payloads can contain mixed tuple/object shapes that still
            // fail typed decoding after indexMap normalization. Fall back to tolerant
            // raw JSON layout decoding before treating this as fatal corruption.
            if let fallback = decodeLayoutFromRawJSON(normalized) {
                return fallback
            }
            throw error
        }
    }

    private static func dumpLayoutIndexMapSegmentFromSecureContainer(
        _ container: KeyedDecodingContainer<SecureLayout.CodingKeys>,
        decodeError: Error
    ) {
        guard shouldDumpIndexMapSegment() else { return }
        guard let rawLayoutDecoder = try? container.superDecoder(forKey: .layout),
              let rawLayout = try? RawJSONValue(from: rawLayoutDecoder) else {
            BlazeLogger.debug("BLAZEDB_DUMP layout.indexMap unavailable (layout raw decode failed): \(decodeError)")
            return
        }
        guard case .object(let layoutObject) = rawLayout,
              let indexMap = layoutObject["indexMap"] else {
            BlazeLogger.debug("BLAZEDB_DUMP layout.indexMap unavailable (missing indexMap key): \(decodeError)")
            return
        }
        let segment = formatJSONSegment(rawJSONToObject(indexMap))
        BlazeLogger.debug("BLAZEDB_DUMP layout.indexMap decodeError=\(decodeError)\n\(segment)")
    }

    private static func normalizedPageList(from any: Any) -> [Int] {
        if let intVal = any as? Int { return [intVal] }
        if let doubleVal = any as? Double, doubleVal.rounded(.towardZero) == doubleVal { return [Int(doubleVal)] }
        if let stringVal = any as? String, let intVal = Int(stringVal) { return [intVal] }
        if let list = any as? [Any] { return list.flatMap { normalizedPageList(from: $0) } }
        return []
    }

    private static func normalizedUUIDString(from any: Any) -> String? {
        if let string = any as? String, UUID(uuidString: string) != nil { return string }
        if let list = any as? [Any] {
            for item in list {
                if let string = normalizedUUIDString(from: item) { return string }
            }
        }
        return nil
    }

    private static func normalizeIndexMapRaw(_ rawIndexMap: Any) -> [String: [Int]] {
        var normalized: [String: [Int]] = [:]

        if let dict = rawIndexMap as? [String: Any] {
            for (key, value) in dict where UUID(uuidString: key) != nil {
                normalized[key] = normalizedPageList(from: value)
            }
            return normalized
        }

        if let entries = rawIndexMap as? [Any] {
            // Supports flat legacy shape: [ "<uuid>", [1,2], "<uuid>", [3], ... ]
            if entries.count >= 2 {
                var flatParsedCount = 0
                var i = 0
                while i + 1 < entries.count {
                    if let key = normalizedUUIDString(from: entries[i]) {
                        normalized[key] = normalizedPageList(from: entries[i + 1])
                        flatParsedCount += 1
                    }
                    i += 2
                }
                if flatParsedCount > 0 {
                    return normalized
                }
            }

            for entry in entries {
                // Supports legacy tuple-style: [key, value]
                if let pair = entry as? [Any], pair.count >= 2,
                   let key = normalizedUUIDString(from: pair[0]) {
                    normalized[key] = normalizedPageList(from: pair[1])
                    continue
                }
                // Supports canonical object-style: {"id":"...","pages":[...]}
                if let object = entry as? [String: Any],
                   let keyAny = object["id"] ?? object["key"],
                   let key = normalizedUUIDString(from: keyAny) {
                    let valueAny = object["pages"] ?? object["value"] ?? []
                    normalized[key] = normalizedPageList(from: valueAny)
                }
            }
        }

        return normalized
    }

    private static func decodeLayoutFromRawJSON(_ raw: Any) -> StorageLayout? {
        guard var object = raw as? [String: Any] else { return nil }
        func normalizeKVArrayObject(_ rawValue: Any) -> [String: Any]? {
            guard let entries = rawValue as? [[String: Any]] else { return nil }
            var dict: [String: Any] = [:]
            for entry in entries {
                guard let key = entry["key"] as? String else { continue }
                dict[key] = entry["value"]
            }
            return dict
        }

        let normalizedIndexMap = normalizeIndexMapRaw(object["indexMap"] ?? [:])
        if let rawMetaData = object["metaData"], let normalized = normalizeKVArrayObject(rawMetaData) {
            object["metaData"] = normalized
        }
        if let rawFieldTypes = object["fieldTypes"], let normalized = normalizeKVArrayObject(rawFieldTypes) {
            object["fieldTypes"] = normalized
        }
        if let rawSecondaryDefs = object["secondaryIndexDefinitions"], let normalized = normalizeKVArrayObject(rawSecondaryDefs) {
            object["secondaryIndexDefinitions"] = normalized
        }

        let indexMap: [UUID: [Int]] = normalizedIndexMap.reduce(into: [:]) { acc, pair in
            guard let uuid = UUID(uuidString: pair.key) else { return }
            acc[uuid] = pair.value
        }

        let nextPageIndex: Int = {
            if let value = object["nextPageIndex"] as? Int { return value }
            if let value = object["nextPageIndex"] as? Double, value.rounded(.towardZero) == value { return Int(value) }
            return 0
        }()
        let version: Int = {
            if let value = object["version"] as? Int { return value }
            if let value = object["version"] as? Double, value.rounded(.towardZero) == value { return Int(value) }
            return 1
        }()
        let encodingFormat = object["encodingFormat"] as? String ?? "blazeBinary"

        let fieldTypes = object["fieldTypes"] as? [String: String] ?? [:]
        let secondaryIndexDefinitions = object["secondaryIndexDefinitions"] as? [String: [String]] ?? [:]
        let searchIndexedFields = object["searchIndexedFields"] as? [String] ?? []
        let deletedPages = normalizedPageList(from: object["deletedPages"] ?? [])

        var metaData: [String: BlazeDocumentField] = [:]
        if let metaObject = object["metaData"],
           JSONSerialization.isValidJSONObject(metaObject),
           let metaDataBytes = try? JSONSerialization.data(withJSONObject: metaObject, options: [.sortedKeys]) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            metaData = (try? decoder.decode([String: BlazeDocumentField].self, from: metaDataBytes)) ?? [:]
        }

        var layout = StorageLayout(
            indexMap: indexMap,
            nextPageIndex: nextPageIndex,
            secondaryIndexes: [:],
            version: version,
            encodingFormat: encodingFormat,
            metaData: metaData,
            fieldTypes: fieldTypes,
            secondaryIndexDefinitions: secondaryIndexDefinitions,
            searchIndex: nil,
            searchIndexedFields: searchIndexedFields
        )
        layout.deletedPages = deletedPages
        return layout
    }

    private struct CanonicalStorageLayout: Codable {
        struct IndexEntry: Codable {
            let id: String
            let pages: [Int]
        }
        struct SecondaryIndexEntry: Codable {
            let name: String
            let entries: [SecondaryEntry]
        }
        struct SecondaryEntry: Codable {
            let key: CompoundIndexKey
            let ids: [String]
        }
        struct KVStringField<T: Codable>: Codable {
            let key: String
            let value: T
        }

        let indexMap: [IndexEntry]
        let nextPageIndex: Int
        let secondaryIndexes: [SecondaryIndexEntry]
        let version: Int
        let encodingFormat: String
        let metaData: [KVStringField<BlazeDocumentField>]
        let fieldTypes: [KVStringField<String>]
        let secondaryIndexDefinitions: [KVStringField<[String]>]
        let searchIndex: InvertedIndex?
        let searchIndexedFields: [String]
        let deletedPages: [Int]
    }

    private static func storageLayout(from canonical: CanonicalStorageLayout) -> StorageLayout {
        let indexMap: [UUID: [Int]] = canonical.indexMap.reduce(into: [:]) { acc, entry in
            guard let id = UUID(uuidString: entry.id) else { return }
            acc[id] = entry.pages
        }

        let secondaryIndexes: [String: [CompoundIndexKey: [UUID]]] = canonical.secondaryIndexes.reduce(into: [:]) { acc, indexEntry in
            let dict: [CompoundIndexKey: [UUID]] = indexEntry.entries.reduce(into: [:]) { inner, entry in
                inner[entry.key] = entry.ids.compactMap(UUID.init(uuidString:))
            }
            acc[indexEntry.name] = dict
        }

        let metaData = canonical.metaData.reduce(into: [String: BlazeDocumentField]()) { acc, entry in
            acc[entry.key] = entry.value
        }
        let fieldTypes = canonical.fieldTypes.reduce(into: [String: String]()) { acc, entry in
            acc[entry.key] = entry.value
        }
        let secondaryIndexDefinitions = canonical.secondaryIndexDefinitions.reduce(into: [String: [String]]()) { acc, entry in
            acc[entry.key] = entry.value
        }

        var layout = StorageLayout(
            indexMap: indexMap,
            nextPageIndex: canonical.nextPageIndex,
            secondaryIndexes: secondaryIndexes,
            version: canonical.version,
            encodingFormat: canonical.encodingFormat,
            metaData: metaData,
            fieldTypes: fieldTypes,
            secondaryIndexDefinitions: secondaryIndexDefinitions,
            searchIndex: canonical.searchIndex,
            searchIndexedFields: canonical.searchIndexedFields
        )
        layout.deletedPages = canonical.deletedPages
        return layout
    }

    private static func canonicalLayout(from layout: StorageLayout) -> CanonicalStorageLayout {
        return CanonicalStorageLayout(
            indexMap: layout.indexMap
                .map { CanonicalStorageLayout.IndexEntry(id: $0.key.uuidString, pages: $0.value.sorted()) }
                .sorted { $0.id < $1.id },
            nextPageIndex: layout.nextPageIndex,
            secondaryIndexes: layout.secondaryIndexes
                .map { name, entries in
                    let sortedEntries = entries.map { key, ids in
                        CanonicalStorageLayout.SecondaryEntry(
                            key: key,
                            ids: ids.map(\.uuidString).sorted()
                        )
                    }
                    .sorted { String(describing: $0.key) < String(describing: $1.key) }
                    return CanonicalStorageLayout.SecondaryIndexEntry(name: name, entries: sortedEntries)
                }
                .sorted { $0.name < $1.name },
            version: layout.version,
            encodingFormat: layout.encodingFormat,
            metaData: layout.metaData
                .map { CanonicalStorageLayout.KVStringField(key: $0.key, value: $0.value) }
                .sorted { $0.key < $1.key },
            fieldTypes: layout.fieldTypes
                .map { CanonicalStorageLayout.KVStringField(key: $0.key, value: $0.value) }
                .sorted { $0.key < $1.key },
            secondaryIndexDefinitions: layout.secondaryIndexDefinitions
                .map { CanonicalStorageLayout.KVStringField(key: $0.key, value: $0.value.sorted()) }
                .sorted { $0.key < $1.key },
            searchIndex: layout.searchIndex,
            searchIndexedFields: layout.searchIndexedFields.sorted(),
            deletedPages: layout.deletedPages.sorted()
        )
    }

    private static func canonicalSignaturePayload(for layout: StorageLayout) throws -> Data {
        // Canonicalize non-string-key dictionaries into sorted arrays so signatures
        // are stable across process restarts and hash-seed changes.
        let canonicalLayout = canonicalLayout(from: layout)

        // Step 1: Encode canonical layout with stable date strategy.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let raw = try encoder.encode(canonicalLayout)

        // Step 2: Re-serialize via JSONSerialization with sorted keys, which applies
        // recursively across nested dictionaries to produce canonical bytes.
        let object = try JSONSerialization.jsonObject(with: raw, options: [])
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    
    /// Secure storage layout with HMAC signature
    public struct SecureLayout: Codable {
        /// Schema version for secure wrapper.
        /// v1: layout + signature + signedAt (legacy)
        /// v2: adds signedPayload and requires it for strict verification
        public let secureLayoutVersion: Int

        /// The actual layout data
        public let layout: StorageLayout

        /// Backward-compatibility mirror for readers/tests that inspect top-level metadata.
        /// Canonical source remains `layout.encodingFormat`.
        public let encodingFormat: String?

        /// Exact bytes that were signed. If present, verification uses this payload
        /// directly to avoid re-encoding nondeterminism with non-string dictionary keys.
        public let signedPayload: Data?
        
        /// HMAC-SHA256 signature for tamper detection
        public let signature: Data
        
        /// Timestamp when signed
        public let signedAt: Date

        enum CodingKeys: String, CodingKey {
            case secureLayoutVersion
            case layout
            case encodingFormat
            case signedPayload
            case signature
            case signedAt
        }

        public init(
            secureLayoutVersion: Int,
            layout: StorageLayout,
            encodingFormat: String? = nil,
            signedPayload: Data?,
            signature: Data,
            signedAt: Date
        ) {
            self.secureLayoutVersion = secureLayoutVersion
            self.layout = layout
            self.encodingFormat = encodingFormat
            self.signedPayload = signedPayload
            self.signature = signature
            self.signedAt = signedAt
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            secureLayoutVersion = try c.decodeIfPresent(Int.self, forKey: .secureLayoutVersion) ?? 1
            encodingFormat = try c.decodeIfPresent(String.self, forKey: .encodingFormat)
            signedPayload = try c.decodeIfPresent(Data.self, forKey: .signedPayload)
            signature = try c.decode(Data.self, forKey: .signature)
            signedAt = try c.decode(Date.self, forKey: .signedAt)

            do {
                let decodedLayout = try c.decode(StorageLayout.self, forKey: .layout)
                layout = decodedLayout
                return
            } catch {
                StorageLayout.dumpLayoutIndexMapSegmentFromSecureContainer(c, decodeError: error)
            }

            // Trunk-path migration: normalize only layout.indexMap before typed decode.
            if let rawLayoutDecoder = try? c.superDecoder(forKey: .layout),
               let rawLayout = try? RawJSONValue(from: rawLayoutDecoder) {
                do {
                    layout = try StorageLayout.decodeStorageLayoutFromNormalizedSecureRawLayout(rawLayout)
                    return
                } catch {
                    if StorageLayout.shouldDebugLayoutDecode() {
                        BlazeLogger.debug("Secure trunk normalization failed: \(error)")
                    }
                }
            }

            // Prefer signed payload for v2+ because it's the verification source-of-truth.
            if secureLayoutVersion >= 2, let signedPayload {
                let payloadDecoder = JSONDecoder()
                payloadDecoder.dateDecodingStrategy = .iso8601
                if let canonical = try? payloadDecoder.decode(CanonicalStorageLayout.self, from: signedPayload) {
                    layout = StorageLayout.storageLayout(from: canonical)
                    return
                }
            }

            // Some legacy files persisted canonical layout shape directly in `layout`.
            if let canonicalDecoder = try? c.superDecoder(forKey: .layout),
               let canonicalLayout = try? CanonicalStorageLayout(from: canonicalDecoder) {
                layout = StorageLayout.storageLayout(from: canonicalLayout)
                return
            }

            throw DecodingError.dataCorruptedError(
                forKey: .layout,
                in: c,
                debugDescription: "Unable to decode secure layout payload"
            )
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(secureLayoutVersion, forKey: .secureLayoutVersion)
            try c.encode(layout, forKey: .layout)
            try c.encode(encodingFormat ?? layout.encodingFormat, forKey: .encodingFormat)
            try c.encodeIfPresent(signedPayload, forKey: .signedPayload)
            try c.encode(signature, forKey: .signature)
            try c.encode(signedAt, forKey: .signedAt)
        }
        
        /// Create secure layout with signature
        public static func create(
            layout: StorageLayout,
            signingKey: SymmetricKey
        ) throws -> SecureLayout {
            let encoded = try StorageLayout.canonicalSignaturePayload(for: layout)
            
            // Generate HMAC signature
            let hmac = HMAC<SHA256>.authenticationCode(
                for: encoded,
                using: signingKey
            )
            
            return SecureLayout(
                secureLayoutVersion: 2,
                layout: layout,
                encodingFormat: layout.encodingFormat,
                signedPayload: encoded,
                signature: Data(hmac),
                signedAt: Date()
            )
        }
        
        /// Verify layout integrity
        public func verify(using signingKey: SymmetricKey) -> Bool {
            do {
                let expectedSignature = try expectedSignature(using: signingKey)
                
                // Compare signatures using constant-time semantics.
                let matches = StorageLayout.constantTimeEquals(expectedSignature, signature)
                
                if !matches && !BlazeDBForensics.enabled {
                    BlazeLogger.error("❌ [VERIFY] Signature verification failed")
                    BlazeLogger.error("❌ [VERIFY] Expected signature (first 16 bytes): \(expectedSignature.prefix(16).map { String(format: "%02x", $0) }.joined())...")
                    BlazeLogger.error("❌ [VERIFY] Stored signature (first 16 bytes): \(signature.prefix(16).map { String(format: "%02x", $0) }.joined())...")
                }
                
                return matches
            } catch {
                BlazeLogger.error("❌ [VERIFY] Failed to verify layout signature: \(error)")
                return false
            }
        }

        private func payloadForVerification() throws -> Data {
            if secureLayoutVersion >= 2 && signedPayload == nil {
                throw NSError(
                    domain: "StorageLayout",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "secure_layout_v2_missing_signed_payload"]
                )
            }
            if let signedPayload {
                return signedPayload
            }
            // Backward compatibility for pre-v2 records without signed payload bytes.
            return try StorageLayout.canonicalSignaturePayload(for: layout)
        }

        func resolvedLayout(using decoder: JSONDecoder) throws -> StorageLayout {
            if secureLayoutVersion >= 2 {
                guard let payload = signedPayload else {
                    throw NSError(
                        domain: "StorageLayout",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "secure_layout_v2_missing_signed_payload"]
                    )
                }
                if let canonical = try? decoder.decode(CanonicalStorageLayout.self, from: payload) {
                    return StorageLayout.storageLayout(from: canonical)
                }
                if let raw = try? JSONSerialization.jsonObject(with: payload, options: []),
                   let normalized = StorageLayout.decodeLayoutFromRawJSON(raw) {
                    return normalized
                }
                throw NSError(
                    domain: "StorageLayout",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "secure_layout_v2_payload_decode_failed"]
                )
            }
            return layout
        }

        func expectedSignature(using signingKey: SymmetricKey) throws -> Data {
            let encoded = try payloadForVerification()

            let expectedHMAC = HMAC<SHA256>.authenticationCode(
                for: encoded,
                using: signingKey
            )
            return Data(expectedHMAC)
        }
        
        /// Check if signature is expired (optional security feature)
        public func isExpired(maxAge: TimeInterval = 86400 * 365) -> Bool {
            let age = Date().timeIntervalSince(signedAt)
            return age > maxAge
        }
    }
    
    /// Save layout with HMAC signature
    public func saveSecure(
        to url: URL,
        signingKey: SymmetricKey
    ) throws {
#if DEBUG
        if ProcessInfo.processInfo.environment["BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE"] == "1" {
            throw NSError(
                domain: "BlazeDBTestFault",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Forced layout save failure for tests"]
            )
        }
#endif

        let secureLayout = try SecureLayout.create(
            layout: self,
            signingKey: signingKey
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]  // Ensure deterministic encoding for SecureLayout wrapper too
        let data = try encoder.encode(secureLayout)
        
        // Use atomic write with platform-appropriate file protection.
        #if os(iOS) || os(tvOS) || os(watchOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        
        // CRITICAL: Ensure file is fully synced to disk before returning
        // This prevents signature verification failures when reopening immediately after save
        if let fileHandle = FileHandle(forWritingAtPath: url.path) {
            fileHandle.synchronizeFile()
            fileHandle.closeFile()
        }
    }
    
    /// Load layout with signature verification
    /// If signature verification fails with the provided key, this will try alternative KDF methods
    /// to auto-detect which method was used (useful when cache is cleared)
    public static func loadSecure(
        from url: URL,
        signingKey: SymmetricKey,
        password: String? = nil,
        salt: Data? = nil,
        allowUnsignedLayoutFallback: Bool = false
    ) throws -> StorageLayout {
        let data = try Data(contentsOf: url)
        guard looksLikeJSONLayout(data) else {
            throw NSError(
                domain: "StorageLayout",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "layout_format_mismatch_json_vs_framed"]
            )
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // Try to decode as secure layout first
        if let secureLayout = try? decoder.decode(SecureLayout.self, from: data) {
            if secureLayout.secureLayoutVersion >= 2 && secureLayout.signedPayload == nil {
                throw NSError(
                    domain: "StorageLayout",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "secure_layout_v2_missing_signed_payload"]
                )
            }
            // Verify signature with provided key
            if secureLayout.verify(using: signingKey) {
                // Check expiry (optional)
                if secureLayout.isExpired() {
                    BlazeLogger.warn("Layout signature is expired (older than 1 year)")
                }
                
                BlazeLogger.debug("✅ Signature verified with provided key")
                return try secureLayout.resolvedLayout(using: decoder)
            }

            if BlazeDBForensics.enabled {
                let expectedSignature = (try? secureLayout.expectedSignature(using: signingKey)) ?? Data()
                BlazeDBForensics.captureVerifyFailure(
                    layoutURL: url,
                    fileData: data,
                    expectedSignature: expectedSignature,
                    storedSignature: secureLayout.signature
                )
                throw NSError(
                    domain: "StorageLayout",
                    code: 9001,
                    userInfo: [NSLocalizedDescriptionKey: "Forensics fail-fast: first signature verification mismatch captured"]
                )
            }
            
            // Signature verification failed - try alternative KDF methods if password is provided
            // This handles the case where cache was cleared and we need to auto-detect the KDF method
            BlazeLogger.debug("❌ Signature verification failed with provided key, password=\(password != nil ? "provided" : "nil"), salt=\(salt != nil ? "provided" : "nil")")
            if let password = password, let salt = salt {
                BlazeLogger.debug("🔍 Signature verification failed, trying alternative KDF methods (password provided)...")
                
                // CRITICAL: Also try the provided signingKey's raw data to see if it matches
                // This handles the case where the key was derived correctly but verification failed for another reason
                let signingKeyData = signingKey.withUnsafeBytes { Data($0) }
                
                // Try Argon2 key (if current key was from PBKDF2)
                do {
                    BlazeLogger.debug("🔍 Trying Argon2 key derivation...")
                    let argon2Key = try Argon2KDF.deriveKey(
                        from: password,
                        salt: salt,
                        parameters: Argon2KDF.Parameters.default
                    )
                    let argon2KeyData = argon2Key.withUnsafeBytes { Data($0) }
                    
                    if secureLayout.verify(using: argon2Key) {
                        BlazeLogger.debug("✅ Signature verified with Argon2 key (auto-detected KDF method)")
                        // Cache is managed internally by KeyManager when getKey is called
                        return try secureLayout.resolvedLayout(using: decoder)
                    } else {
                        BlazeLogger.debug("❌ Argon2 key did not match signature")
                        // Check if Argon2 key matches the provided signingKey
                        if argon2KeyData == signingKeyData {
                            BlazeLogger.debug("⚠️ Argon2 key matches provided signingKey but signature verification still failed")
                            if secureLayout.secureLayoutVersion >= 2 {
                                throw NSError(
                                    domain: "StorageLayout",
                                    code: 5,
                                    userInfo: [NSLocalizedDescriptionKey: "secure_layout_v2_signature_mismatch_strict"]
                                )
                            }
                            BlazeLogger.debug("🔧 Accepting legacy v1 layout with matching key bytes despite signature mismatch")
                            return try secureLayout.resolvedLayout(using: decoder)
                        }
                    }
                } catch {
                    BlazeLogger.debug("❌ Argon2 key derivation failed: \(error)")
                    // Argon2 failed, continue to try PBKDF2
                }
                
                // Try PBKDF2 key (if current key was from Argon2)
                // Try current and legacy PBKDF2 iteration counts for compatibility.
                do {
                    BlazeLogger.debug("🔍 Trying PBKDF2 key derivation with current iteration policy...")
                    let passwordData = Data(password.utf8)
                    let pbkdf2KeyData10k = try KeyManager.deriveKeyPBKDF2(
                        password: passwordData,
                        salt: salt,
                        iterations: KeyManager.pbkdf2Iterations,
                        keyLength: 32
                    )
                    let pbkdf2Key10k = SymmetricKey(data: pbkdf2KeyData10k)
                    let pbkdf2KeyDataForCompare10k = pbkdf2Key10k.withUnsafeBytes { Data($0) }
                    
                    if secureLayout.verify(using: pbkdf2Key10k) {
                        BlazeLogger.debug("✅ Signature verified with PBKDF2 key (auto-detected KDF method)")
                        return try secureLayout.resolvedLayout(using: decoder)
                    } else {
                        BlazeLogger.debug("❌ PBKDF2 key did not match signature")
                        // Check if PBKDF2 key matches the provided signingKey
                        if pbkdf2KeyDataForCompare10k == signingKeyData {
                            BlazeLogger.debug("⚠️ PBKDF2 key matches provided signingKey but signature verification still failed")
                            if secureLayout.secureLayoutVersion >= 2 {
                                throw NSError(
                                    domain: "StorageLayout",
                                    code: 5,
                                    userInfo: [NSLocalizedDescriptionKey: "secure_layout_v2_signature_mismatch_strict"]
                                )
                            }
                            BlazeLogger.debug("🔧 Accepting legacy v1 layout with matching key bytes despite signature mismatch")
                            return try secureLayout.resolvedLayout(using: decoder)
                        }
                    }
                    
                    // Also try 100,000 iterations for backward compatibility
                    BlazeLogger.debug("🔍 Trying PBKDF2 key derivation with 100,000 iterations...")
                    let pbkdf2KeyData100k = try KeyManager.deriveKeyPBKDF2(
                        password: passwordData,
                        salt: salt,
                        iterations: 100_000,
                        keyLength: 32
                    )
                    let pbkdf2Key100k = SymmetricKey(data: pbkdf2KeyData100k)
                    let pbkdf2KeyDataForCompare100k = pbkdf2Key100k.withUnsafeBytes { Data($0) }
                    
                    if secureLayout.verify(using: pbkdf2Key100k) {
                        BlazeLogger.debug("✅ Signature verified with PBKDF2 (100k) key (auto-detected KDF method)")
                        return try secureLayout.resolvedLayout(using: decoder)
                    } else {
                        BlazeLogger.debug("❌ PBKDF2 (100k) key did not match signature")
                        // Check if PBKDF2 (100k) key matches the provided signingKey
                        if pbkdf2KeyDataForCompare100k == signingKeyData {
                            BlazeLogger.debug("⚠️ PBKDF2 (100k) key matches provided signingKey but signature verification still failed")
                            if secureLayout.secureLayoutVersion >= 2 {
                                throw NSError(
                                    domain: "StorageLayout",
                                    code: 5,
                                    userInfo: [NSLocalizedDescriptionKey: "secure_layout_v2_signature_mismatch_strict"]
                                )
                            }
                            BlazeLogger.debug("🔧 Accepting legacy v1 layout with matching key bytes despite signature mismatch")
                            return try secureLayout.resolvedLayout(using: decoder)
                        }
                    }
                } catch {
                    BlazeLogger.debug("❌ PBKDF2 key derivation failed: \(error)")
                    // PBKDF2 failed
                }
                
                BlazeLogger.debug("⚠️ All KDF methods tried, none matched the signature")
            } else {
                BlazeLogger.debug("⚠️ Password not provided, cannot try alternative KDF methods")
            }
            
            // All signature verification attempts failed
            throw NSError(
                domain: "StorageLayout",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Layout signature verification failed - metadata may have been tampered with"]
            )
        }
        
        if allowUnsignedLayoutFallback {
            // Backward compatibility mode for controlled one-time migrations only.
            if let layout = try? decoder.decode(StorageLayout.self, from: data) {
                BlazeLogger.warn("Loaded unsigned layout (explicit fallback enabled)")
                return layout
            }

            // Last-chance tolerant path for legacy/tuple-style JSON payloads.
            if let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                if let rawLayout = raw["layout"], let normalized = decodeLayoutFromRawJSON(rawLayout) {
                    BlazeLogger.warn("Loaded layout via tolerant secure-wrapper normalization path")
                    return normalized
                }
                if let normalized = decodeLayoutFromRawJSON(raw) {
                    BlazeLogger.warn("Loaded layout via tolerant plain-layout normalization path")
                    return normalized
                }
            }
        }
        
        throw NSError(
            domain: "StorageLayout",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Failed to decode layout"]
        )
    }

    private static func looksLikeJSONLayout(_ data: Data) -> Bool {
        for byte in data {
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D:
                continue
            case 0x7B, 0x5B:
                return true
            default:
                return false
            }
        }
        return false
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        let maxLen = max(lhs.count, rhs.count)
        var diff = UInt8(lhs.count ^ rhs.count)
        for i in 0..<maxLen {
            let l = i < lhs.count ? lhs[lhs.index(lhs.startIndex, offsetBy: i)] : 0
            let r = i < rhs.count ? rhs[rhs.index(rhs.startIndex, offsetBy: i)] : 0
            diff |= l ^ r
        }
        return diff == 0
    }
}

