//
//  VacuumRecovery.swift
//  BlazeDB
//
//  Recovery from crashes during VACUUM operation
//
//  If the process crashes during VACUUM, we need to detect it
//  and recover by either completing or rolling back.
//
//  Created: 2025-11-13
//

import Foundation

extension BlazeDBClient {
    
    /// Recover from a crashed VACUUM operation
    ///
    /// Called during initialization to detect and recover from
    /// incomplete VACUUM operations.
    internal func recoverFromVacuumCrashIfNeeded() throws {
        let baseURL = collection.store.fileURL.deletingPathExtension()
        
        // Check for VACUUM intent log
        let vacuumLogURL = baseURL.appendingPathExtension("vacuum_in_progress")
        let hasVacuumIntent = FileManager.default.fileExists(atPath: vacuumLogURL.path)
        
        if hasVacuumIntent {
            print("⚠️ Detected incomplete VACUUM operation, recovering...")
            
            // Check for backup files
            let dataBackupURL = baseURL.appendingPathExtension("vacuum_backup.blazedb")
            let metaBackupURL = baseURL.appendingPathExtension("vacuum_backup.meta")
            
            let hasBackup = FileManager.default.fileExists(atPath: dataBackupURL.path)
            
            // Check for success marker
            let successMarkerURL = baseURL.appendingPathExtension("vacuum_success")
            let hasSuccess = FileManager.default.fileExists(atPath: successMarkerURL.path)
            
            if hasSuccess {
                // VACUUM completed successfully but cleanup didn't finish
                print("   ✅ VACUUM was successful, cleaning up...")
                
                try? FileManager.default.removeItem(at: dataBackupURL)
                try? FileManager.default.removeItem(at: metaBackupURL)
                try? FileManager.default.removeItem(at: vacuumLogURL)
                try? FileManager.default.removeItem(at: successMarkerURL)
                
            } else if hasBackup {
                // VACUUM was in progress when crash happened
                // Restore from backup to be safe
                print("   ⚠️ VACUUM was interrupted, restoring from backup...")
                
                let currentDataURL = collection.store.fileURL
                let currentMetaURL = collection.metaURL
                
                // Remove potentially incomplete current files
                try? FileManager.default.removeItem(at: currentDataURL)
                try? FileManager.default.removeItem(at: currentMetaURL)
                
                // Restore from backup
                if FileManager.default.fileExists(atPath: dataBackupURL.path) {
                    try FileManager.default.moveItem(at: dataBackupURL, to: currentDataURL)
                }
                if FileManager.default.fileExists(atPath: metaBackupURL.path) {
                    try FileManager.default.moveItem(at: metaBackupURL, to: currentMetaURL)
                }
                
                // Clean up
                try? FileManager.default.removeItem(at: vacuumLogURL)
                
                print("   ✅ Restored from backup successfully")
                
            } else {
                // No backup, VACUUM probably failed early - just clean up marker
                try? FileManager.default.removeItem(at: vacuumLogURL)
                print("   ✅ Cleaned up incomplete VACUUM marker")
            }
            
            print("   ✅ VACUUM crash recovery complete")
        }
    }
}

