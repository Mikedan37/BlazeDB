//
//  BlazeDBClient+Monitoring.swift
//  BlazeDB
//
//  Secure monitoring and observability APIs
//  Safe to expose to external visualization tools!
//
//  ⚠️ SECURITY: This API exposes ONLY metadata, never actual record data!
//
//  Created by Michael Danylchuk on 11/13/25.
//

import Foundation

// MARK: - Monitoring Data Structures

/// Complete database monitoring snapshot
/// Safe to expose - contains NO sensitive data!
public struct DatabaseMonitoringSnapshot: Codable, Equatable {
    public let database: DatabaseInfo
    public let storage: StorageInfo
    public let performance: PerformanceInfo
    public let health: HealthInfo
    public let schema: SchemaInfo
    public let timestamp: Date
    
    public init(database: DatabaseInfo, storage: StorageInfo, performance: PerformanceInfo, health: HealthInfo, schema: SchemaInfo) {
        self.database = database
        self.storage = storage
        self.performance = performance
        self.health = health
        self.schema = schema
        self.timestamp = Date()
    }
}

/// Basic database information
public struct DatabaseInfo: Codable, Equatable {
    public let name: String
    public let path: String
    public let createdAt: Date?
    public let lastModified: Date?
    public let isEncrypted: Bool
    public let version: String
    public let formatVersion: String  // "blazeBinary", "json", etc.
    
    public init(name: String, path: String, createdAt: Date?, lastModified: Date?, isEncrypted: Bool, version: String, formatVersion: String) {
        self.name = name
        self.path = path
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.isEncrypted = isEncrypted
        self.version = version
        self.formatVersion = formatVersion
    }
}

/// Storage statistics
public struct StorageInfo: Codable, Equatable {
    public let totalRecords: Int
    public let totalPages: Int
    public let orphanedPages: Int
    public let fileSizeBytes: Int64
    public let metadataSizeBytes: Int64
    public let dataFilePath: String
    public let metadataFilePath: String
    public let fragmentationPercent: Double
    public let avgRecordSizeBytes: Int
    public let largestRecordBytes: Int
    
    public init(totalRecords: Int, totalPages: Int, orphanedPages: Int, fileSizeBytes: Int64, metadataSizeBytes: Int64, dataFilePath: String, metadataFilePath: String, fragmentationPercent: Double, avgRecordSizeBytes: Int, largestRecordBytes: Int) {
        self.totalRecords = totalRecords
        self.totalPages = totalPages
        self.orphanedPages = orphanedPages
        self.fileSizeBytes = fileSizeBytes
        self.metadataSizeBytes = metadataSizeBytes
        self.dataFilePath = dataFilePath
        self.metadataFilePath = metadataFilePath
        self.fragmentationPercent = fragmentationPercent
        self.avgRecordSizeBytes = avgRecordSizeBytes
        self.largestRecordBytes = largestRecordBytes
    }
}

/// Performance metrics
public struct PerformanceInfo: Codable, Equatable {
    public let mvccEnabled: Bool
    public let activeTransactions: Int
    public let totalVersions: Int
    public let obsoleteVersions: Int
    public let gcRunCount: Int
    public let lastGCDuration: TimeInterval?
    public let indexCount: Int
    public let indexNames: [String]
    
    public init(mvccEnabled: Bool, activeTransactions: Int, totalVersions: Int, obsoleteVersions: Int, gcRunCount: Int, lastGCDuration: TimeInterval?, indexCount: Int, indexNames: [String]) {
        self.mvccEnabled = mvccEnabled
        self.activeTransactions = activeTransactions
        self.totalVersions = totalVersions
        self.obsoleteVersions = obsoleteVersions
        self.gcRunCount = gcRunCount
        self.lastGCDuration = lastGCDuration
        self.indexCount = indexCount
        self.indexNames = indexNames
    }
}

/// Health indicators
public struct HealthInfo: Codable, Equatable {
    public let status: String  // "healthy", "warning", "critical"
    public let needsVacuum: Bool
    public let fragmentationHigh: Bool
    public let orphanedPagesHigh: Bool
    public let gcNeeded: Bool
    public let warnings: [String]
    public let lastHealthCheck: Date
    
