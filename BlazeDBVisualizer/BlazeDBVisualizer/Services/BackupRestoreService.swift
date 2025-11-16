//
//  BackupRestoreService.swift
//  BlazeDBVisualizer
//
//  Backup and restore databases safely
//  ✅ Automatic backups before VACUUM
//  ✅ Named backups with timestamps
//  ✅ Easy restore
//
//  Created by Michael Danylchuk on 11/14/25.
//

import Foundation
import BlazeDB

final class BackupRestoreService {
    
    static let shared = BackupRestoreService()
    
    private init() {}
    
    // MARK: - Backup Operations
    
    /// Create a backup of a database
    /// Returns the backup file URL
    func createBackup(dbPath: String, name: String? = nil) throws -> URL {
        let sourceURL = URL(fileURLWithPath: dbPath)
        let sourceMetaURL = sourceURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Generate backup name
        let backupName: String
        if let name = name {
            backupName = name
        } else {
            let timestamp = DateFormatter.backupFormatter.string(from: Date())
            let dbName = sourceURL.deletingPathExtension().lastPathComponent
            backupName = "\(dbName)_backup_\(timestamp)"
        }
        
        // Create backups directory if needed
        let backupsDir = sourceURL.deletingLastPathComponent().appendingPathComponent("Backups")
        try? FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        
        let backupURL = backupsDir.appendingPathComponent(backupName).appendingPathExtension("blazedb")
        let backupMetaURL = backupURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Copy database file
        try FileManager.default.copyItem(at: sourceURL, to: backupURL)
        
        // Copy metadata file
        if FileManager.default.fileExists(atPath: sourceMetaURL.path) {
            try FileManager.default.copyItem(at: sourceMetaURL, to: backupMetaURL)
        }
        
        return backupURL
    }
    
    /// List all backups for a database
    func listBackups(for dbPath: String) throws -> [BackupInfo] {
        let sourceURL = URL(fileURLWithPath: dbPath)
        let backupsDir = sourceURL.deletingLastPathComponent().appendingPathComponent("Backups")
        
        guard FileManager.default.fileExists(atPath: backupsDir.path) else {
            return []
        }
        
        let files = try FileManager.default.contentsOfDirectory(
            at: backupsDir,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        let backups = files
            .filter { $0.pathExtension == "blazedb" }
            .compactMap { url -> BackupInfo? in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                    return nil
                }
                
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                let created = attrs[.creationDate] as? Date ?? Date()
                
                return BackupInfo(
                    name: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    size: size,
                    createdAt: created
                )
            }
            .sorted { $0.createdAt > $1.createdAt }  // Newest first
        
        return backups
    }
    
    /// Restore a database from backup
    func restoreFromBackup(backupURL: URL, to destinationPath: String) throws {
        let destURL = URL(fileURLWithPath: destinationPath)
        let destMetaURL = destURL.deletingPathExtension().appendingPathExtension("meta")
        
        let backupMetaURL = backupURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Safety: Create a backup of the current database first
        let safetyBackupURL = try createSafetyBackup(dbPath: destinationPath)
        
        do {
            // Delete current database
            try? FileManager.default.removeItem(at: destURL)
            try? FileManager.default.removeItem(at: destMetaURL)
            
            // Copy backup files
            try FileManager.default.copyItem(at: backupURL, to: destURL)
            
            if FileManager.default.fileExists(atPath: backupMetaURL.path) {
                try FileManager.default.copyItem(at: backupMetaURL, to: destMetaURL)
            }
            
            // Delete safety backup (restore succeeded)
            try? FileManager.default.removeItem(at: safetyBackupURL)
            
        } catch {
            // Restore failed! Recover from safety backup
            try? FileManager.default.removeItem(at: destURL)
            try? FileManager.default.removeItem(at: destMetaURL)
            
            if FileManager.default.fileExists(atPath: safetyBackupURL.path) {
                let safetyMetaURL = safetyBackupURL.deletingPathExtension().appendingPathExtension("meta")
                try? FileManager.default.copyItem(at: safetyBackupURL, to: destURL)
                try? FileManager.default.copyItem(at: safetyMetaURL, to: destMetaURL)
            }
            
            throw BackupRestoreError.restoreFailed(underlying: error)
        }
    }
    
    /// Delete a backup
    func deleteBackup(backupURL: URL) throws {
        let metaURL = backupURL.deletingPathExtension().appendingPathExtension("meta")
        
        try FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
    
    // MARK: - Private Helpers
    
    private func createSafetyBackup(dbPath: String) throws -> URL {
        let sourceURL = URL(fileURLWithPath: dbPath)
        let safetyURL = sourceURL.deletingPathExtension()
            .appendingPathExtension("safety_\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("blazedb")
        
        try FileManager.default.copyItem(at: sourceURL, to: safetyURL)
        
        return safetyURL
    }
}

// MARK: - Backup Info

struct BackupInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    let createdAt: Date
    
    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(url)
    }
    
    static func == (lhs: BackupInfo, rhs: BackupInfo) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url
    }
}

// MARK: - Errors

enum BackupRestoreError: LocalizedError {
    case restoreFailed(underlying: Error)
    case backupNotFound
    
    var errorDescription: String? {
        switch self {
        case .restoreFailed(let error):
            return "Restore failed: \(error.localizedDescription)"
        case .backupNotFound:
            return "Backup file not found"
        }
    }
}

// MARK: - Date Formatter Extension

extension DateFormatter {
    static let backupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter
    }()
}

