//
//  BlazeDBClient+Lifecycle.swift
//  BlazeDB
//
//  Process lifecycle safety: deterministic shutdown handling
//  Ensures file handles are closed, operations are idempotent, and failures are safe
//
import Foundation

extension BlazeDBClient {
    
    /// Explicitly close the database, releasing all resources.
    ///
    /// This method is idempotent: calling it multiple times is safe and has no effect after the first call.
    ///
    /// **What this does:**
    /// - Flushes all pending writes to disk
    /// - Releases file handles
    /// - Cleans up internal resources
    ///
    /// **After calling close():**
    /// - The database instance should not be used for further operations
    /// - Any subsequent operations will throw `BlazeDBError.invalidInput`
    ///
    /// **Note:** `deinit` will automatically call `close()` if not called explicitly,
    /// but explicit close is recommended for deterministic resource management.
    ///
    /// - Throws: `BlazeDBError` if flush fails (database may be partially closed)
    public func close() throws {
        // Idempotency: if already closed, do nothing
        guard !isClosed else {
            BlazeLogger.debug("Database '\(name)' already closed (idempotent call)")
            return
        }

        // Transaction safety: never implicitly commit active transactions on close.
        // If a transaction is open, rollback first so close/deinit stays fail-closed.
        var flushAllowed = true
        if transactionIndexMapSnapshot != nil {
            do {
                try rollbackTransaction()
                BlazeLogger.info("Rolled back active transaction during close for '\(name)'")
            } catch {
                BlazeLogger.error("Failed to rollback active transaction during close for '\(name)': \(error)")
                // Fail closed: do not flush if rollback could not be guaranteed.
                flushAllowed = false
            }
        }

        // Flush pending non-transactional changes while database is still open.
        // If we mark _isClosed first, persist() becomes a no-op via ensureNotClosed().
        if flushAllowed {
            do {
                try persist()
                BlazeLogger.debug("Flushed pending changes before close for '\(name)'")
            } catch {
                BlazeLogger.error("Failed to flush before close for '\(name)': \(error)")
                // Continue with close even if flush fails - better to release resources
                // than to leave database in inconsistent state
            }
        } else {
            BlazeLogger.warn("Skipping persist during close for '\(name)' because transaction rollback failed")
        }

        // Deterministically release underlying storage resources (locks/file handles).
        do {
            try collection.close()
        } catch {
            BlazeLogger.error("Failed to close collection resources for '\(name)': \(error)")
        }

        // Reduce plaintext secret lifetime after shutdown.
        password = nil
        BlazeDBClient.clearCachedKey(for: fileURL.path)

        // Mark closed after cleanup.
        _isClosed = true
        
        BlazeLogger.debug("Database '\(name)' closed successfully")
    }
    
    /// Check if the database is closed.
    ///
    /// - Returns: `true` if `close()` has been called, `false` otherwise
    public var isClosed: Bool {
        return _isClosed
    }
    
    
    /// Validate that database is not closed before operations.
    ///
    /// - Throws: `BlazeDBError.invalidInput` if database is closed
    internal func ensureNotClosed() throws {
        guard !isClosed else {
            throw BlazeDBError.invalidInput(
                reason: "Database '\(name)' has been closed. Create a new instance to continue operations."
            )
        }
    }
}

// MARK: - Signal-Safe Shutdown Documentation

/*
 Signal-Safe Shutdown Guidelines:
 
 BlazeDB handles process interruption (SIGTERM, SIGINT) safely:
 
 1. **File Locking**: OS-level file locks (flock) are automatically released
    when the process terminates, allowing other processes to open the database.
 
 2. **Atomic Writes**: All writes use atomic operations (.atomic flag) which
    ensure either the full write succeeds or nothing is written (no partial corruption).
 
 3. **WAL Recovery**: On next open, the Write-Ahead Log (WAL) is automatically
    recovered, ensuring no data loss from interrupted writes.
 
 4. **deinit Safety**: The deinit method calls persist() to flush pending changes,
    but this is best-effort. For critical applications, call close() explicitly
    in signal handlers or cleanup code.
 
 **Recommended Pattern:**
 ```swift
 signal(SIGTERM) { _ in
     // Flush and close database
     try? db.close()
     exit(0)
 }
 ```
 
 **Note**: Signal handlers should be minimal. If you need complex cleanup,
 use atexit() or similar mechanisms instead of signal handlers.
 */