    public init(status: String, needsVacuum: Bool, fragmentationHigh: Bool, orphanedPagesHigh: Bool, gcNeeded: Bool, warnings: [String]) {
        self.status = status
        self.needsVacuum = needsVacuum
        self.fragmentationHigh = fragmentationHigh
        self.orphanedPagesHigh = orphanedPagesHigh
        self.gcNeeded = gcNeeded
        self.warnings = warnings
        self.lastHealthCheck = Date()
    }
}

/// Schema information (field names and types, NO actual data!)
public struct SchemaInfo: Codable, Equatable {
    public let totalFields: Int
    public let commonFields: [String]  // Field names only
    public let customFields: [String]  // Field names only
    public let inferredTypes: [String: String]  // field -> type (e.g., "age" -> "int")
    
    public init(totalFields: Int, commonFields: [String], customFields: [String], inferredTypes: [String: String]) {
        self.totalFields = totalFields
        self.commonFields = commonFields
        self.customFields = customFields
        self.inferredTypes = inferredTypes
    }
}

// MARK: - Monitoring APIs

extension BlazeDBClient {
    
    /// Get complete monitoring snapshot
    /// 🛡️ SECURE: Returns only metadata, never actual record data!
    ///
    /// Perfect for:
    /// - External monitoring tools
    /// - Dashboards
    /// - Health checks
    /// - Visualization apps
    ///
    /// ## Example
    /// ```swift
    /// let snapshot = try db.getMonitoringSnapshot()
    /// print("Records: \(snapshot.storage.totalRecords)")
    /// print("Size: \(snapshot.storage.fileSizeBytes / 1024) KB")
    /// print("Health: \(snapshot.health.status)")
    /// ```
    public func getMonitoringSnapshot() throws -> DatabaseMonitoringSnapshot {
        let dbInfo = getDatabaseInfo()
        let storageInfo = try getStorageInfo()
        let perfInfo = getPerformanceInfo()
        let healthInfo = try getHealthInfo()
        let schemaInfo = try getSchemaInfo()
        
        return DatabaseMonitoringSnapshot(
            database: dbInfo,
            storage: storageInfo,
            performance: perfInfo,
            health: healthInfo,
            schema: schemaInfo
        )
    }
    
    /// Get list of all database files (for cleanup, backup, visualization)
    /// 🛡️ SECURE: Returns only file paths, not contents!
    public func listDatabaseFiles() throws -> [String] {
        var files: [String] = []
        
        // Main database file
        if FileManager.default.fileExists(atPath: fileURL.path) {
            files.append(fileURL.path)
        }
        
        // Metadata file
        if FileManager.default.fileExists(atPath: metaURL.path) {
            files.append(metaURL.path)
        }
        
        // Transaction log
        let txnLogURL = fileURL.deletingPathExtension().appendingPathExtension("txn_log.json")
        if FileManager.default.fileExists(atPath: txnLogURL.path) {
            files.append(txnLogURL.path)
        }
        
        // WAL file (if exists)
        let walURL = fileURL.deletingPathExtension().appendingPathExtension("wal")
        if FileManager.default.fileExists(atPath: walURL.path) {
            files.append(walURL.path)
        }
        
        // Backup files
        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("backup")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            files.append(backupURL.path)
        }
        
