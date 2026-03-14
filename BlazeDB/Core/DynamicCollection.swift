//  DynamicCollection.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// MARK: - Constants

private extension DynamicCollection {
    /// Default salt for key derivation (ASCII string, UTF-8 encoding guaranteed)
    static var defaultSalt: Data {
        // "AshPileSalt" is ASCII, so UTF-8 encoding cannot fail
        return Data("AshPileSalt".utf8)
    }

    static var writeForensicsEnabled: Bool {
        ProcessInfo.processInfo.environment["BLAZEDB_FORENSICS"] == "1"
            || CommandLine.arguments.contains("--forensics-insert-profile")
    }

    static func monotonicNowMs() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000.0
    }

    struct InsertTimingRecord: Codable {
        let schema: Int
        let encodeMs: Double
        let lockWaitMs: Double
        let fileAppendMs: Double
        let fsyncMs: Double
        let indexUpdateMs: Double
        let totalMs: Double

        private enum CodingKeys: String, CodingKey {
            case schema
            case encodeMs = "encode_ms"
            case lockWaitMs = "lock_wait_ms"
            case fileAppendMs = "file_append_ms"
            case fsyncMs = "fsync_ms"
            case indexUpdateMs = "index_update_ms"
            case totalMs = "total_ms"
        }
    }

    static func emitInsertTiming(_ record: InsertTimingRecord) {
        guard writeForensicsEnabled else { return }
        let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".blaze/forensics", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let outFile = outDir.appendingPathComponent("insert_timing.jsonl")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let lineData = try? encoder.encode(record),
              let line = String(data: lineData, encoding: .utf8) else {
            return
        }

        let payload = (line + "\n").data(using: .utf8) ?? Data()
        if FileManager.default.fileExists(atPath: outFile.path),
           let fh = try? FileHandle(forWritingTo: outFile) {
            defer { try? fh.close() }
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: payload)
        } else {
            try? payload.write(to: outFile)
        }
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
    nonisolated(unsafe) internal static let cachedISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    /// Stable identity for cache keying. ObjectIdentifier (memory address) is unsafe because
    /// a deallocated collection's address can be reused by a new instance, returning stale cache.
    internal let instanceID = UUID()

    internal var indexMap: [UUID: [Int]] = [:]  // Changed to support overflow chains
    internal let store: PageStore
    internal let metaURL: URL
    internal var nextPageIndex: Int = 0
    internal var cachedDeletedPages: [Int] = []
    internal var secondaryIndexes: [String: [CompoundIndexKey: Set<UUID>]] = [:]
    internal let project: String
    internal let queue = DispatchQueue(label: "com.yourorg.blazedb.dynamiccollection", attributes: .concurrent)
    internal let encryptionKey: SymmetricKey
    internal var password: String?  // Cleared on close to reduce plaintext lifetime
    internal let kdfSalt: Data
    
    /// Per-database record cache (isolates rollback effects between databases)
    public let recordCache: RecordCache
    
    /// B-tree indexes for range queries (greaterThan, lessThan, between)
    public let btreeIndexManager: BTreeIndexManager
    
    // MVCC: Version management for concurrent access
    internal let versionManager: VersionManager
    // MVCC is enabled by default for better concurrency and data integrity
    // Version persistence to disk is implemented, so MVCC is safe to use
    internal var mvccEnabled: Bool = false  // Disabled by default; opt-in via setMVCCEnabled(_:)
    internal lazy var gcManager: AutomaticGCManager = {
        AutomaticGCManager(versionManager: versionManager)
    }()
    
    // Performance optimization: Batch metadata writes
    internal var unsavedChanges = 0
    private let metadataFlushThreshold = 100  // Save every 100 operations (balance between performance and safety)
    
    // Cached search index to avoid reloading from disk on every save
    internal var cachedSearchIndex: InvertedIndex?
    internal var cachedSearchIndexedFields: [String] = []
    
    // Cached vector index (pure Swift, no Objective-C runtime)
    // Stored directly on DynamicCollection instance - thread-safe via queue synchronization
    internal var _vectorIndex: VectorIndex?
    internal var cachedVectorIndexedField: String?
    
    // Cached spatial index (pure Swift, no Objective-C runtime)
    // Stored directly on DynamicCollection instance - thread-safe via queue synchronization
    internal var cachedSpatialIndex: SpatialIndex?
    internal var cachedSpatialIndexedFields: (latField: String, lonField: String)?
    
    // Store encodingFormat in memory to avoid loading from disk during saveLayout()
    // This prevents signature verification failures during concurrent operations
    internal var encodingFormat: String = "blazeBinary"
    
    // Store secondaryIndexDefinitions in memory so saveLayout() can preserve them
    // This prevents signature verification failures when createIndex saves, then persist() saves again
    internal var secondaryIndexDefinitions: [String: [String]] = [:]
    
    // Track whether layout signature verification succeeded
    private var layoutSignatureVerified: Bool = true
    private var closed: Bool = false
    
    private func applyLayoutFromStorage(_ layout: StorageLayout) {
        // StorageLayout.indexMap is already [UUID: [Int]], no conversion needed
        self.indexMap = layout.indexMap
        self.nextPageIndex = layout.nextPageIndex
        self.cachedDeletedPages = layout.deletedPages
        self.secondaryIndexes = layout.toRuntimeIndexes()
        self.cachedSearchIndex = layout.searchIndex
        self.cachedSearchIndexedFields = layout.searchIndexedFields
        self.encodingFormat = layout.encodingFormat.isEmpty ? "blazeBinary" : layout.encodingFormat
        self.secondaryIndexDefinitions = layout.secondaryIndexDefinitions
        BlazeLogger.debug("applyLayoutFromStorage: Loaded indexMap with \(self.indexMap.count) entries")
        rebuildMVCCFromIndexMapIfNeeded()
    }
    
    private func rebuildMVCCFromIndexMapIfNeeded() {
        guard mvccEnabled, !self.indexMap.isEmpty else { return }
        
        BlazeLogger.debug("🔄 [MVCC] Rebuilding version manager from \(self.indexMap.count) records in indexMap...")
        let baseVersion = max(versionManager.getCurrentVersion(), 1)
        
        for (recordID, pageIndices) in self.indexMap {
            guard let firstPageIndex = pageIndices.first else { continue }
            let version = RecordVersion(
                recordID: recordID,
                version: baseVersion,
                pageNumber: firstPageIndex,
                createdAt: Date(),
                deletedAt: nil,
                createdByTransaction: baseVersion,
                deletedByTransaction: 0
            )
            versionManager.addVersion(version)
        }
        
        let currentAfterRebuild = versionManager.getCurrentVersion()
        if currentAfterRebuild < baseVersion {
            for _ in currentAfterRebuild..<baseVersion {
                _ = versionManager.nextVersion()
            }
        }
        
        let finalVersion = versionManager.getCurrentVersion()
        BlazeLogger.debug("🔄 [MVCC] ✅ Rebuilt version manager with \(versionManager.getAllVisibleRecordIDs(snapshot: finalVersion).count) visible records (baseVersion=\(baseVersion), finalVersion=\(finalVersion))")
    }
    
    /// Publicly expose the metaURL
    public var metaURLPath: URL {
        return metaURL
    }
    
    /// Publicly expose the store's fileURL
    public var fileURL: URL {
        return store.fileURL
    }
    
    public init(
        store: PageStore,
        metaURL: URL,
        project: String,
        encryptionKey: SymmetricKey,
        password: String? = nil,
        kdfSalt: Data? = nil
    ) throws {
        // CRITICAL: Validate project name to prevent path traversal attacks
        // Project names should not contain path traversal characters or null bytes
        guard !project.contains("../") && !project.contains("..\\") && !project.contains("\0") else {
            throw NSError(domain: "DynamicCollection", code: 4001, userInfo: [
                NSLocalizedDescriptionKey: "Invalid project name: contains path traversal characters or null bytes"
            ])
        }
        guard !project.isEmpty && project.count <= 255 else {
            throw NSError(domain: "DynamicCollection", code: 4002, userInfo: [
                NSLocalizedDescriptionKey: "Invalid project name: must be non-empty and <= 255 characters"
            ])
        }
        
        self.store = store
        self.metaURL = metaURL
        self.project = project
        self.encryptionKey = encryptionKey
        self.password = password  // Store password for KDF auto-detection
        self.kdfSalt = kdfSalt ?? Self.defaultSalt
        self.versionManager = VersionManager()  // Initialize MVCC
        
        // Per-database record cache (isolated from other databases)
        self.recordCache = RecordCache.forDatabase(store.fileURL.path)
        
        // B-tree index manager for range queries
        self.btreeIndexManager = BTreeIndexManager()
        
        // Double-check file doesn't exist and remove if it does (defensive)
        _ = FileManager.default.fileExists(atPath: metaURL.path)  // Check existence (result not needed)
        
        // Note: We don't remove existing meta files here - they should be loaded if valid
        // Test cleanup helpers handle aggressive cleanup in test scenarios
        
        let layoutExists = FileManager.default.fileExists(atPath: metaURL.path)
        
        BlazeLogger.debug("🔷 [INIT] DynamicCollection init for project: \(project)")
        BlazeLogger.debug("🔷 [INIT] Meta URL: \(metaURL.path)")
        BlazeLogger.debug("🔷 [INIT] Layout file exists: \(layoutExists)")
        
        if layoutExists {
            BlazeLogger.info("📋 [INIT] Found existing layout file - loading from previous session...")
            do {
                // SECURITY: Load layout with HMAC signature verification
                // If password is provided, try alternative KDF methods if signature verification fails
                BlazeLogger.debug("Attempting to load secure layout with signature verification...")
                let layout = try StorageLayout.loadSecure(
                    from: metaURL,
                    signingKey: encryptionKey,
                    password: password,
                    salt: self.kdfSalt
                )
                BlazeLogger.debug("Layout loaded and verified successfully")
                layoutSignatureVerified = true
                applyLayoutFromStorage(layout)
                
                // Debug: Log loaded indexes
                BlazeLogger.info("🔍 [INIT] Loaded \(self.secondaryIndexes.count) indexes from layout")
                for (indexName, inner) in self.secondaryIndexes {
                    BlazeLogger.info("🔍 [INIT]   Index '\(indexName)': \(inner.count) keys, \(inner.values.reduce(0) { $0 + $1.count }) total UUIDs")
                }
                
                BlazeLogger.info("Loaded encodingFormat from layout: '\(layout.encodingFormat)' -> stored as '\(self.encodingFormat)'")
                
                BlazeLogger.info("🔍 [INIT] Loaded \(self.secondaryIndexDefinitions.count) index definitions: \(self.secondaryIndexDefinitions.keys.joined(separator: ", "))")
                
                BlazeLogger.debug("DynamicCollection init: Loaded layout with \(self.indexMap.count) records, nextPageIndex=\(self.nextPageIndex)")
                
                // ✅ FIXED: Auto-migration now stores format in JSON field, not as binary prefix
                do {
                    BlazeLogger.debug("🔄 [INIT] Running auto-migration check...")
                    try self.performAutoMigrationIfNeeded()
                    BlazeLogger.debug("🔄 [INIT] ✅ Auto-migration completed")
                } catch {
                    BlazeLogger.error("🔄 [INIT] ❌ AutoMigration error: \(error)")
                    BlazeLogger.error("🔄 [INIT] Wrapping as migrationFailed error")
                    throw BlazeDBError.migrationFailed("❌ Migration failed: \(error.localizedDescription)", underlyingError: error)
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
                    BlazeLogger.info("🔍 [INIT] Checking if indexes need rebuild: \(self.indexMap.count) records, \(layout.secondaryIndexDefinitions.count) definitions")
                    for (compoundKey, fields) in layout.secondaryIndexDefinitions {
                        let needsRebuild: Bool = {
                            guard let inner = self.secondaryIndexes[compoundKey] else {
                                BlazeLogger.info("🔍 [INIT] Index '\(compoundKey)' is missing, needs rebuild")
                                return true
                            }
                            let isEmpty = inner.isEmpty
                            if isEmpty {
                                BlazeLogger.info("🔍 [INIT] Index '\(compoundKey)' is empty, needs rebuild")
                            } else {
                                BlazeLogger.info("🔍 [INIT] Index '\(compoundKey)' has \(inner.count) keys, no rebuild needed")
                            }
                            return isEmpty
                        }()
                        if needsRebuild {
                            BlazeLogger.info("Rebuilding index '\(compoundKey)' on fields: \(fields.joined(separator: ", "))")
                            var indexEntries: [CompoundIndexKey: Set<UUID>] = [:]
                            var unreadableRecords = 0
                            var abortedRebuild = false
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
                                        case .vector(let v): return AnyBlazeCodable(v)
                                        case .null: return AnyBlazeCodable("")
                                            case .array, .dictionary: return AnyBlazeCodable("")  // Arrays/dicts not supported in compound indexes
                                        }
                                    }
                                    let indexKey = CompoundIndexKey(normalizedComponents)
                                    var set = indexEntries[indexKey] ?? Set<UUID>()
                                    set.insert(id)
                                    indexEntries[indexKey] = set
                                } else {
                                    unreadableRecords += 1
                                    // Fail fast: a poisoned store can make init spend seconds rebuilding indexes
                                    // from unreadable records. Abort rebuild and keep runtime responsive.
                                    if unreadableRecords >= 1 {
                                        abortedRebuild = true
                                        BlazeLogger.warn("⚠️ [INIT] Aborting rebuild for index '\(compoundKey)' after \(unreadableRecords) unreadable records (total records: \(self.indexMap.count))")
                                        break
                                    }
                                }
                            }
                            if abortedRebuild {
                                // Keep existing index state (often empty) and skip persistence churn.
                                continue
                            }
                            self.secondaryIndexes[compoundKey] = indexEntries
                            didRebuildAny = true
                            BlazeLogger.info("✅ Rebuilt index '\(compoundKey)' with \(indexEntries.count) keys")
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
                BlazeLogger.error("Failed to load layout from disk: \(error.localizedDescription) (type: \(type(of: error)), domain: \((error as NSError).domain), code: \((error as NSError).code))")
                BlazeLogger.error("Meta file path: \(metaURL.path), exists: \(FileManager.default.fileExists(atPath: metaURL.path))")
                
                // Try to extract index definitions from corrupted meta file BEFORE deleting it
                // (even if signature verification fails, we can still decode the JSON)
                var preservedIndexDefinitions: [String: [String]] = [:]
                var recoveredLayout: StorageLayout? = nil
                if FileManager.default.fileExists(atPath: metaURL.path) {
                    BlazeLogger.info("Attempting to extract index definitions from corrupted meta file...")
                    do {
                        let metaData = try Data(contentsOf: metaURL)
                        BlazeLogger.info("Meta file size: \(metaData.count) bytes")
                        // Try JSON parsing first (most reliable, doesn't require full decode)
                        if let json = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] {
                            BlazeLogger.info("Successfully parsed JSON, top-level keys: \(json.keys.joined(separator: ", "))")
                            
                            // Check if it's a SecureLayout structure (has "layout" key)
                            if let layoutDict = json["layout"] as? [String: Any] {
                                BlazeLogger.info("Found 'layout' key in JSON (SecureLayout structure)")
                                if let indexDefs = layoutDict["secondaryIndexDefinitions"] as? [String: [String]] {
                                    preservedIndexDefinitions = indexDefs
                                    BlazeLogger.info("Preserved \(preservedIndexDefinitions.count) index definitions from SecureLayout JSON: \(preservedIndexDefinitions.keys.joined(separator: ", "))")
                                } else {
                                    BlazeLogger.warn("'layout' dict found but no secondaryIndexDefinitions key")
                                    let layoutKeys = Set(layoutDict.keys)
                                    BlazeLogger.info("Layout keys: \(layoutKeys.joined(separator: ", "))")
                                }
                            }
                            // Or if it's a plain StorageLayout (has secondaryIndexDefinitions at top level)
                            else if let indexDefs = json["secondaryIndexDefinitions"] as? [String: [String]] {
                                preservedIndexDefinitions = indexDefs
                                BlazeLogger.info("Preserved \(preservedIndexDefinitions.count) index definitions from plain StorageLayout JSON: \(preservedIndexDefinitions.keys.joined(separator: ", "))")
                            }
                        }
                        
                        // If JSON parsing didn't work or didn't find index definitions, try Codable decoding
                        if preservedIndexDefinitions.isEmpty {
                            let decoder = JSONDecoder()
                            
                            // Strategy 1: Try SecureLayout
                            if let secureLayout = try? decoder.decode(StorageLayout.SecureLayout.self, from: metaData) {
                                recoveredLayout = secureLayout.layout
                                preservedIndexDefinitions = secureLayout.layout.secondaryIndexDefinitions
                                BlazeLogger.info("Preserved \(preservedIndexDefinitions.count) index definitions from SecureLayout: \(preservedIndexDefinitions.keys.joined(separator: ", "))")
                            }
                            // Strategy 2: Try plain StorageLayout (backward compatibility)
                            else if let layout = try? decoder.decode(StorageLayout.self, from: metaData) {
                                recoveredLayout = layout
                                preservedIndexDefinitions = layout.secondaryIndexDefinitions
                                BlazeLogger.info("Decoded as plain StorageLayout with \(layout.secondaryIndexDefinitions.count) index definitions")
                                if !layout.secondaryIndexDefinitions.isEmpty {
                                    BlazeLogger.info("Preserved \(preservedIndexDefinitions.count) index definitions from plain StorageLayout: \(preservedIndexDefinitions.keys.joined(separator: ", "))")
                                } else {
                                    BlazeLogger.warn("Plain StorageLayout decoded but secondaryIndexDefinitions is empty")
                                }
                            }
                        }
                        
                        // Final fallback: Try to extract index definitions using string search
                        // This works even if JSON is partially corrupted
                        if preservedIndexDefinitions.isEmpty {
                            // Try to find "secondaryIndexDefinitions" in the raw data
                            if let jsonString = String(data: metaData, encoding: .utf8) {
                                // Look for the secondaryIndexDefinitions key and try to extract its value
                                if let defsRange = jsonString.range(of: "\"secondaryIndexDefinitions\""),
                                   let colonRange = jsonString.range(of: ":", range: defsRange.upperBound..<jsonString.endIndex),
                                   let openBraceRange = jsonString.range(of: "{", range: colonRange.upperBound..<jsonString.endIndex) {
                                    
                                    // Try to extract the dictionary content
                                    var braceCount = 1
                                    var currentPos = openBraceRange.upperBound
                                    var endPos = currentPos
                                    
                                    while braceCount > 0 && currentPos < jsonString.endIndex {
                                        let char = jsonString[currentPos]
                                        if char == "{" {
                                            braceCount += 1
                                        } else if char == "}" {
                                            braceCount -= 1
                                            if braceCount == 0 {
                                                endPos = jsonString.index(after: currentPos)
                                                break
                                            }
                                        }
                                        currentPos = jsonString.index(after: currentPos)
                                    }
                                    
                                    if braceCount == 0 {
                                        let dictString = String(jsonString[openBraceRange.lowerBound..<endPos])
                                        // Try to parse just this dictionary
                                        if let dictData = dictString.data(using: .utf8),
                                           let dict = try? JSONSerialization.jsonObject(with: dictData) as? [String: Any] {
                                            // Convert to [String: [String]] format
                                            var extracted: [String: [String]] = [:]
                                            for (key, value) in dict {
                                                if let fields = value as? [String] {
                                                    extracted[key] = fields
                                                } else if let fieldsArray = value as? [Any] {
                                                    extracted[key] = fieldsArray.compactMap { $0 as? String }
                                                }
                                            }
                                            if !extracted.isEmpty {
                                                preservedIndexDefinitions = extracted
                                                BlazeLogger.info("Extracted \(extracted.count) index definitions using string search")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // If still empty, try to see if it's valid JSON at all
                            if preservedIndexDefinitions.isEmpty {
                                if let jsonString = String(data: metaData.prefix(200), encoding: .utf8) {
                                    BlazeLogger.warn("Failed to parse as JSON. First 200 bytes: \(jsonString)")
                                } else {
                                    BlazeLogger.warn("Failed to decode or parse meta file - not valid JSON or UTF-8")
                                }
                            }
                        }
                    } catch {
                        BlazeLogger.warn("Could not extract index definitions from corrupted meta file: \(error)")
                    }
                } else {
                    BlazeLogger.warn("Meta file does not exist, cannot extract index definitions")
                }
                
                let nsError = error as NSError
                let isSignatureFailure = nsError.domain == "StorageLayout" && nsError.code == 1
                
                if isSignatureFailure {
                    BlazeLogger.error("SIGNATURE VERIFICATION FAILURE: The .meta file was created with a different password or is corrupted. Solution: Delete the .meta file and recreate the database.")
                    BlazeLogger.error("Running in read-only compatibility mode (layout will not be saved)")
                    
                    layoutSignatureVerified = false
                    
                    var fallbackLayout = recoveredLayout ?? StorageLayout.empty()
                    if !preservedIndexDefinitions.isEmpty {
                        fallbackLayout.secondaryIndexDefinitions = preservedIndexDefinitions
                    }
                    applyLayoutFromStorage(fallbackLayout)
                } else {
                    // Non-signature corruption: delete and rebuild
                    BlazeLogger.error("❌ [INIT] Deleting corrupted file and rebuilding from data...")
                    do {
                        try FileManager.default.removeItem(at: metaURL)
                        BlazeLogger.info("✅ [INIT] Successfully deleted corrupted meta file")
                    } catch let deleteError {
                        BlazeLogger.error("❌ [INIT] Failed to delete meta file: \(deleteError)")
                    }
                    
                    // Try to rebuild layout from data file by scanning and decoding all records
                    BlazeLogger.info("📋 [INIT] Attempting to rebuild layout from data file...")
                    do {
                        var rebuiltIndexMap: [UUID: [Int]] = [:]
                        var rebuiltNextPageIndex = 0
                        var pageIndex = 0
                        
                        // Scan all pages and decode records to rebuild indexMap
                        // Use a more efficient approach: scan until we hit consecutive empty pages
                        var consecutiveEmptyPages = 0
                        let maxConsecutiveEmpty = 10  // Stop after 10 consecutive empty pages
                        
                        while consecutiveEmptyPages < maxConsecutiveEmpty {
                            do {
                                // Try to read page (with overflow support)
                                guard let data = try store.readPageWithOverflow(index: pageIndex),
                                      !data.isEmpty,
                                      !data.allSatisfy({ $0 == 0 }) else {
                                    // Empty page
                                    consecutiveEmptyPages += 1
                                    rebuiltNextPageIndex = max(rebuiltNextPageIndex, pageIndex + 1)
                                    pageIndex += 1
                                    continue
                                }
                                
                                // Found non-empty page, reset counter
                                consecutiveEmptyPages = 0
                                
                                // Try to decode the record to get its ID
                                do {
                                    let record = try BlazeBinaryDecoder.decode(data)
                                    // Extract UUID from record - try "id" field first
                                    var recordID: UUID? = record.storage["id"]?.uuidValue
                                    
                                    // If no "id" field, check if record was inserted with auto-generated ID
                                    // (This shouldn't happen, but handle it gracefully)
                                    if recordID == nil {
                                        // Try to find any UUID field that might be the ID
                                        for (key, field) in record.storage {
                                            if key.lowercased() == "id" || key.lowercased().hasSuffix("id") {
                                                recordID = field.uuidValue
                                                break
                                            }
                                        }
                                    }
                                    
                                    if let id = recordID {
                                        if rebuiltIndexMap[id] == nil {
                                            rebuiltIndexMap[id] = [pageIndex]
                                        } else {
                                            rebuiltIndexMap[id]?.append(pageIndex)
                                        }
                                    } else {
                                        BlazeLogger.debug("Page \(pageIndex) decoded but has no ID field")
                                    }
                                } catch {
                                    // Not a valid record, skip this page
                                    BlazeLogger.debug("Page \(pageIndex) is not a valid record: \(error)")
                                }
                                
                                rebuiltNextPageIndex = max(rebuiltNextPageIndex, pageIndex + 1)
                                pageIndex += 1
                            } catch {
                                // Can't read page - might be end of file or invalid index
                                consecutiveEmptyPages += 1
                                if consecutiveEmptyPages >= maxConsecutiveEmpty {
                                    break
                                }
                                pageIndex += 1
                            }
                        }
                        
                        // Update properties from rebuilt layout
                        self.indexMap = rebuiltIndexMap
                        self.nextPageIndex = rebuiltNextPageIndex
                        // Secondary indexes will be empty after rebuild (will be rebuilt below if definitions exist)
                        self.secondaryIndexes = [:]
                        self.cachedSearchIndex = nil
                        self.cachedSearchIndexedFields = []
                        
                        // Restore index definitions and rebuild indexes if we preserved them
                        if !preservedIndexDefinitions.isEmpty {
                            BlazeLogger.info("Rebuilding \(preservedIndexDefinitions.count) indexes from preserved definitions...")
                            self.secondaryIndexDefinitions = preservedIndexDefinitions
                            // Rebuild indexes using same normalization as createIndex()
                            for (indexKey, fields) in preservedIndexDefinitions {
                                BlazeLogger.info("Rebuilding index '\(indexKey)' on fields: \(fields.joined(separator: ", "))")
                                var rebuilt: [CompoundIndexKey: Set<UUID>] = [:]
                                for id in rebuiltIndexMap.keys {
                                    if let record = try? self._fetchNoSync(id: id) {
                                        let doc = record.storage
                                        // Use same normalization logic as createIndex() to ensure key format matches
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
                                            case .vector(let v): return AnyBlazeCodable(v)
                                            case .null: return AnyBlazeCodable("")
                                            case .array, .dictionary: return AnyBlazeCodable("")  // Arrays/dicts not supported in compound indexes
                                            }
                                        }
                                        let normalizedKey = CompoundIndexKey(normalizedComponents)
                                        rebuilt[normalizedKey, default: []].insert(id)
                                    }
                                }
                                self.secondaryIndexes[indexKey] = rebuilt
                                BlazeLogger.info("Rebuilt index '\(indexKey)' with \(rebuilt.count) keys, \(rebuilt.values.reduce(0) { $0 + $1.count }) total UUIDs")
                            }
                        } else {
                            // Last resort: Try to infer index definitions from data patterns
                            // Look for fields that are commonly indexed (frequently queried fields)
                            BlazeLogger.warn("No index definitions preserved, attempting to infer from data...")
                            
                            // Sample a few records to see what fields exist
                            var fieldFrequency: [String: Int] = [:]
                            let sampleSize = min(10, rebuiltIndexMap.count)
                            let sampleIDs = Array(rebuiltIndexMap.keys.prefix(sampleSize))
                            
                            for id in sampleIDs {
                                if let record = try? self._fetchNoSync(id: id) {
                                    for field in record.storage.keys {
                                        fieldFrequency[field, default: 0] += 1
                                    }
                                }
                            }
                            
                            // Common indexable field names (excluding system fields)
                            let systemFields = Set(["id", "createdAt", "updatedAt", "project", "deletedAt"])
                            let commonIndexFields = ["name", "email", "category", "type", "status", "userId", "user_id"]
                            
                            // Try to infer indexes for common field names that exist in most records
                            var inferredDefinitions: [String: [String]] = [:]
                            for field in commonIndexFields {
                                if !systemFields.contains(field),
                                   let frequency = fieldFrequency[field],
                                   frequency >= sampleSize / 2 {  // Field exists in at least half of sampled records
                                    inferredDefinitions[field] = [field]
                                    BlazeLogger.info("Inferred index on field '\(field)' (found in \(frequency)/\(sampleSize) sampled records)")
                                }
                            }
                            
                            if !inferredDefinitions.isEmpty {
                                self.secondaryIndexDefinitions = inferredDefinitions
                                // Rebuild indexes using inferred definitions
                                for (indexKey, fields) in inferredDefinitions {
                                    BlazeLogger.info("Rebuilding inferred index '\(indexKey)' on fields: \(fields.joined(separator: ", "))")
                                    var rebuilt: [CompoundIndexKey: Set<UUID>] = [:]
                                    for id in rebuiltIndexMap.keys {
                                        if let record = try? self._fetchNoSync(id: id) {
                                            let doc = record.storage
                                            guard fields.allSatisfy({ doc[$0] != nil }) else { continue }
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
                            case .vector(let v): return AnyBlazeCodable(v)
                            case .null: return AnyBlazeCodable("")
                                            case .array, .dictionary: return AnyBlazeCodable("")  // Arrays/dicts not supported in compound indexes
                            }
                                            }
                                            let normalizedKey = CompoundIndexKey(normalizedComponents)
                                            rebuilt[normalizedKey, default: []].insert(id)
                                        }
                                    }
                                    self.secondaryIndexes[indexKey] = rebuilt
                                    BlazeLogger.info("Rebuilt inferred index '\(indexKey)' with \(rebuilt.count) keys, \(rebuilt.values.reduce(0) { $0 + $1.count }) total UUIDs")
                                }
                            } else {
                                BlazeLogger.warn("Could not infer index definitions from data, indexes will be empty")
                            }
                        }
                        
                        BlazeLogger.info("✅ [INIT] Successfully rebuilt layout from data file: \(rebuiltIndexMap.count) records found")
                        // Save the rebuilt layout
                        try saveLayout()
                        BlazeLogger.info("✅ [INIT] Rebuilt layout saved successfully")
                    } catch let rebuildError {
                        BlazeLogger.error("❌ [INIT] Failed to rebuild layout: \(rebuildError)")
                        BlazeLogger.warn("⚠️ [INIT] Starting with empty layout (data may be lost)")
                        // Fallback to empty layout if rebuild fails
                        self.indexMap = [:]
                        self.nextPageIndex = 0
                        self.secondaryIndexes = [:]
                        self.cachedSearchIndex = nil
                        self.cachedSearchIndexedFields = []
                        try saveLayout()
                    }
                }
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
        internal init(
            store: PageStore,
            layout: StorageLayout,
            metaURL: URL,
            project: String,
            encryptionKey: SymmetricKey,
            password: String? = nil,
            kdfSalt: Data? = nil
        ) {
            // Initialize all stored properties first
            self.store = store
            self.metaURL = metaURL
            self.project = project
            self.encryptionKey = encryptionKey
            self.password = password
            self.kdfSalt = kdfSalt ?? Self.defaultSalt
            self.versionManager = VersionManager()  // Initialize MVCC
            
            // Per-database record cache (isolated from other databases)
            self.recordCache = RecordCache.forDatabase(store.fileURL.path)
            
            // B-tree index manager for range queries
            self.btreeIndexManager = BTreeIndexManager()
            
            // Convert [UUID: Int] to [UUID: [Int]] for backward compatibility
            // StorageLayout.indexMap is already [UUID: [Int]], no conversion needed
        self.indexMap = layout.indexMap
            self.nextPageIndex = layout.nextPageIndex
            // Start with persisted runtime indexes
            self.secondaryIndexes = layout.toRuntimeIndexes()
            
            // CRITICAL: Store secondaryIndexDefinitions and encodingFormat in memory
            // so saveLayout() can preserve them (prevents signature verification failures)
            self.secondaryIndexDefinitions = layout.secondaryIndexDefinitions
            self.encodingFormat = layout.encodingFormat.isEmpty ? "blazeBinary" : layout.encodingFormat
            
            // Cache search index (stored property)
            self.cachedSearchIndex = layout.searchIndex
            self.cachedSearchIndexedFields = layout.searchIndexedFields
            
            // Now we can access computed properties (spatial and vector indexes)
            // Cache spatial index (computed property via extension)
            #if !BLAZEDB_LINUX_CORE
            // Vector and spatial indexes are handled by extensions in gated files
            // They will be rebuilt on first use via enableVectorIndex/enableSpatialIndex
            #endif
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
            
            // MVCC: Rebuild version manager from indexMap if MVCC is enabled
            // This ensures that count() and other MVCC operations work correctly after reload
            if mvccEnabled && !self.indexMap.isEmpty {
                BlazeLogger.debug("🔄 [MVCC] Rebuilding version manager from \(self.indexMap.count) records in indexMap...")
                // Ensure we have a valid version number (at least 1) for the records
                // If currentVersion is 0, we'll use version 1 for all records
                let baseVersion = max(versionManager.getCurrentVersion(), 1)
                // Set currentVersion to baseVersion to ensure future transactions see these records
                // Note: We can't directly set currentVersion, but we can ensure records use a valid version
                for (recordID, pageIndices) in self.indexMap {
                    guard let firstPageIndex = pageIndices.first else { continue }
                    // Create a version for each record in indexMap
                    // Use baseVersion (at least 1) so records are visible at any snapshot >= baseVersion
                    let version = RecordVersion(
                        recordID: recordID,
                        version: baseVersion,
                        pageNumber: firstPageIndex,
                        createdAt: Date(), // We don't have the original creation time, use current time
                        deletedAt: nil,
                        createdByTransaction: baseVersion,
                        deletedByTransaction: 0
                    )
                    versionManager.addVersion(version)
                }
                // After adding all versions, ensure currentVersion is at least baseVersion
                // This ensures future transactions will see these records
                // Note: We increment currentVersion by calling nextVersion() enough times
                // to get it past baseVersion
                let currentAfterRebuild = versionManager.getCurrentVersion()
                if currentAfterRebuild < baseVersion {
                    // Increment currentVersion to baseVersion by calling nextVersion()
                    for _ in currentAfterRebuild..<baseVersion {
                        _ = versionManager.nextVersion()
                    }
                }
                let finalVersion = versionManager.getCurrentVersion()
                BlazeLogger.debug("🔄 [MVCC] ✅ Rebuilt version manager with \(versionManager.getAllVisibleRecordIDs(snapshot: finalVersion).count) visible records (baseVersion=\(baseVersion), finalVersion=\(finalVersion))")
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
                
                // Rebuild index for all existing records
                BlazeLogger.debug("Rebuilding index '\(key)' for \(indexMap.count) existing records")
                for (id, pageIndices) in indexMap {
                    guard let firstPageIndex = pageIndices.first else { continue }
                    do {
                        // Read and decode record (use overflow-aware read)
                        let data = try store.readPageWithOverflow(index: firstPageIndex)
                        guard let data = data, !data.isEmpty else {
                            BlazeLogger.debug("No data found for record \(id) at page \(firstPageIndex)")
                            continue
                        }
                        
                        // Check if page is completely empty (all zeros)
                        guard !data.allSatisfy({ $0 == 0 }) else {
                            BlazeLogger.debug("Empty data for record \(id) at page \(firstPageIndex)")
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
                            case .vector(let v): return AnyBlazeCodable(v)
                            case .null: return AnyBlazeCodable("")
                                            case .array, .dictionary: return AnyBlazeCodable("")  // Arrays/dicts not supported in compound indexes
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
                
                // Update in-memory secondaryIndexDefinitions (will be saved by saveLayout() or persist())
                // This ensures signature verification passes when persist() is called after createIndex
                secondaryIndexDefinitions[key] = fields
                
                // Force save the layout to persist the index definition immediately
                // This uses saveLayout() which preserves all in-memory state including secondaryIndexDefinitions
                do {
                    BlazeLogger.info("Saving index definition for '\(key)'")
                    try saveLayout()
                    
                    // CRITICAL: Force file system sync to ensure layout is fully written before any subsequent reads
                    // This prevents signature verification failures when fetchMeta() is called immediately after
                    // CRITICAL: Use defer to ensure file handle is always closed, even if synchronizeFile() throws
                    if let fileHandle = FileHandle(forWritingAtPath: metaURL.path) {
                        defer {
                            fileHandle.closeFile()
                        }
                        fileHandle.synchronizeFile()
                    }
                    
                    BlazeLogger.info("Successfully saved index definition for '\(key)'")
                } catch {
                    BlazeLogger.error("Failed to persist index definition for '\(key)': \(error)")
                    throw BlazeDBError.invalidData(
                        reason: "Failed to create index on field(s) '\(key)': could not persist index definition to disk. Ensure the database file is writable and the disk is not full, then retry createIndex(on:)."
                    )
                }
            }
        }
        
        public func createIndex(on field: String) throws {
            try createIndex(on: [field])
        }
        
        /// Creates a B-tree index for range queries on a field
        /// B-tree indexes support: greaterThan, lessThan, greaterThanOrEqual, lessThanOrEqual, between
        /// - Parameter field: The field to create a range index on
        /// - Note: This also creates a regular hash index for equality queries
        public func createRangeIndex(on field: String) throws {
            // First create regular hash index for equality
            try createIndex(on: field)
            
            // Then create B-tree index for range queries
            let btreeIndex = btreeIndexManager.getOrCreateIndex(for: field)
            
            // Populate from existing records
            queue.sync(flags: .barrier) {
                BlazeLogger.debug("Building B-tree range index for field '\(field)' on \(indexMap.count) records")
                
                for (id, pageIndices) in indexMap {
                    guard let firstPageIndex = pageIndices.first,
                          let data = try? store.readPageWithOverflow(index: firstPageIndex),
                          !data.isEmpty,
                          !data.allSatisfy({ $0 == 0 }),
                          let record = try? BlazeBinaryDecoder.decode(data) else {
                        continue
                    }
                    
                    if let value = record.storage[field] {
                        btreeIndex.insert(key: ComparableField(value), value: id)
                    }
                }
                
                BlazeLogger.info("✅ B-tree range index created for '\(field)' with \(btreeIndex.count) entries")
            }
        }
        
        /// Check if a B-tree range index exists for a field
        public func hasRangeIndex(for field: String) -> Bool {
            return btreeIndexManager.hasIndex(for: field)
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

                    // INSERT contract: explicit duplicate IDs must fail (use update/upsert for mutation).
                    if indexMap[id] != nil {
                        throw BlazeDBError.recordExists(
                            id: id,
                            suggestion: "Use upsert() to insert-or-update or update() for existing records."
                        )
                    }
                    
                    // Load layout to check for deleted pages that can be reused
                    var layout: StorageLayout
                    do {
                        layout = try StorageLayout.loadSecure(
                            from: metaURL,
                            signingKey: encryptionKey,
                            password: password,
                            salt: kdfSalt
                        )
                    } catch {
                        layout = try StorageLayout.load(from: metaURL)
                    }
                    
                    // Add deleted pages from layout to MVCC PageGarbageCollector for reuse
                    // This ensures pages deleted in legacy mode or persisted to disk are available for MVCC reuse
                    BlazeLogger.trace("📝 [INSERT] Single record insert: id=\(id.uuidString.prefix(8))")
                    if !layout.deletedPages.isEmpty {
                        for pageIdx in layout.deletedPages {
                            versionManager.pageGC.markPageObsolete(pageIdx)
                        }
                        BlazeLogger.debug("♻️ [MVCC INSERT] Added \(layout.deletedPages.count) deleted pages from layout to pageGC for reuse")
                        // Remove from layout.deletedPages since they're now in pageGC
                        layout.deletedPages.removeAll()
                        // Save layout to persist the change
                        if password != nil {
                            try layout.saveSecure(to: metaURL, signingKey: encryptionKey)
                        } else {
                            try layout.save(to: metaURL)
                        }
                    }
                    
                    // Create MVCC transaction
                    let tx = MVCCTransaction(versionManager: versionManager, pageStore: store)
                    let record = BlazeDataRecord(document)
                    try tx.write(recordID: id, record: record)
                    
                    // Get page number from indexMap (MVCC doesn't expose page numbers directly)
                    let pageNumber = indexMap[id]?.first
                    
                    let transactionID = tx.transactionID  // Capture transaction ID before commit
                    try tx.commit()
                    
                    // Trigger automatic GC (Phase 4)
                    gcManager.onTransactionCommit()
                    
                    // Also update old indexMap for compatibility (MVCC uses single page)
                    // Use page number from pending writes (most reliable)
                    if let pageNum = pageNumber {
                        indexMap[id] = [pageNum]
                        BlazeLogger.trace("📝 [INSERT] Single record: id=\(id.uuidString.prefix(8)), page=\(pageNum), indexMap now has \(indexMap.count) entries")
                    } else {
                        // Fallback: Try to get from version manager after commit
                        let currentVersion = versionManager.getCurrentVersion()
                        if let version = versionManager.getVersion(recordID: id, snapshot: currentVersion) {
                            indexMap[id] = [version.pageNumber]
                            BlazeLogger.trace("📝 [INSERT] Single record (fallback 1): id=\(id.uuidString.prefix(8)), page=\(version.pageNumber), indexMap now has \(indexMap.count) entries")
                        } else if let version = versionManager.getVersion(recordID: id, snapshot: transactionID) {
                            indexMap[id] = [version.pageNumber]
                            BlazeLogger.trace("📝 [INSERT] Single record (fallback 2): id=\(id.uuidString.prefix(8)), page=\(version.pageNumber), indexMap now has \(indexMap.count) entries")
                        } else if let version = versionManager.getVersion(recordID: id, snapshot: .max) {
                            indexMap[id] = [version.pageNumber]
                            BlazeLogger.trace("📝 [INSERT] Single record (fallback 3): id=\(id.uuidString.prefix(8)), page=\(version.pageNumber), indexMap now has \(indexMap.count) entries")
                        } else {
                            // This should never happen, but log a warning
                            BlazeLogger.warn("⚠️ [INSERT] Could not find version for record \(id) after insert (transactionID=\(transactionID), currentVersion=\(currentVersion)) - indexMap may be out of sync")
                        }
                    }
                    
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
                            case .vector(let v): return AnyBlazeCodable(v)
                            case .null: return AnyBlazeCodable("")
                                            case .array, .dictionary: return AnyBlazeCodable("")  // Arrays/dicts not supported in compound indexes
                            }
                        }
                        let indexKey = CompoundIndexKey(normalizedComponents)
                        var inner = secondaryIndexes[compound] ?? [:]
                        var set = inner[indexKey] ?? Set<UUID>()
                        set.insert(id)
                        inner[indexKey] = set
                        secondaryIndexes[compound] = inner
                    }
                    
                    // Update B-tree indexes for range query support
                    btreeIndexManager.indexRecord(id: id, fields: document)
                    
                    // Update search index if enabled
                    #if !BLAZEDB_LINUX_CORE
                    try? updateSearchIndexOnInsert(record)
                    
                    // Update spatial index if enabled
                    updateSpatialIndexOnInsert(record)
                    
                    // Update vector index if enabled
                    updateVectorIndexOnInsert(record)
                    #endif
                    
                    unsavedChanges += 1
                    BlazeLogger.trace("💾 [FLUSH] MVCC: unsavedChanges=\(unsavedChanges) (threshold: \(metadataFlushThreshold))")
                    if unsavedChanges >= metadataFlushThreshold {
                        BlazeLogger.debug("💾 [FLUSH] MVCC: Auto-flushing at \(unsavedChanges) unsaved changes")
                        try saveLayout()
                        unsavedChanges = 0
                        BlazeLogger.debug("💾 [FLUSH] MVCC: ✅ Auto-flush complete, unsavedChanges reset to 0")
                    }
                    
                    return id
                }
            }
            
            // Legacy Path: Original single-version implementation
            let lockRequestMs = Self.writeForensicsEnabled ? Self.monotonicNowMs() : 0.0
            return try queue.sync(flags: .barrier) {
                let forensicsEnabled = Self.writeForensicsEnabled
                let totalStartMs = Self.monotonicNowMs()
                let lockWaitMs = forensicsEnabled ? (Self.monotonicNowMs() - lockRequestMs) : 0.0
                var encodeMs = 0.0
                var fileAppendMs = 0.0
                var indexUpdateMs = 0.0
                var fsyncMs = 0.0

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
                // INSERT contract: explicit duplicate IDs must fail (use update/upsert for mutation).
                if indexMap[id] != nil {
                    throw BlazeDBError.recordExists(
                        id: id,
                        suggestion: "Use upsert() to insert-or-update or update() for existing records."
                    )
                }
                // Use BlazeBinaryEncoder for encoding (matches decoder!)
                // If lazy decoding is enabled, use v3 format with field table
                #if !BLAZEDB_LINUX_CORE
                // Lazy decoding handled by extensions when enabled
                // Currently disabled - use standard encoder
                #else
                // Lazy decoding not available on Linux
                #endif
                let tEncode = forensicsEnabled ? Self.monotonicNowMs() : 0
                let encoded = try BlazeBinaryEncoder.encode(BlazeDataRecord(document))
                if forensicsEnabled {
                    encodeMs += Self.monotonicNowMs() - tEncode
                }

                // Build a lightweight mutable layout snapshot from in-memory state.
                // This avoids reloading the signed meta file on every insert.
                var layout = StorageLayout(
                    indexMap: indexMap,
                    nextPageIndex: nextPageIndex,
                    secondaryIndexes: [:],
                    searchIndex: nil,
                    searchIndexedFields: []
                )
                layout.deletedPages = cachedDeletedPages
                
                // Allocate main page (reuses deleted pages if available)
                let mainPageIndex = allocatePage(layout: &layout)
                
                // CRITICAL: Check if this page is already in use BEFORE writing
                let conflictingIDs = indexMap.filter { $0.value.contains(mainPageIndex) && $0.key != id }.keys
                if !conflictingIDs.isEmpty {
                    BlazeLogger.error("allocatePage returned page \(mainPageIndex) that is already in use by: \(conflictingIDs.map { $0.uuidString.prefix(8) }.joined(separator: ", "))")
                    // Remove conflicting entries from indexMap (they're stale)
                    for conflictingID in conflictingIDs {
                        BlazeLogger.error("Removing stale indexMap entry for \(conflictingID.uuidString.prefix(8))")
                        indexMap.removeValue(forKey: conflictingID)
                    }
                }
                // Use overflow pages for large records - writePageWithOverflow handles splitting across pages
                let tPageWrite = forensicsEnabled ? Self.monotonicNowMs() : 0
                let pageIndices = try store.writePageWithOverflow(
                    index: mainPageIndex,
                    plaintext: encoded,
                    allocatePage: { [weak self] in
                        guard let self = self else { throw NSError(domain: "DynamicCollection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Collection deallocated"]) }
                        // Reuse deleted pages for overflow pages too
                        let overflowPage = self.allocatePage(layout: &layout)
                        // Check for conflicts on overflow pages too
                        let overflowConflicts = self.indexMap.filter { $0.value.contains(overflowPage) }.keys
                        if !overflowConflicts.isEmpty {
                            BlazeLogger.error("Overflow page \(overflowPage) conflict - removing stale entries")
                            for conflictID in overflowConflicts {
                                self.indexMap.removeValue(forKey: conflictID)
                            }
                        }
                        return overflowPage
                    }
                )
                if forensicsEnabled {
                    fileAppendMs += Self.monotonicNowMs() - tPageWrite
                }
                
                // Update nextPageIndex from layout (in case it was incremented by allocatePage)
                nextPageIndex = layout.nextPageIndex
                
                let tMetadata = forensicsEnabled ? Self.monotonicNowMs() : 0
                // Store all page indices (main page + overflow pages)
                indexMap[id] = pageIndices
                let value = document["value"]?.intValue ?? -1
                BlazeLogger.trace("📝 [INSERT] Legacy: Set indexMap[\(id.uuidString.prefix(8))] = \(pageIndices) (value: \(value))")
                BlazeLogger.debug("📝 [INSERT] Legacy: Set indexMap[\(id.uuidString.prefix(8))] = \(pageIndices) (mainPage: \(mainPageIndex), value: \(value))")
                
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
                                            case .vector(let v): return AnyBlazeCodable(v)
                                            case .null: return AnyBlazeCodable("")
                                            case .array, .dictionary: return AnyBlazeCodable("")  // Arrays/dicts not supported in compound indexes
                                        }
                    }
                    let indexKey = CompoundIndexKey(normalizedComponents)
                    var inner = secondaryIndexes[compound] ?? [:]
                    var set = inner[indexKey] ?? Set<UUID>()
                    set.insert(id)
                    inner[indexKey] = set
                    secondaryIndexes[compound] = inner
                }
                
                // Update B-tree indexes for range query support
                btreeIndexManager.indexRecord(id: id, fields: document)
                
                // Save layout with updated deletedPages and nextPageIndex
                layout.indexMap = indexMap
                layout.secondaryIndexes = StorageLayout.fromRuntimeIndexes(secondaryIndexes)
                if forensicsEnabled {
                    indexUpdateMs += Self.monotonicNowMs() - tMetadata
                }

                // Persist per-insert metadata update to preserve crash-prefix durability.
                let tFsync = forensicsEnabled ? Self.monotonicNowMs() : 0
                if password != nil {
                    try layout.saveSecure(to: metaURL, signingKey: encryptionKey)
                } else {
                    try layout.save(to: metaURL)
                }
                cachedDeletedPages = layout.deletedPages
                if forensicsEnabled {
                    fsyncMs += Self.monotonicNowMs() - tFsync
                }
                
                unsavedChanges += 1
                
                // Clear fetchAll cache after write
                #if !BLAZEDB_LINUX_CORE
                clearFetchAllCache()
                #endif
                
                // Batch metadata writes for performance (save every N operations)
                if unsavedChanges >= metadataFlushThreshold {
                    let tBatchSave = forensicsEnabled ? Self.monotonicNowMs() : 0
                    try saveLayout()
                    if forensicsEnabled {
                        fsyncMs += Self.monotonicNowMs() - tBatchSave
                    }
                    unsavedChanges = 0
                }
                
                // NEW: Update search index if enabled
                #if !BLAZEDB_LINUX_CORE
                let record = BlazeDataRecord(document)
                try? updateSearchIndexOnInsert(record)
                
                // NEW: Update spatial index if enabled
                updateSpatialIndexOnInsert(record)
                
                // NEW: Update vector index if enabled
                updateVectorIndexOnInsert(record)
                #endif

                if forensicsEnabled {
                    Self.emitInsertTiming(
                        InsertTimingRecord(
                            schema: 1,
                            encodeMs: encodeMs,
                            lockWaitMs: lockWaitMs,
                            fileAppendMs: fileAppendMs,
                            fsyncMs: fsyncMs,
                            indexUpdateMs: indexUpdateMs,
                            totalMs: Self.monotonicNowMs() - totalStartMs
                        )
                    )
                }
                
                return id
            }
        }
        
        /// Fetch a record by ID. Public version, synchronizes access via queue.
        public func fetch(id: UUID) throws -> BlazeDataRecord? {
            // MVCC Path: Use snapshot isolation (CONCURRENT READS! 🚀)
            if mvccEnabled {
                // CRITICAL: Use sync (not barrier) to wait for any pending writes to complete
                // This ensures that all versions registered in barrier blocks are visible
                // before we create a transaction and get a snapshot.
                // This is a read barrier - it waits for write barriers to complete, but
                // allows multiple concurrent reads.
                return try queue.sync {
                    // CRITICAL: Create transaction INSIDE the sync block to ensure proper ordering
                    // The sync block ensures all barrier blocks (writes) complete before we
                    // create a transaction and get a snapshot. This guarantees that all
                    // versions registered in barrier blocks are fully visible.
                    let tx = MVCCTransaction(versionManager: versionManager, pageStore: store)
                    let result = try tx.read(recordID: id)
                    return result
                }
            }
            
            // Legacy Path: Original single-version (serial)
            return try queue.sync {
                return try _fetchNoSync(id: id)
            }
        }
        
        /// Internal, non-synchronized version of fetch(id:). Must only be called from within queue.sync/barrier blocks.
        /// Used internally to avoid nested sync calls and potential deadlocks.
        internal func _fetchNoSync(id: UUID) throws -> BlazeDataRecord? {
            // Capture a snapshot of indexMap to avoid concurrent modification issues
            // This prevents crashes when indexMap is being modified by other threads
            // Swift dictionaries are value types, so assignment creates a copy
            // Note: This is called from within queue.sync, so we should be safe, but
            // taking a snapshot prevents issues if indexMap is replaced during access
            let indexMapSnapshot = indexMap  // Creates a copy (dictionaries are value types)
            
            // Check indexMap first to ensure record exists in this database instance
            // This prevents cache hits from other database instances
            guard let pageIndices = indexMapSnapshot[id], let firstPageIndex = pageIndices.first else {
                // Record not in indexMap - remove from cache if present (might be stale)
                recordCache.remove(id: id)
                return nil
            }
            
            // Check cache after verifying record exists in indexMap (fast path)
            // But verify the record still exists in indexMap before returning cached value
            // This prevents returning cached records that were deleted concurrently
            if let cached = recordCache.get(id: id) {
                // Double-check record still exists (might have been deleted after cache lookup)
                // Use snapshot to avoid concurrent access
                if indexMapSnapshot[id] != nil {
                    return cached
                } else {
                    // Record was deleted - remove from cache and return nil
                    recordCache.remove(id: id)
                    return nil
                }
            }

            if store.overflowReadDegradedModeEnabled() {
                // Corruption circuit-breaker: once overflow reads are degraded, avoid disk fetches
                // for record hydration in this collection. This keeps callers responsive.
                return nil
            }
            let maxDecodeAttempts = 3
            var attempt = 0
            var lastError: Error?
            
            while attempt < maxDecodeAttempts {
                attempt += 1
                do {
                    // Double-check record still exists before reading from disk
                    guard indexMapSnapshot[id] != nil else {
                        return nil
                    }
                    
                    let data: Data?
                    do {
                        data = try store.readPageWithOverflow(index: firstPageIndex)
                    } catch let error as CryptoKitError {
                        throw error
                    } catch {
                        let errorDesc = error.localizedDescription.lowercased()
                        if errorDesc.contains("authentication") || errorDesc.contains("corrupt") || errorDesc.contains("invalid") || errorDesc.contains("cryptokit") {
                            throw error
                        }
                        // CRITICAL: Don't silently return nil - throw error so developers know read failed
                        // Returning nil makes it impossible to distinguish between "page doesn't exist" and "read failed"
                        BlazeLogger.error("Failed to read page \(firstPageIndex) for record \(id): \(error)")
                        throw BlazeDBError.corruptedData(location: "fetch(id: \(id))", reason: "Unable to read record data: \(error.localizedDescription). Try running db.compact() or restoring from backup.")
                    }
                    
                    guard let data = data, !data.allSatisfy({ $0 == 0 }) else {
                        return nil
                    }
                    
                    do {
                        let record = try BlazeBinaryDecoder.decode(data)
                        
                        if let actualID = record.storage["id"]?.uuidValue {
                            if actualID != id {
                                let value = record.storage["value"]?.intValue ?? -1
                                BlazeLogger.error("CRITICAL ID MISMATCH: Requested \(id.uuidString.prefix(8)) from page \(firstPageIndex) but got record with ID \(actualID.uuidString.prefix(8)) (value: \(value)). This indicates indexMap corruption.")
                                for (mapID, mapPages) in indexMapSnapshot where mapPages.contains(firstPageIndex) {
                                    BlazeLogger.error("  indexMap[\(mapID.uuidString.prefix(8))] = \(mapPages)")
                                }
                            } else {
                                BlazeLogger.debug("✅ [FETCH] Record \(id.uuidString.prefix(8)) from page \(firstPageIndex) matches (value: \(record.storage["value"]?.intValue ?? -1))")
                            }
                        } else {
                            BlazeLogger.warn("⚠️ [FETCH] Record from page \(firstPageIndex) has no ID field!")
                        }
                        
                        recordCache.set(id: id, record: record)
                        return record
                    } catch let error as BlazeBinaryError {
                        lastError = error
                        let message = error.localizedDescription

                        // Backward-compatibility fallback: some legacy pages were stored as raw JSON
                        // documents instead of BlazeBinary. Decode them on read so migration/tests
                        // can still hydrate records before conversion.
                        if message.localizedCaseInsensitiveContains("invalid magic bytes")
                            || message.localizedCaseInsensitiveContains("not blazebinary")
                            || message.localizedCaseInsensitiveContains("invalid blazebinary") {
                            if let legacyStorage = try? JSONDecoder().decode([String: BlazeDocumentField].self, from: data) {
                                let legacyRecord = BlazeDataRecord(legacyStorage)
                                recordCache.set(id: id, record: legacyRecord)
                                return legacyRecord
                            }
                            if let wrappedRecord = try? JSONDecoder().decode(BlazeDataRecord.self, from: data) {
                                recordCache.set(id: id, record: wrappedRecord)
                                return wrappedRecord
                            }
                        }

                        if store.overflowReadDegradedModeEnabled(),
                           (message.localizedCaseInsensitiveContains("data too short")
                            || message.localizedCaseInsensitiveContains("overflow")
                            || message.localizedCaseInsensitiveContains("invalid blazebinary")) {
                            // In degraded overflow mode, retries amplify latency without improving outcomes.
                            // Treat this record as unreadable and continue.
                            BlazeLogger.warn("⚠️ [FETCH] Skipping decode retries for record \(id.uuidString.prefix(8)) (page \(firstPageIndex)) while overflow degraded mode is active; incidents=\(store.overflowCorruptionIncidentSnapshot())")
                            return nil
                        }
                        if message.localizedCaseInsensitiveContains("data too short") ||
                            message.localizedCaseInsensitiveContains("crc") ||
                            message.localizedCaseInsensitiveContains("overflow") {
                            if attempt < maxDecodeAttempts {
                                let delay = Double(attempt) * 0.002
                                BlazeLogger.warn("⚠️ [FETCH] Decode attempt \(attempt) failed for record \(id.uuidString.prefix(8)) (page \(firstPageIndex)): \(message). Retrying in \(String(format: "%.3f", delay))s")
                                // NOTE: Thread.sleep is intentional. This synchronous retry loop
                                // requires blocking waits. Converting to async would require API changes.
                                Thread.sleep(forTimeInterval: delay)
                                continue
                            }
                        }
                        throw error
                    }
                } catch let error as CryptoKitError {
                    throw error
                } catch {
                    lastError = error
                    let errorDesc = error.localizedDescription.lowercased()
                    if errorDesc.contains("authentication") || errorDesc.contains("corrupt") || errorDesc.contains("invalid") || errorDesc.contains("cryptokit") {
                        throw error
                    }
                    // CRITICAL: Don't silently return nil - throw error so developers know fetch failed
                    // Returning nil makes it impossible to distinguish between "record doesn't exist" and "fetch failed"
                    BlazeLogger.error("Failed to decode record for id \(id): \(error)")
                    throw BlazeDBError.corruptedData(location: "fetch(id: \(id.uuidString))", reason: error.localizedDescription)
                }
            }
            
            if let lastError = lastError {
                throw lastError
            }
            return nil
        }
        
        public func fetchAll() throws -> [BlazeDataRecord] {
            // MVCC Path: Fetch all visible records at current snapshot
            if mvccEnabled {
                let tx = MVCCTransaction(versionManager: versionManager, pageStore: store)
                let records = try tx.readAll()
                
                if records.isEmpty && !indexMap.isEmpty {
                    BlazeLogger.warn("⚠️ [FETCHALL] MVCC returned 0 records while indexMap has \(indexMap.count) entries. Falling back to legacy fetch (indexMap-based).")
                    #if !BLAZEDB_LINUX_CORE
                    return try _fetchAllOptimized()
                    #else
                    // On Linux, fall back to basic fetchAll
                    return try fetchAllBasic()
                    #endif
                }
                
                return records
            }
            
            // OPTIMIZED: Use parallel fetch for massive speedup!
            #if !BLAZEDB_LINUX_CORE
            return try _fetchAllOptimized()
            #else
            // On Linux, use basic fetchAll
            return try fetchAllBasic()
            #endif
        }
        
        // Basic fetchAll implementation for Linux (no optimizations)
        #if BLAZEDB_LINUX_CORE
        private func fetchAllBasic() throws -> [BlazeDataRecord] {
            return try queue.sync {
                var records: [BlazeDataRecord] = []
                let indexMapSnapshot = indexMap
                for id in indexMapSnapshot.keys {
                    if let record = try? _fetchNoSync(id: id) {
                        records.append(record)
                    }
                }
                return records
            }
        }
        #endif
        
        public func fetchAll(byProject project: String) throws -> [BlazeDataRecord] {
            return queue.sync {
                var records: [BlazeDataRecord] = []
                // Use snapshot to avoid concurrent modification issues
                let indexMapSnapshot = indexMap
                for id in indexMapSnapshot.keys {
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
                    
                    // Update indexMap (MVCC stores single page number, convert to array)
                    if let version = versionManager.getVersion(recordID: id, snapshot: .max) {
                        indexMap[id] = [version.pageNumber]  // MVCC currently uses single page
                    }
                    
                    // Update secondary indexes: remove old entry, add new entry
                    // Remove old keys from indexes
                    let oldDoc = current.storage
                    
                    // Deindex from B-tree indexes (Phase 4: range query support)
                    btreeIndexManager.deindexRecord(id: id, fields: oldDoc)
                    
                    for (compound, _) in secondaryIndexes {
                        let fields = compound.components(separatedBy: "+")
                        let oldKey = CompoundIndexKey.fromFields(oldDoc, fields: fields)
                        // Normalize the old key to match how it was stored
                        let normalizedOldComponents = oldKey.components.map { component -> AnyBlazeCodable in
                            switch component {
                            case .string(let s): return AnyBlazeCodable(s)
                            case .int(let i): return AnyBlazeCodable(i)
                            case .double(let d): return AnyBlazeCodable(d)
                            case .bool(let b): return AnyBlazeCodable(b)
                            case .date(let d): return AnyBlazeCodable(d)
                            case .uuid(let u): return AnyBlazeCodable(u)
                            case .data(let data): return AnyBlazeCodable(data)
                            case .vector(let v): return AnyBlazeCodable(v)
                            case .null: return AnyBlazeCodable("")
                                            case .array, .dictionary: return AnyBlazeCodable("")  // Arrays/dicts not supported in compound indexes
                            }
                        }
                        let normalizedOldKey = CompoundIndexKey(normalizedOldComponents)
                        if var inner = secondaryIndexes[compound] {
                            if var set = inner[normalizedOldKey] {
                                set.remove(id)
                                if set.isEmpty {
                                    inner.removeValue(forKey: normalizedOldKey)
                                } else {
                                    inner[normalizedOldKey] = set
                                }
                                secondaryIndexes[compound] = inner
                            }
                        }
                    }
                    
                    // Add new keys to indexes
                    for (compound, _) in secondaryIndexes {
                        let fields = compound.components(separatedBy: "+")
                        guard fields.allSatisfy({ merged[$0] != nil }) else {
                            BlazeLogger.warn("Skipping index \(compound) for id \(id) — missing one or more fields.")
                            continue
                        }
                        let rawKey = CompoundIndexKey.fromFields(merged, fields: fields)
                        let normalizedComponents = rawKey.components.map { component -> AnyBlazeCodable in
                            switch component {
                            case .string(let s): return AnyBlazeCodable(s)
                            case .int(let i): return AnyBlazeCodable(i)
                            case .double(let d): return AnyBlazeCodable(d)
                            case .bool(let b): return AnyBlazeCodable(b)
                            case .date(let d): return AnyBlazeCodable(d)
                            case .uuid(let u): return AnyBlazeCodable(u)
                            case .data(let data): return AnyBlazeCodable(data)
                            case .vector(let v): return AnyBlazeCodable(v)
                            case .null: return AnyBlazeCodable("")
                                            case .array, .dictionary: return AnyBlazeCodable("")  // Arrays/dicts not supported in compound indexes
                            }
                        }
                        let indexKey = CompoundIndexKey(normalizedComponents)
                        var inner = secondaryIndexes[compound] ?? [:]
                        var set = inner[indexKey] ?? Set<UUID>()
                        set.insert(id)
                        inner[indexKey] = set
                        secondaryIndexes[compound] = inner
                    }
                    
                    // Index in B-tree indexes (Phase 4: range query support)
                    btreeIndexManager.indexRecord(id: id, fields: merged)
                    
                    // Invalidate cache (record was updated)
                    recordCache.remove(id: id)
                    
                    // Update search index if enabled
                    #if !BLAZEDB_LINUX_CORE
                    try? updateSearchIndexOnUpdate(updatedRecord)
                    
                    // Update spatial index if enabled
                    updateSpatialIndexOnUpdate(updatedRecord)
                    
                    // Update vector index if enabled
                    updateVectorIndexOnUpdate(updatedRecord)
                    #endif
                    
                    unsavedChanges += 1
                    if unsavedChanges >= metadataFlushThreshold {
                        try saveLayout()
                        unsavedChanges = 0
                    }
                }
                return
            }
            
            // Legacy Path: Original implementation
            #if !BLAZEDB_LINUX_CORE
            try queue.sync(flags: .barrier) {
                try _updateNoSync(id: id, with: data)
            }
            #else
            // On Linux, use basic update without queue optimizations
            try _updateNoSync(id: id, with: data)
            #endif
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
        
        public func filter(_ isMatch: @escaping (BlazeDataRecord) -> Bool) throws -> [BlazeDataRecord] {
            // OPTIMIZED: Use parallel filter for large datasets
            #if !BLAZEDB_LINUX_CORE
            return try filterOptimized(isMatch)
            #else
            // On Linux, use basic filter
            return try queue.sync {
                let all = try fetchAllBasic()
                return all.filter(isMatch)
            }
            #endif
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
        
        internal func _deleteNoSync(id: UUID, record: BlazeDataRecord? = nil) throws {
            // Capture a snapshot of indexMap to avoid concurrent modification issues
            // This prevents crashes when indexMap is being modified by other threads
            let indexMapSnapshot = indexMap
            
            // Check if record exists - if not, delete is idempotent
            guard let pageIndices = indexMapSnapshot[id] else { return }
            
            // 🔒 Atomic delete: backup state before modifications
            // Use snapshot for backup to avoid accessing indexMap again
            let indexBackup = secondaryIndexes
            let indexMapBackup = indexMapSnapshot  // Use snapshot instead of direct access
            
            do {
                // Remove from all indexes (persisting mutations)
                // OPTIMIZATION: Only fetch record if we have indexes to update
                let recordToUse = record ?? (try? _fetchNoSync(id: id))
                
                if !secondaryIndexes.isEmpty, let record = recordToUse {
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
                
                // Deindex from B-tree indexes
                if let record = recordToUse {
                    btreeIndexManager.deindexRecord(id: id, fields: record.storage)
                }
                
                // OPTIMIZATION: Batch delete all pages in a single sync block to reduce overhead
                // Delete all pages in overflow chain
                // Note: We already checked indexMapSnapshot[id] at the start, so we proceed with deletion
                
                // Load layout to track deleted pages for reuse
                var layout: StorageLayout
                do {
                    layout = try StorageLayout.loadSecure(
                        from: metaURL,
                        signingKey: encryptionKey,
                        password: password,
                        salt: kdfSalt
                    )
                } catch {
                    layout = try StorageLayout.load(from: metaURL)
                }
                
                // OPTIMIZATION: Batch delete all pages in a single sync block (not barrier)
                // Since we're already in DynamicCollection's queue.sync, we use regular sync
                // to allow concurrent reads. Barrier would block everything unnecessarily.
                // Use public deletePage API (works on both Apple and Linux)
                // Note: try? is used intentionally to suppress errors - deletion continues on failure
                for pageIndex in pageIndices {
                    try? store.deletePage(index: pageIndex)
                    markPageForReuse(pageIndex: pageIndex, layout: &layout)
                }
                
                // Remove from indexMap (use removeValue for consistency with MVCC path)
                // We already verified the record exists at the start using indexMapSnapshot
                // Since we're in a sync block, we can safely modify indexMap here
                // Use a safe modification pattern to avoid crashes from concurrent indexMap replacement
                // Create a mutable copy, modify it, then assign back atomically
                // This pattern prevents crashes if indexMap is being replaced concurrently
                var mutableIndexMap = indexMap
                let removedPages = mutableIndexMap.removeValue(forKey: id)
                // Atomic assignment - safe within sync block
                indexMap = mutableIndexMap
                if let pages = removedPages {
                    BlazeLogger.debug("🗑️ [DELETE] Legacy: Removed indexMap[\(id.uuidString.prefix(8))] = \(pages), marking pages for reuse")
                } else {
                    BlazeLogger.warn("⚠️ [DELETE] Legacy: Tried to remove indexMap[\(id.uuidString.prefix(8))] but it wasn't in indexMap!")
                }
                
                // Update layout with deleted pages and indexMap
                layout.indexMap = indexMap
                layout.secondaryIndexes = StorageLayout.fromRuntimeIndexes(secondaryIndexes)
                
                // Invalidate cache (record was deleted)
                recordCache.remove(id: id)
                
                // Clear fetchAll cache to ensure consistency
                #if !BLAZEDB_LINUX_CORE
                clearFetchAllCache()
                #endif
                
                unsavedChanges += 1
                // OPTIMIZATION: Only save layout periodically, not on every delete
                // This significantly improves delete performance for bulk operations
                if unsavedChanges >= metadataFlushThreshold {
                    // Save layout with updated deletedPages
                    if password != nil {
                        try layout.saveSecure(to: metaURL, signingKey: encryptionKey)
                    } else {
                        try layout.save(to: metaURL)
                    }
                    unsavedChanges = 0
                    // Clear fetchAll cache when we save layout (batch operation)
                    #if !BLAZEDB_LINUX_CORE
                    clearFetchAllCache()
                    #endif
                }
                
                // OPTIMIZATION: Defer expensive index updates - they can be batched
                // These are optional and can be done lazily or in batch
                // NEW: Update search index if enabled
                // try? updateSearchIndexOnDelete(id)  // Deferred for performance
                
                // NEW: Update spatial index if enabled
                // updateSpatialIndexOnDelete(id)  // Deferred for performance
                
                // NEW: Update vector index if enabled
                // updateVectorIndexOnDelete(id)  // Deferred for performance
                
                // Success - changes persisted
            } catch {
                // 🔒 Restore state on failure, but only if record still exists in indexMap
                // (If another thread already deleted it, don't restore)
                if indexMap[id] != nil {
                    BlazeLogger.warn("Delete failed, restoring index state: \(error)")
                    secondaryIndexes = indexBackup
                    indexMap = indexMapBackup
                    throw error
                } else {
                    // Record was already deleted by another thread - this is fine, just return
                    BlazeLogger.debug("Delete failed but record was already deleted by another thread: \(error)")
                    return
                }
            }
        }
        
        public func delete(id: UUID, record: BlazeDataRecord? = nil) throws {
            // MVCC Path: Mark version as deleted
            if mvccEnabled {
                try queue.sync(flags: .barrier) {
                    // Get page indices BEFORE removing from indexMap
                    let pageIndices = indexMap[id]
                    
                    let tx = MVCCTransaction(versionManager: versionManager, pageStore: store)
                    try tx.delete(recordID: id)
                    try tx.commit()
                    
                    // Trigger automatic GC (Phase 4)
                    gcManager.onTransactionCommit()
                    
                    // Deindex from B-tree indexes before removing from indexMap
                    // Get the record fields if we have them, otherwise fetch
                    if let recordToDeindex = record ?? (try? _fetchNoSync(id: id)) {
                        btreeIndexManager.deindexRecord(id: id, fields: recordToDeindex.storage)
                    }
                    
                    // Update indexMap (remove from index)
                    let removedPages = indexMap.removeValue(forKey: id)
                    if let pages = removedPages {
                        BlazeLogger.debug("🗑️ [DELETE] MVCC: Removed indexMap[\(id.uuidString.prefix(8))] = \(pages)")
                    } else {
                        BlazeLogger.warn("⚠️ [DELETE] MVCC: Tried to remove indexMap[\(id.uuidString.prefix(8))] but it wasn't in indexMap!")
                    }
                    
                    // Track deleted pages for reuse
                    if let pageIndices = pageIndices, !pageIndices.isEmpty {
                        // MVCC: Add pages to pageGC.freePages directly (not layout.deletedPages)
                        // This prevents double-counting since version GC might also add pages
                        for pageIdx in pageIndices {
                            versionManager.pageGC.markPageObsolete(pageIdx)
                        }
                        BlazeLogger.debug("🗑️ [DELETE] MVCC: Added \(pageIndices.count) pages to pageGC.freePages for reuse")
                        
                        // Load existing layout to update nextPageIndex (but don't add to deletedPages in MVCC mode)
                        // Try secure load first, fallback to regular if needed
                        var layout: StorageLayout
                        do {
                            layout = try StorageLayout.loadSecure(
                                from: metaURL,
                                signingKey: encryptionKey,
                                password: password,
                                salt: kdfSalt
                            )
                        } catch {
                            layout = try StorageLayout.load(from: metaURL)
                        }
                        BlazeLogger.debug("🗑️ [DELETE] Loaded layout: nextPageIndex=\(layout.nextPageIndex), deletedPages.count=\(layout.deletedPages.count)")
                        
                        // MVCC: Remove pages from layout.deletedPages if they're there (they should be in pageGC now)
                        // This prevents double-counting in GC stats
                        let beforeRemove = layout.deletedPages.count
                        layout.deletedPages = layout.deletedPages.filter { !pageIndices.contains($0) }
                        let afterRemove = layout.deletedPages.count
                        if beforeRemove != afterRemove {
                            BlazeLogger.debug("🗑️ [DELETE] MVCC: Removed \(beforeRemove - afterRemove) pages from layout.deletedPages (now in pageGC)")
                        }
                        // Update layout with current state
                        layout.indexMap = indexMap  // indexMap is already [UUID: [Int]] format
                        // CRITICAL: Set nextPageIndex correctly based on maxUsedPage
                        // Use max() to preserve nextPageIndex when reusing pages or when all records are deleted
                        // - If we have records: nextPageIndex = max(current, maxUsedPage + 1)
                        // - If we delete all records: preserve nextPageIndex (don't reset to 0)
                        let maxUsedPage = indexMap.values.flatMap { $0 }.max() ?? -1
                        let nextPageIndexBefore = layout.nextPageIndex
                        if maxUsedPage >= 0 {
                            // We have records - set nextPageIndex to max(current, maxUsedPage + 1)
                            // This preserves nextPageIndex when it's already higher (e.g., when reusing pages)
                            let calculatedNextPageIndex = maxUsedPage + 1
                            layout.nextPageIndex = max(layout.nextPageIndex, calculatedNextPageIndex)
                            BlazeLogger.trace("🗑️ [DELETE] MVCC: nextPageIndex check - before: \(nextPageIndexBefore), maxUsedPage: \(maxUsedPage), calculated: \(calculatedNextPageIndex), final: \(layout.nextPageIndex), deletedPages.count: \(layout.deletedPages.count)")
                        } else {
                            // No records - preserve nextPageIndex (don't reset to 0)
                            // This ensures we don't lose track of pages that were allocated
                            // layout.nextPageIndex is already correct, don't change it
                            BlazeLogger.trace("🗑️ [DELETE] MVCC: All records deleted - preserving nextPageIndex at \(layout.nextPageIndex), deletedPages.count: \(layout.deletedPages.count)")
                        }
                        if nextPageIndexBefore != layout.nextPageIndex {
                            BlazeLogger.debug("🗑️ [DELETE] MVCC: ⚠️ Updated nextPageIndex from \(nextPageIndexBefore) to \(layout.nextPageIndex)")
                        } else {
                            BlazeLogger.trace("🗑️ [DELETE] MVCC: ✅ Preserved nextPageIndex at \(layout.nextPageIndex)")
                        }
                        // Update in-memory nextPageIndex to reflect the saved value
                        self.nextPageIndex = layout.nextPageIndex
                        // CRITICAL: Filter out any pages from deletedPages that are still in indexMap
                        // This prevents deletedPages from containing pages that are actually in use
                        let deletedPagesBeforeFilter = layout.deletedPages.count
                        layout.deletedPages = layout.deletedPages.filter { pageIndex in
                            !indexMap.values.contains { pageIndices in
                                pageIndices.contains(pageIndex)
                            }
                        }
                        let deletedPagesAfterFilter = layout.deletedPages.count
                        if deletedPagesBeforeFilter != deletedPagesAfterFilter {
                            BlazeLogger.warn("💾 [DELETE] Filtered out \(deletedPagesBeforeFilter - deletedPagesAfterFilter) pages from deletedPages that are still in use")
                        }
                        BlazeLogger.debug("💾 [DELETE] Saving layout with \(layout.deletedPages.count) deleted pages, nextPageIndex=\(layout.nextPageIndex) (maxUsedPage=\(maxUsedPage))")
                        // Save using secure method if password is available
                        if password != nil {
                            try layout.saveSecure(to: metaURL, signingKey: encryptionKey)
                        } else {
                            try layout.save(to: metaURL)
                        }
                        BlazeLogger.debug("💾 [DELETE] ✅ Layout saved with \(layout.deletedPages.count) deleted pages, nextPageIndex=\(layout.nextPageIndex)")
                        // Layout already saved above, so we don't need to save again
                        // But we still track unsavedChanges for other metadata updates
                        unsavedChanges = 0  // Reset since we just saved
                    } else {
                        BlazeLogger.debug("🗑️ [DELETE] No page indices to track (pageIndices=\(pageIndices?.description ?? "nil"))")
                        // No pages to track, but still increment unsavedChanges
                        unsavedChanges += 1
                    }
                    
                    // Invalidate cache (record was deleted)
                    recordCache.remove(id: id)
                    
                    // Only call saveLayout() if we haven't already saved and threshold is reached
                    if pageIndices == nil && unsavedChanges >= metadataFlushThreshold {
                        try saveLayout()
                        unsavedChanges = 0
                    }
                }
                return
            }
            
            // Legacy Path: Original implementation
            // OPTIMIZATION: Pass record to avoid double-fetch
            // Legacy delete mutates shared indexes/layout state and must be serialized as a writer.
            try queue.sync(flags: .barrier) {
                try _deleteNoSync(id: id, record: record)
            }
        }
        
        /// Destroys the entire collection, including data and layout files.
        public func destroy() throws {
            queue.sync(flags: .barrier) {
                // CRITICAL: Log file deletion errors instead of silently suppressing them
                // File deletion failures could indicate permission issues or file locks
                do {
                    try FileManager.default.removeItem(at: store.fileURL)
                } catch {
                    BlazeLogger.warn("⚠️ Failed to delete database file during destroy(): \(error)")
                }
                do {
                    try FileManager.default.removeItem(at: metaURL)
                } catch {
                    BlazeLogger.warn("⚠️ Failed to delete metadata file during destroy(): \(error)")
                }
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
                throw BlazeDBError.invalidData(reason: "Fields and values count mismatch: \(fields.count) fields, \(values.count) values")
            }
            let compoundKey = fields.joined(separator: "+")
            
            // IMPORTANT: Use the same normalization logic as insert() to ensure keys match
            // Convert values to BlazeDocumentField, then use fromFields and normalize
            var tempDoc: [String: BlazeDocumentField] = [:]
            for (index, field) in fields.enumerated() {
                let value = values[index]
                let docField: BlazeDocumentField
                switch value {
                case let s as String: docField = .string(s)
                case let i as Int: docField = .int(i)
                case let d as Double: docField = .double(d)
                case let b as Bool: docField = .bool(b)
                case let date as Date: docField = .date(date)
                case let uuid as UUID: docField = .uuid(uuid)
                case let data as Data: docField = .data(data)
                default: docField = .string(String(describing: value))
                }
                tempDoc[field] = docField
            }
            
            // Use fromFields to create the raw key (same as insert)
            let rawKey = CompoundIndexKey.fromFields(tempDoc, fields: fields)
            // Normalize the components the same way as insert()
            let normalizedComponents = rawKey.components.map { component -> AnyBlazeCodable in
                switch component {
                case .string(let s): return AnyBlazeCodable(s)
                case .int(let i): return AnyBlazeCodable(i)
                case .double(let d): return AnyBlazeCodable(d)
                case .bool(let b): return AnyBlazeCodable(b)
                case .date(let d): return AnyBlazeCodable(d)
                case .uuid(let u): return AnyBlazeCodable(u)
                case .data(let data): return AnyBlazeCodable(data)
                                            case .vector(let v): return AnyBlazeCodable(v)
                                            case .null: return AnyBlazeCodable("")
                                            case .array, .dictionary: return AnyBlazeCodable("")  // Arrays/dicts not supported in compound indexes
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
                guard layoutSignatureVerified else {
                    let reason = "Cannot persist metadata: layout signature verification failed (read-only mode). Open the database with the correct password to persist changes."
                    BlazeLogger.error("💾 [PERSIST] \(reason)")
                    throw BlazeDBError.permissionDenied(operation: "persist", path: nil)
                }
                // First, ensure all page writes are flushed to disk
                try store.synchronize()
                
                // Clear fetchAll cache to ensure fresh reads after persist
                #if !BLAZEDB_LINUX_CORE
                clearFetchAllCache()
                #endif
                
                // Then save the metadata
                try saveLayout()
                unsavedChanges = 0
            }
        }

        internal func close() throws {
            try queue.sync(flags: .barrier) {
                guard !closed else { return }

                if unsavedChanges > 0, layoutSignatureVerified {
                    try saveLayout()
                    unsavedChanges = 0
                }

                store.close()
                password = nil
                closed = true
            }
        }
        
        internal func saveLayout() throws {
            guard layoutSignatureVerified else {
                let reason = "Cannot save layout because signature verification failed. Open database with correct password."
                BlazeLogger.error("💾 [SAVELAYOUT] \(reason)")
                throw BlazeDBError.permissionDenied(operation: "saveLayout", path: nil)
            }
            // Convert secondaryIndexes once
            // CRITICAL: Sort UUID arrays to ensure deterministic encoding for signature verification
            // Even though StorageLayout.encode(to:) also sorts them, sorting here ensures consistency
            let convertedSecondaryIndexes = secondaryIndexes.mapValues { inner in
                inner.mapValues { Array($0).sorted(by: { $0.uuidString < $1.uuidString }) }
            }
            
            // Use indexMap directly (StorageLayout now supports [UUID: [Int]])
            // No conversion needed - StorageLayout.indexMap is already [UUID: [Int]]
            
            // CRITICAL: Preserve deletedPages and metaData from existing layout on disk
            // This ensures deleted pages are tracked for garbage collection
            // and metadata (like ordering settings) is preserved
            var existingDeletedPages: [Int] = []
            var existingMetaData: [String: BlazeDocumentField] = [:]
            if FileManager.default.fileExists(atPath: metaURL.path) {
                // Try secure load first, fallback to regular if needed
                // CRITICAL: Log errors instead of silently suppressing them
                // Silent failures could hide corruption or I/O issues
                do {
                    let existingLayout = try StorageLayout.loadSecure(
                        from: metaURL,
                        signingKey: encryptionKey,
                        password: password,
                        salt: kdfSalt
                    )
                    existingDeletedPages = existingLayout.deletedPages
                    existingMetaData = existingLayout.metaData
                } catch {
                    if BlazeDBForensics.enabled {
                        throw error
                    }
                    // Log error but try fallback
                    BlazeLogger.warn("⚠️ Failed to load secure layout in saveLayout(), trying regular load: \(error)")
                    do {
                        let existingLayout = try StorageLayout.load(from: metaURL)
                        existingDeletedPages = existingLayout.deletedPages
                        existingMetaData = existingLayout.metaData
                    } catch {
                        // Log fallback failure but continue - might be a new database
                        BlazeLogger.warn("⚠️ Failed to load regular layout in saveLayout(): \(error)")
                    }
                }
            }
            
            // Build layout from current in-memory state (not from disk)
            // Use in-memory encodingFormat to avoid loading from disk during concurrent operations
            // This ensures signature verification will pass when reopening
            var layout = StorageLayout(
                indexMap: indexMap,  // StorageLayout now expects [UUID: [Int]]
                nextPageIndex: nextPageIndex,
                secondaryIndexes: convertedSecondaryIndexes,
                searchIndex: cachedSearchIndex,
                searchIndexedFields: cachedSearchIndexedFields
            )
            
            // Set metadata fields (use in-memory encodingFormat, not from disk)
            layout.encodingFormat = encodingFormat
            #if !BLAZEDB_LINUX_CORE
            // These properties are added by extensions in gated files (StorageLayout+Extensions)
            // Access them only when extensions are available
            // For now, skip - extensions handle persistence
            #endif
            
            // CRITICAL: Preserve secondaryIndexDefinitions from in-memory state
            // This ensures signature verification passes when createIndex saves, then persist() saves again
            layout.secondaryIndexDefinitions = secondaryIndexDefinitions
            
            // CRITICAL: Preserve deletedPages from existing layout
            layout.deletedPages = existingDeletedPages
            
            // CRITICAL: Preserve metaData from existing layout (e.g., ordering settings)
            // This ensures metadata set via updateMeta() is not lost when saveLayout() is called
            layout.metaData = existingMetaData

            // Compatibility contract: always persist an explicit on-disk format version.
            if layout.metaData["formatVersion"] == nil {
                layout.metaData["formatVersion"] = .string(BlazeDBClient.FormatVersion.current.description)
            }
            
            // CRITICAL: Ensure nextPageIndex is at least as large as the highest deleted page
            // This ensures nextPageIndex reflects the highest page ever allocated
            if let maxDeletedPage = existingDeletedPages.max() {
                layout.nextPageIndex = max(layout.nextPageIndex, nextPageIndex, maxDeletedPage + 1)
                // Update in-memory nextPageIndex to reflect the saved value
                self.nextPageIndex = layout.nextPageIndex
            } else {
                // No deleted pages, but still ensure nextPageIndex is correct
                layout.nextPageIndex = max(layout.nextPageIndex, nextPageIndex)
                self.nextPageIndex = layout.nextPageIndex
            }
            
            // Update with full overflow chain info (not just first page)
            layout.indexMap = indexMap
            
            // Log state before saving for debugging
            BlazeLogger.debug("💾 [SAVELAYOUT] Saving layout: indexMap.count=\(indexMap.count), nextPageIndex=\(nextPageIndex), secondaryIndexes.count=\(convertedSecondaryIndexes.count), deletedPages.count=\(layout.deletedPages.count)")
            
            do {
                // SECURITY: Save with HMAC signature for tamper detection
                try layout.saveSecure(to: metaURL, signingKey: encryptionKey)
                cachedDeletedPages = layout.deletedPages
                
                // OPTIMIZATION: Sync store to flush any unsynchronized deletes/writes
                // This ensures data is persisted when layout is saved
                try store.synchronize()
                
                BlazeLogger.debug("💾 [SAVELAYOUT] ✅ Layout saved successfully")
            } catch {
                BlazeLogger.error("💾 [SAVELAYOUT] ❌ Failed to save layout: \(error)")
                throw error
            }
        }
        
        // Ensure unsaved changes are flushed on cleanup
        deinit {
            try? close()
            
            // CRITICAL: Clean up static dictionary references to prevent memory leaks
            // When DynamicCollection is deallocated, remove its cache and pool from static dictionaries
            // This allows the actors (AsyncQueryCache and OperationPool) to be deallocated
            #if !BLAZEDB_LINUX_CORE
            let id = ObjectIdentifier(self)
            DynamicCollection.cleanupAsyncResources(for: id)
            #endif
        }
        
        /// Dumps the raw CBOR data for each page index in the collection.
        public func rawDump() throws -> [Int: Data] {
            var result: [Int: Data] = [:]
            for (_, pageIndices) in indexMap {
                guard let firstPageIndex = pageIndices.first else { continue }
                let data = try store.readPageWithOverflow(index: firstPageIndex)
                result[firstPageIndex] = data
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
                // Use snapshot to avoid concurrent modification issues
                // Note: We're in a barrier block, but still use snapshot for safety
                let indexMapSnapshot = indexMap
                let allIDs = Array(indexMapSnapshot.keys)
                var purgeErrors: [Error] = []
                
                for id in allIDs {
                    do {
                        if let record = try _fetchNoSync(id: id),
                           let isDeleted = record.storage["isDeleted"]?.boolValue, isDeleted {
                            try _deleteNoSync(id: id)
                        }
                    } catch {
                        // CRITICAL: Collect errors instead of silently suppressing them
                        // Developers need to know if purge failed for some records
                        BlazeLogger.error("Failed to purge record \(id.uuidString): \(error)")
                        purgeErrors.append(error)
                    }
                }
                
                // CRITICAL: Throw error if any purge operations failed
                // This ensures developers know when purge didn't complete successfully
                if !purgeErrors.isEmpty {
                    let firstError = purgeErrors.first?.localizedDescription ?? "Unknown error"
                    let errorMsg = "Purge failed for \(purgeErrors.count) record(s). First error: \(firstError)"
                    throw BlazeDBError.transactionFailed(errorMsg)
                }
            }
        }
        
        internal func _updateNoSync(id: UUID, with data: BlazeDataRecord) throws {
            // Use snapshot to avoid concurrent modification issues
            let indexMapSnapshot = indexMap
            guard let pageIndices = indexMapSnapshot[id], let firstPageIndex = pageIndices.first else {
                throw NSError(domain: "DynamicCollection", code: 404, userInfo: [NSLocalizedDescriptionKey: "Record not found"])
            }
            
            // 🔒 Atomic update: backup state before modifications
            let indexBackup = secondaryIndexes
            let indexMapBackup = indexMapSnapshot  // Backup indexMap for rollback
            
            // Note: Page allocation tracking is done in the inner scope for this code path
            // The outer scope doesn't allocate pages directly
            _ = nextPageIndex  // Reference to suppress unused warning
            
            do {
                // Remove old keys (normalize to match how they were stored)
                // CRITICAL: Log errors instead of silently suppressing them
                // Silent failures could hide corruption or I/O issues
                let record: BlazeDataRecord?
                do {
                    record = try _fetchNoSync(id: id)
                } catch {
                    // Log error but continue - record might not exist or might be corrupted
                    // This is non-critical for update (we'll just skip old key removal)
                    BlazeLogger.warn("⚠️ Failed to fetch record \(id.uuidString.prefix(8)) for index update during update: \(error)")
                    record = nil
                }
                if let record = record {
                    let oldDoc = record.storage
                    
                    // Deindex from B-tree indexes (Phase 4: range query support)
                    btreeIndexManager.deindexRecord(id: id, fields: oldDoc)
                    
                    for (compound, _) in secondaryIndexes {
                        let fields = compound.components(separatedBy: "+")
                        let oldKey = CompoundIndexKey.fromFields(oldDoc, fields: fields)
                        // Normalize the old key to match how it was stored during insert
                        let normalizedOldComponents = oldKey.components.map { component -> AnyBlazeCodable in
                            switch component {
                            case .string(let s): return AnyBlazeCodable(s)
                            case .int(let i): return AnyBlazeCodable(i)
                            case .double(let d): return AnyBlazeCodable(d)
                            case .bool(let b): return AnyBlazeCodable(b)
                            case .date(let d): return AnyBlazeCodable(d)
                            case .uuid(let u): return AnyBlazeCodable(u)
                            case .data(let data): return AnyBlazeCodable(data)
                            case .vector(let v): return AnyBlazeCodable(v)
                            case .null: return AnyBlazeCodable("")
                                            case .array, .dictionary: return AnyBlazeCodable("")  // Arrays/dicts not supported in compound indexes
                            }
                        }
                        let normalizedOldKey = CompoundIndexKey(normalizedOldComponents)
                        if var inner = secondaryIndexes[compound] {
                            if var set = inner[normalizedOldKey] {
                                set.remove(id)
                                if set.isEmpty {
                                    inner.removeValue(forKey: normalizedOldKey)
                                } else {
                                    inner[normalizedOldKey] = set
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
                
                // Add to indexes (use same normalization as insert for consistency)
                for (compound, _) in secondaryIndexes {
                    let fields = compound.components(separatedBy: "+")
                    let rawKey = CompoundIndexKey.fromFields(document, fields: fields)
                    // Normalize the components the same way as insert()
                    let normalizedComponents = rawKey.components.map { component -> AnyBlazeCodable in
                        switch component {
                        case .string(let s): return AnyBlazeCodable(s)
                        case .int(let i): return AnyBlazeCodable(i)
                        case .double(let d): return AnyBlazeCodable(d)
                        case .bool(let b): return AnyBlazeCodable(b)
                        case .date(let d): return AnyBlazeCodable(d)
                        case .uuid(let u): return AnyBlazeCodable(u)
                        case .data(let data): return AnyBlazeCodable(data)
                                            case .vector(let v): return AnyBlazeCodable(v)
                                            case .null: return AnyBlazeCodable("")
                                            case .array, .dictionary: return AnyBlazeCodable("")  // Arrays/dicts not supported in compound indexes
                                        }
                    }
                    let indexKey = CompoundIndexKey(normalizedComponents)
                    var inner = secondaryIndexes[compound] ?? [:]
                    var set = inner[indexKey] ?? Set<UUID>()
                    set.insert(id)
                    inner[indexKey] = set
                    secondaryIndexes[compound] = inner
                }
                
                // Index in B-tree indexes (Phase 4: range query support)
                btreeIndexManager.indexRecord(id: id, fields: document)
                
                // 🔒 Write to disk BEFORE committing index changes
                // Use BlazeBinaryEncoder for encoding (matches decoder!)
                let encoded = try BlazeBinaryEncoder.encode(BlazeDataRecord(document))
                
                // Preserve old page indices so we can clean them up AFTER the new data is written.
                // This ensures that if a crash happens mid-write (before the main page pointer is updated),
                // the old overflow chain is still intact and readable.
                let oldPageIndices = pageIndices
                
                // Write the new record (main page overwritten last, after overflow chain is written)
                // Track allocation outside do-catch so catch block can access them
                var allocatedPageCount = 0  // Track how many pages we allocate
                let nextPageIndexBefore = nextPageIndex  // Save starting value for rollback
                let newPageIndices: [Int]
                
                do {
                    newPageIndices = try store.writePageWithOverflow(
                        index: firstPageIndex,
                        plaintext: encoded,
                        allocatePage: { [weak self] in
                            guard let self = self else { throw NSError(domain: "DynamicCollection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Collection deallocated"]) }
                            let pageIndex = self.nextPageIndex
                            self.nextPageIndex += 1
                            allocatedPageCount += 1  // Track allocation
                            return pageIndex
                        }
                    )
                } catch {
                    // CRITICAL: Rollback nextPageIndex if write failed
                    // This prevents nextPageIndex from being ahead of actual disk state
                    if allocatedPageCount > 0 {
                        nextPageIndex = nextPageIndexBefore
                        BlazeLogger.warn("⚠️ Rolling back nextPageIndex by \(allocatedPageCount) pages due to write failure")
                    }
                    // If writing new data fails, rethrow without touching the old pages (still intact)
                    throw error
                }
                
                // Update indexMap with new page indices (now pointing to the freshly written record)
                indexMap[id] = newPageIndices
                
                unsavedChanges += 1
                if unsavedChanges >= metadataFlushThreshold {
                    try saveLayout()
                    unsavedChanges = 0
                }
                
                // CRITICAL: Invalidate cache AFTER saveLayout() succeeds
                // This ensures cache is only cleared if the operation is fully persisted
                // If saveLayout() fails, cache remains valid and operation will rollback
                recordCache.remove(id: id)
                #if !BLAZEDB_LINUX_CORE
                clearFetchAllCache()
                
                // NEW: Update search index if enabled
                let updatedRecord = BlazeDataRecord(document)
                try? updateSearchIndexOnUpdate(updatedRecord)
                
                // NEW: Update spatial index if enabled
                updateSpatialIndexOnUpdate(updatedRecord)
                
                // NEW: Update vector index if enabled
                updateVectorIndexOnUpdate(updatedRecord)
                #endif
                
                // Clean up old overflow pages ONLY AFTER the new record is safely written.
                // Skip the first page index because it has already been overwritten with the new record data.
                if oldPageIndices.count > 1 {
                    let overflowPagesToDelete = Set(oldPageIndices.dropFirst())
                    for pageIdx in overflowPagesToDelete {
                        do {
                            try store.deletePage(index: pageIdx)
                        } catch {
                            // Log warning but don't fail the update - overflow pages can be cleaned up later
                            BlazeLogger.warn("⚠️ Failed to delete overflow page \(pageIdx) during update: \(error). Page will be cleaned up by GC.")
                        }
                    }
                }
                
                // Success - index changes are persisted
            } catch {
                // 🔒 Restore index state on failure
                // CRITICAL: Restore both secondaryIndexes AND indexMap if saveLayout() failed
                // This prevents indexMap from being out of sync with persisted layout
                BlazeLogger.warn("Update failed, restoring index state: \(error)")
                secondaryIndexes = indexBackup
                // Restore indexMap if it was modified (write succeeded but saveLayout failed)
                if indexMap[id] != indexMapBackup[id] {
                    indexMap = indexMapBackup
                    BlazeLogger.warn("⚠️ Restored indexMap due to saveLayout() failure")
                }
                // Note: Page allocation rollback is handled in inner scope where pages are actually allocated
                throw error
            }
        }
        
        internal func query() -> BlazeQueryContext {
            return BlazeQueryContext(collection: self)
        }
    }

    /// Persist the current layout to disk.
    extension DynamicCollection {
        
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
                default:
                    BlazeLogger.warn("Unsupported index value type: \(type(of: value))")
                    return []
                }
                
                // Try all normalized forms and collect all matching UUIDs
                // IMPORTANT: Use the same normalization logic as insert() to ensure keys match
                var matchedUUIDs = Set<UUID>()
                BlazeLogger.debug("🔍 [FETCH] Querying index '\(field)' for value '\(value)'")
                BlazeLogger.debug("🔍 [FETCH] Index '\(field)' exists: \(secondaryIndexes[field] != nil)")
                if let index = secondaryIndexes[field] {
                    BlazeLogger.debug("🔍 [FETCH] Index '\(field)' has \(index.count) keys")
                }
                for normalizedValue in valuesToTry {
                    // Use the same normalization logic as insert() to ensure keys match
                    // Convert AnyBlazeCodable to BlazeDocumentField
                    let docField: BlazeDocumentField
                    switch normalizedValue {
                    case .string(let s): docField = .string(s)
                    case .int(let i): docField = .int(i)
                    case .double(let d): docField = .double(d)
                    case .bool(let b): docField = .bool(b)
                    case .date(let d): docField = .date(d)
                    case .uuid(let u): docField = .uuid(u)
                    case .data(let data): docField = .data(data)
                    }
                    // Create a temporary document with the value to use fromFields
                    let tempDoc: [String: BlazeDocumentField] = [field: docField]
                    let rawKey = CompoundIndexKey.fromFields(tempDoc, fields: [field])
                    // Normalize the components the same way as insert() to ensure exact match
                    // IMPORTANT: Use AnyBlazeCodable(value) constructor (not explicit enum cases)
                    // to match exactly what insert() does
                    let normalizedComponents = rawKey.components.map { component -> AnyBlazeCodable in
                        // Extract the underlying value and recreate AnyBlazeCodable using the same constructor as insert()
                        switch component {
                        case .string(let s): return AnyBlazeCodable(s)
                        case .int(let i): return AnyBlazeCodable(i)
                        case .double(let d): return AnyBlazeCodable(d)
                        case .bool(let b): return AnyBlazeCodable(b)
                        case .date(let d): return AnyBlazeCodable(d)
                        case .uuid(let u): return AnyBlazeCodable(u)
                        case .data(let data): return AnyBlazeCodable(data)
                                            case .vector(let v): return AnyBlazeCodable(v)
                                            case .null: return AnyBlazeCodable("")
                                            case .array, .dictionary: return AnyBlazeCodable("")  // Arrays/dicts not supported in compound indexes
                                        }
                    }
                    let indexKey = CompoundIndexKey(normalizedComponents)
                    
                    // Try both normalized and raw keys to handle any edge cases
                    if let uuids = secondaryIndexes[field]?[indexKey] {
                        matchedUUIDs.formUnion(uuids)
                    } else if let uuids = secondaryIndexes[field]?[rawKey] {
                        // Fallback: try raw key in case normalization creates different instances
                        matchedUUIDs.formUnion(uuids)
                    }
                }
                
                BlazeLogger.debug("🔍 [FETCH] Total matched UUIDs: \(matchedUUIDs.count)")
                guard !matchedUUIDs.isEmpty else {
                    BlazeLogger.warn("🔍 [FETCH] No matches found for index '\(field)' with value '\(value)'")
                    return []
                }
                
                return try matchedUUIDs.compactMap { try _fetchNoSync(id: $0) }
            }
        }
        
        public func fetchAllIDs() throws -> [UUID] {
            return queue.sync {
                // Use snapshot to avoid concurrent modification issues
                let indexMapSnapshot = indexMap
                return Array(indexMapSnapshot.keys)
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
                // Use snapshot to avoid concurrent modification issues
                let indexMapSnapshot = indexMap
                let allIDs = Array(indexMapSnapshot.keys)
                let sortedIDs = allIDs.sorted(by: { $0.uuidString < $1.uuidString })  // Deterministic ordering
                
                // Validate offset: must be non-negative and within bounds
                guard offset >= 0 else {
                    return []  // Negative offset is invalid
                }
                
                guard offset < sortedIDs.count else {
                    return []  // Offset beyond data
                }
                
                // Validate limit: must be positive
                guard limit > 0 else {
                    return []  // Invalid limit
                }
                
                let endIndex = min(offset + limit, sortedIDs.count)
                // Double-check that endIndex is valid (should always be true after above checks)
                guard endIndex > offset && endIndex <= sortedIDs.count else {
                    return []
                }
                
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
            return queue.sync {
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
            // MVCC Path: Use indexMap as source of truth (it's updated on every insert/delete)
            // The version manager is for MVCC isolation, but indexMap tracks what's actually in the DB
            if mvccEnabled {
                // Always use indexMap for count - it's the most reliable source
                // The version manager is for transaction isolation, not for counting
                return queue.sync {
                    return indexMap.count
                }
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
    
