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
            BlazeLogger.warn("Detected incomplete VACUUM operation, recovering...")
            
            // Check for backup files
            let dataBackupURL = baseURL.appendingPathExtension("vacuum_backup.blazedb")
            let metaBackupURL = baseURL.appendingPathExtension("vacuum_backup.meta")
            
            let hasBackup = FileManager.default.fileExists(atPath: dataBackupURL.path)
            
            // Check for success marker
            let successMarkerURL = baseURL.appendingPathExtension("vacuum_success")
            let hasSuccess = FileManager.default.fileExists(atPath: successMarkerURL.path)
            
            if hasSuccess {
                // VACUUM completed successfully but cleanup didn't finish
                BlazeLogger.info("VACUUM was successful, cleaning up...")
                
                BlazeAuthoritativeFileOps.removeItemIfExists(at: dataBackupURL, context: "VacuumRecovery(success cleanup data backup)")
                BlazeAuthoritativeFileOps.removeItemIfExists(at: metaBackupURL, context: "VacuumRecovery(success cleanup meta backup)")
                BlazeAuthoritativeFileOps.removeItemIfExists(at: vacuumLogURL, context: "VacuumRecovery(success cleanup intent)")
                BlazeAuthoritativeFileOps.removeItemIfExists(at: successMarkerURL, context: "VacuumRecovery(success marker)")
                
            } else if hasBackup {
                // VACUUM was in progress when crash happened
                // Restore from backup to be safe
                BlazeLogger.warn("VACUUM was interrupted, restoring from backup...")
                
                let currentDataURL = collection.store.fileURL
                let currentMetaURL = collection.metaURL
                
                // Remove potentially incomplete current files
                BlazeAuthoritativeFileOps.removeItemIfExists(at: currentDataURL, context: "VacuumRecovery(interrupted remove partial data)")
                BlazeAuthoritativeFileOps.removeItemIfExists(at: currentMetaURL, context: "VacuumRecovery(interrupted remove partial meta)")
                
                // Restore from backup
                if FileManager.default.fileExists(atPath: dataBackupURL.path) {
                    try FileManager.default.moveItem(at: dataBackupURL, to: currentDataURL)
                }
                if FileManager.default.fileExists(atPath: metaBackupURL.path) {
                    try FileManager.default.moveItem(at: metaBackupURL, to: currentMetaURL)
                }
                
                // Clean up
                BlazeAuthoritativeFileOps.removeItemIfExists(at: vacuumLogURL, context: "VacuumRecovery(post-restore intent)")
                
                BlazeLogger.info("Restored from VACUUM backup successfully")
                
            } else {
                // No backup, VACUUM probably failed early - just clean up marker
                BlazeAuthoritativeFileOps.removeItemIfExists(at: vacuumLogURL, context: "VacuumRecovery(early fail intent)")
                BlazeLogger.info("Cleaned up incomplete VACUUM marker")
            }
            
            BlazeLogger.info("VACUUM crash recovery complete")
        }
    }
}

