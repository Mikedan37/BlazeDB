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
    
    /// Recover from a crashed VACUUM operation before opening PageStore.
    ///
    /// Must run during init prior to PageStore/DynamicCollection creation so restored
    /// backup files are what get opened — not a stale handle to pre-recovery data.
    internal static func recoverFromVacuumCrashIfNeeded(fileURL: URL, metaURL: URL) throws {
        let baseURL = fileURL.deletingPathExtension()
        
        let vacuumLogURL = baseURL.appendingPathExtension("vacuum_in_progress")
        guard FileManager.default.fileExists(atPath: vacuumLogURL.path) else {
            return
        }
        
        BlazeLogger.warn("Detected incomplete VACUUM operation, recovering...")
        
        let dataBackupURL = baseURL.appendingPathExtension("vacuum_backup.blazedb")
        let metaBackupURL = baseURL.appendingPathExtension("vacuum_backup.meta")
        
        let hasDataBackup = FileManager.default.fileExists(atPath: dataBackupURL.path)
        let hasMetaBackup = FileManager.default.fileExists(atPath: metaBackupURL.path)
        let successMarkerURL = baseURL.appendingPathExtension("vacuum_success")
        let hasSuccess = FileManager.default.fileExists(atPath: successMarkerURL.path)
        
        if hasSuccess {
            BlazeLogger.info("VACUUM was successful, cleaning up...")
            
            BlazeAuthoritativeFileOps.removeItemIfExists(at: dataBackupURL, context: "VacuumRecovery(success cleanup data backup)")
            BlazeAuthoritativeFileOps.removeItemIfExists(at: metaBackupURL, context: "VacuumRecovery(success cleanup meta backup)")
            BlazeAuthoritativeFileOps.removeItemIfExists(at: vacuumLogURL, context: "VacuumRecovery(success cleanup intent)")
            BlazeAuthoritativeFileOps.removeItemIfExists(at: successMarkerURL, context: "VacuumRecovery(success marker)")
            
        } else if hasDataBackup || hasMetaBackup {
            BlazeLogger.warn("VACUUM was interrupted, restoring from backup...")
            
            if hasDataBackup {
                BlazeAuthoritativeFileOps.removeItemIfExists(at: fileURL, context: "VacuumRecovery(interrupted remove partial data)")
                try FileManager.default.moveItem(at: dataBackupURL, to: fileURL)
            }
            if hasMetaBackup {
                BlazeAuthoritativeFileOps.removeItemIfExists(at: metaURL, context: "VacuumRecovery(interrupted remove partial meta)")
                try FileManager.default.moveItem(at: metaBackupURL, to: metaURL)
            }
            
            BlazeAuthoritativeFileOps.removeItemIfExists(at: vacuumLogURL, context: "VacuumRecovery(post-restore intent)")
            
            BlazeLogger.info("Restored from VACUUM backup successfully")
            
        } else {
            BlazeAuthoritativeFileOps.removeItemIfExists(at: vacuumLogURL, context: "VacuumRecovery(early fail intent)")
            BlazeLogger.info("Cleaned up incomplete VACUUM marker")
        }
        
        BlazeLogger.info("VACUUM crash recovery complete")
    }
    
    /// Post-open VACUUM recovery hook (legacy call site; normally a no-op).
    ///
    /// Authoritative restore runs in `init` via the static overload above, before PageStore
    /// opens files. This instance method remains so existing init sequencing is unchanged and
    /// so a future refactor cannot drop pre-open recovery just because another recovery symbol
    /// still exists — if pre-init recovery ran, the intent marker is already gone.
    internal func recoverFromVacuumCrashIfNeeded() throws {
        try Self.recoverFromVacuumCrashIfNeeded(fileURL: collection.store.fileURL, metaURL: collection.metaURL)
    }
}
