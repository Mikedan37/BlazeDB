//  ScanService.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
//
//  ✅ UPGRADED: Now uses BlazeDB's official Monitoring API
//  ✅ SECURE: No password needed for discovery!
//  ✅ FAST: Reads only metadata, not full databases
//
import Foundation
import BlazeDB

/// Service for discovering and scanning BlazeDB databases
/// Uses the official BlazeDB Monitoring API for safe, fast discovery
enum ScanService {
    
    /// Scan for all BlazeDB databases in common locations
    /// Returns enriched data with record counts, sizes, health status
    static func scanAllBlazeDBs() -> [DBRecord] {
        let fileManager = FileManager.default
        var discovered: [DBRecord] = []
        
        // Search common locations
        let searchPaths: [URL] = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Developer"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        ]
        
        for searchPath in searchPaths {
            print("🔍 Scanning: \(searchPath.path)")
            guard fileManager.fileExists(atPath: searchPath.path) else { 
                print("   ⏭️  Path doesn't exist, skipping")
                continue 
            }
            
            do {
                let databases = try BlazeDBClient.discoverDatabases(in: searchPath)
                print("   ✅ Found \(databases.count) databases in \(searchPath.lastPathComponent)")
                
                for db in databases {
                    // Skip backup files (created by BackupRestoreService)
                    if db.name.hasPrefix("backup_v") || 
                       db.name.hasPrefix("auto_before_edit_") ||
                       db.path.contains("/Backups/") {
                        print("      ⏭️  Skipping backup: \(db.name)")
                        continue
                    }
                    
                    print("      📦 \(db.name) (\(db.recordCount) records)")
                    
                    // Infer basic health status from available metadata
                    let inferredStatus: String = {
                        if db.recordCount == 0 {
                            return "empty"
                        } else if db.fileSizeBytes > 100_000_000 {  // > 100MB
                            return "large"
                        } else if db.recordCount > 10000 {
                            return "active"
                        } else {
                            return "ready"
                        }
                    }()
                    
                    // Try to get full monitoring snapshot (if we can access it)
                    let record = DBRecord(
                        id: UUID(),
                        name: db.name,
                        path: db.path,
                        appName: extractAppName(from: db.path),
                        sizeInBytes: Int(db.fileSizeBytes),
                        recordCount: db.recordCount,
                        modifiedDate: db.lastModified ?? Date(),
                        isEncrypted: true,  // All BlazeDB databases are encrypted!
                        healthStatus: inferredStatus,
                        fragmentationPercent: nil,
                        needsVacuum: false,
                        mvccEnabled: nil,
                        indexCount: nil
                    )
                    discovered.append(record)
                }
            } catch {
                print("   ⚠️  Error scanning \(searchPath.lastPathComponent): \(error)")
                continue
            }
        }
        
        // Recursively scan developer folder for nested databases
        if let devPath = searchPaths.first(where: { $0.lastPathComponent == "Developer" }) {
            discovered.append(contentsOf: deepScan(directory: devPath))
        }
        
        return discovered.sorted { $0.name < $1.name }
    }
    
    /// Deep recursive scan for nested databases
    private static func deepScan(directory: URL) -> [DBRecord] {
        let fileManager = FileManager.default
        var found: [DBRecord] = []
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "blazedb" else { continue }
            
            // Use discovery API for each database
            if let parent = fileURL.deletingLastPathComponent().path.isEmpty ? nil : fileURL.deletingLastPathComponent(),
               let databases = try? BlazeDBClient.discoverDatabases(in: parent) {
                
                for db in databases where db.path == fileURL.path {
                    // Skip backup files
                    if db.name.hasPrefix("backup_v") || 
                       db.name.hasPrefix("auto_before_edit_") ||
                       db.path.contains("/Backups/") {
                        continue
                    }
                    
                    // Infer status
                    let inferredStatus: String = {
                        if db.recordCount == 0 {
                            return "empty"
                        } else if db.fileSizeBytes > 100_000_000 {
                            return "large"
                        } else if db.recordCount > 10000 {
                            return "active"
                        } else {
                            return "ready"
                        }
                    }()
                    
                    let record = DBRecord(
                        id: UUID(),
                        name: db.name,
                        path: db.path,
                        appName: extractAppName(from: db.path),
                        sizeInBytes: Int(db.fileSizeBytes),
                        recordCount: db.recordCount,
                        modifiedDate: db.lastModified ?? Date(),
                        isEncrypted: true,
                        healthStatus: inferredStatus,
                        fragmentationPercent: nil,
                        needsVacuum: false,
                        mvccEnabled: nil,
                        indexCount: nil
                    )
                    found.append(record)
                }
            }
        }
        
        return found
    }
    
    /// Extract app name from file path
    /// Example: "/Users/mike/Developer/MyApp/data.blazedb" -> "MyApp"
    private static func extractAppName(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents
        
        // Try to find a meaningful parent directory name
        if let projectIdx = components.firstIndex(where: { $0 == "Developer" || $0 == "Documents" }) {
            let afterProject = components.dropFirst(projectIdx + 1)
            if let appName = afterProject.first, appName != url.lastPathComponent {
                return appName
            }
        }
        
        // Fallback to database name
        return url.deletingPathExtension().lastPathComponent
    }
    
    /// Get enriched monitoring data for a specific database (requires password)
    /// This provides full health, performance, and schema information
    static func getFullMonitoringData(for dbPath: String, password: String) throws -> DBRecord {
        let url = URL(fileURLWithPath: dbPath)
        let name = url.deletingPathExtension().lastPathComponent
        
        // Open database with password
        let db = try BlazeDBClient(name: name, fileURL: url, password: password)
        defer {
            // Database will auto-close on deinit, but we can explicitly close if needed
        }
        
        // Get full monitoring snapshot
        let snapshot = try db.getMonitoringSnapshot()
        
        // Create enriched record
        return DBRecord(
            id: UUID(),
            name: snapshot.database.name,
            path: snapshot.database.path,
            appName: extractAppName(from: snapshot.database.path),
            sizeInBytes: Int(snapshot.storage.fileSizeBytes),
            recordCount: snapshot.storage.totalRecords,
            modifiedDate: snapshot.database.lastModified ?? Date(),
            isEncrypted: snapshot.database.isEncrypted,
            healthStatus: snapshot.health.status,
            fragmentationPercent: snapshot.storage.fragmentationPercent,
            needsVacuum: snapshot.health.needsVacuum,
            mvccEnabled: snapshot.performance.mvccEnabled,
            indexCount: snapshot.performance.indexCount,
            warnings: snapshot.health.warnings,
            formatVersion: snapshot.database.formatVersion,
            totalPages: snapshot.storage.totalPages,
            orphanedPages: snapshot.storage.orphanedPages,
            gcRunCount: snapshot.performance.gcRunCount,
            obsoleteVersions: snapshot.performance.obsoleteVersions
        )
    }
}