        return files
    }
    
    // MARK: - Private Helpers
    
    private func getDatabaseInfo() -> DatabaseInfo {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let createdAt = attrs?[.creationDate] as? Date
        let modifiedAt = attrs?[.modificationDate] as? Date
        
        // Infer format from metadata
        let formatVersion: String
        if let layout = try? StorageLayout.load(from: metaURL) {
            formatVersion = layout.encodingFormat
        } else {
            formatVersion = "unknown"
        }
        
        return DatabaseInfo(
            name: name,
            path: fileURL.path,
            createdAt: createdAt,
            lastModified: modifiedAt,
            isEncrypted: true,  // Always encrypted in BlazeDB!
            version: "1.0",
            formatVersion: formatVersion
        )
    }
    
    private func getStorageInfo() throws -> StorageInfo {
        let recordCount = collection.indexMap.count
        let totalPages = collection.nextPageIndex
        
        // Calculate file sizes
        let fileAttrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSizeBytes = (fileAttrs?[.size] as? NSNumber)?.int64Value ?? 0
        
        let metaAttrs = try? FileManager.default.attributesOfItem(atPath: metaURL.path)
        let metaSizeBytes = (metaAttrs?[.size] as? NSNumber)?.int64Value ?? 0
        
        // Calculate fragmentation
        let usedPages = recordCount
        let fragmentation = totalPages > 0 ? Double(totalPages - usedPages) / Double(totalPages) * 100 : 0
        
        // Calculate average record size
        let avgSize = recordCount > 0 ? Int(fileSizeBytes) / recordCount : 0
        
        return StorageInfo(
            totalRecords: recordCount,
            totalPages: totalPages,
            orphanedPages: totalPages - usedPages,
            fileSizeBytes: fileSizeBytes,
            metadataSizeBytes: metaSizeBytes,
            dataFilePath: fileURL.path,
            metadataFilePath: metaURL.path,
            fragmentationPercent: fragmentation,
            avgRecordSizeBytes: avgSize,
            largestRecordBytes: collection.largestRecordSize
        )
    }
    
    private func getPerformanceInfo() -> PerformanceInfo {
        let mvccEnabled = collection.mvccEnabled
        let versionStats = collection.versionManager.getStats()
        let gcStats = collection.gcManager.getStats()
        
        // Get index names
        let indexNames = collection.secondaryIndexes.keys.map { String($0) }
        
        // Calculate obsolete versions (total - unique records)
        let obsoleteVersions = versionStats.totalVersions - versionStats.uniqueRecords
        
        return PerformanceInfo(
            mvccEnabled: mvccEnabled,
            activeTransactions: versionStats.activeSnapshots,  // Fixed: use activeSnapshots
            totalVersions: versionStats.totalVersions,
            obsoleteVersions: obsoleteVersions,  // Calculated from stats
            gcRunCount: gcStats.totalRuns,
            lastGCDuration: nil,  // MVCCGCStats doesn't have duration, only lastGCTime
            indexCount: collection.secondaryIndexes.count,
            indexNames: indexNames
        )
    }
    
    private func getHealthInfo() throws -> HealthInfo {
        let storageInfo = try getStorageInfo()
        
        var warnings: [String] = []
        var status = "healthy"
        
        // Check fragmentation
        let fragmentationHigh = storageInfo.fragmentationPercent > 30
        if fragmentationHigh {
            warnings.append("High fragmentation (\(String(format: "%.1f", storageInfo.fragmentationPercent))%) - consider VACUUM")
            status = "warning"
        }
        
        // Check orphaned pages
        let orphanedHigh = storageInfo.orphanedPages > 100
        if orphanedHigh {
            warnings.append("\(storageInfo.orphanedPages) orphaned pages - run GC")
            if status == "healthy" { status = "warning" }
        }
        
        // Check if GC is needed
        let perfInfo = getPerformanceInfo()
        let gcNeeded = perfInfo.obsoleteVersions > 1000
        if gcNeeded {
            warnings.append("\(perfInfo.obsoleteVersions) obsolete MVCC versions - run GC")
            if status == "healthy" { status = "warning" }
        }
        
        // Check if VACUUM is needed
        let needsVacuum = fragmentationHigh || orphanedHigh
        if needsVacuum && warnings.count > 2 {
            status = "critical"
        }
        
        return HealthInfo(
            status: status,
            needsVacuum: needsVacuum,
            fragmentationHigh: fragmentationHigh,
            orphanedPagesHigh: orphanedHigh,
            gcNeeded: gcNeeded,
            warnings: warnings
        )
    }
    
    private func getSchemaInfo() throws -> SchemaInfo {
        // Get all unique field names from a sample of records (NOT the values!)
        var fieldSet = Set<String>()
        var typeInference: [String: String] = [:]
        
        // Sample first 100 records to infer schema
        let sampleSize = min(100, collection.indexMap.count)
        let sampleIDs = Array(collection.indexMap.keys.prefix(sampleSize))
        
        for id in sampleIDs {
            guard let record = try? collection.fetch(id: id) else { continue }
            
            for (key, value) in record.storage {
                fieldSet.insert(key)
                
                // Infer type (NOT the value!)
                let typeName: String
                switch value {
                case .string: typeName = "string"
                case .int: typeName = "int"
                case .double: typeName = "double"
                case .bool: typeName = "bool"
                case .uuid: typeName = "uuid"
                case .date: typeName = "date"
                case .data: typeName = "data"
                case .array: typeName = "array"
                case .dictionary: typeName = "dictionary"
                case .vector: typeName = "vector"
                case .null: typeName = "null"
                }
                
                // Store type (or mark as "mixed" if types vary)
                if let existing = typeInference[key], existing != typeName {
                    typeInference[key] = "mixed"
                } else {
                    typeInference[key] = typeName
                }
            }
        }
        
        // Split into common vs custom fields
        let commonFieldNames = COMMON_FIELDS_REVERSE.keys
        let common = fieldSet.filter { commonFieldNames.contains($0) }.sorted()
        let custom = fieldSet.filter { !commonFieldNames.contains($0) }.sorted()
        
        return SchemaInfo(
            totalFields: fieldSet.count,
            commonFields: common,
            customFields: custom,
            inferredTypes: typeInference
        )
    }
}

// MARK: - Monitoring API for External Tools

extension BlazeDBClient {
    
    /// Export monitoring data as JSON (safe for external tools)
    /// 🛡️ SECURE: Contains NO sensitive data, only metadata!
    ///
    /// Perfect for:
    /// - Web dashboards
    /// - Monitoring apps (like your BlazeDBVisualizer!)
    /// - Grafana / Prometheus exporters
    /// - CI/CD health checks
    ///
    /// ## Example
    /// ```swift
    /// let json = try db.exportMonitoringJSON()
    /// // Send to monitoring service, save to file, etc.
    /// ```
    public func exportMonitoringJSON() throws -> Data {
        let snapshot = try getMonitoringSnapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }
    
    /// Get quick health status (for dashboards)
    /// Returns: "healthy", "warning", or "critical"
    public func getHealthStatus() throws -> String {
        let health = try getHealthInfo()
        return health.status
    }
    
    /// Get database size on disk (total of all files)
    public func getTotalDiskUsage() throws -> Int64 {
        let files = try listDatabaseFiles()
        var total: Int64 = 0
        
        for filePath in files {
            let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
            total += (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        
        return total
    }
    
    /// Get record count (fast, no actual reads!)
    public func getRecordCount() -> Int {
        return collection.indexMap.count
    }
    
    /// Check if database needs maintenance
    public func needsMaintenance() throws -> (vacuum: Bool, gc: Bool, reasons: [String]) {
        let health = try getHealthInfo()
        return (
            vacuum: health.needsVacuum,
            gc: health.gcNeeded,
            reasons: health.warnings
        )
    }
}

// MARK: - Discovery API (List All Databases)

extension BlazeDBClient {
    
    /// Discover all BlazeDB databases in a directory
    /// 🛡️ SECURE: Returns only file paths, not contents!
    ///
    /// Perfect for building a database browser/selector UI
    ///
    /// ## Example
    /// ```swift
    /// let appDir = FileManager.default.documentsDirectory
    /// let databases = BlazeDBClient.discoverDatabases(in: appDir)
    /// print("Found \(databases.count) databases")
    /// ```
    public static func discoverDatabases(in directory: URL) throws -> [DatabaseDiscoveryInfo] {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        let blazeDBFiles = contents.filter { $0.pathExtension == "blazedb" }
        
        return blazeDBFiles.compactMap { url in
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
            
            let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let createdAt = attrs[.creationDate] as? Date
            let modifiedAt = attrs[.modificationDate] as? Date
            
            // Read metadata to get record count (without opening full DB)
            let metaURL = url.deletingPathExtension().appendingPathExtension("meta")
            let recordCount: Int
            if let layout = try? StorageLayout.load(from: metaURL) {
                recordCount = layout.indexMap.count
            } else {
                recordCount = 0
            }
            
            return DatabaseDiscoveryInfo(
                name: url.deletingPathExtension().lastPathComponent,
                path: url.path,
                fileSizeBytes: fileSize,
                recordCount: recordCount,
                createdAt: createdAt,
                lastModified: modifiedAt
            )
        }
    }
}

/// Database discovery information
public struct DatabaseDiscoveryInfo: Codable {
    public let name: String
    public let path: String
    public let fileSizeBytes: Int64
    public let recordCount: Int
    public let createdAt: Date?
    public let lastModified: Date?
    
    public init(name: String, path: String, fileSizeBytes: Int64, recordCount: Int, createdAt: Date?, lastModified: Date?) {
        self.name = name
        self.path = path
        self.fileSizeBytes = fileSizeBytes
        self.recordCount = recordCount
        self.createdAt = createdAt
        self.lastModified = lastModified
    }
}

