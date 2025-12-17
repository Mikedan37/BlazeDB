#if !BLAZEDB_LINUX_CORE

import Foundation

extension DynamicCollection: MetaStore {
    public func fetchMeta() throws -> [String: BlazeDocumentField] {
        // PERFORMANCE: Use in-memory metaData if available to avoid loading from disk
        // This improves performance by avoiding expensive signature verification
        if !metaData.isEmpty {
            return metaData
        }
        
        // If layout file doesn't exist, return empty metadata (new database)
        if !FileManager.default.fileExists(atPath: metaURLPath.path) {
            BlazeLogger.debug("📋 [FETCHMETA] Layout file doesn't exist, returning empty metadata")
            return [:]
        }
        
        guard let salt = "AshPileSalt".data(using: .utf8) else {
            throw BlazeDBError.invalidData(reason: "Failed to encode salt as UTF-8")
        }
        do {
            let layout = try StorageLayout.loadSecure(
                from: metaURLPath,
                signingKey: encryptionKey,
                password: password,
                salt: salt
            )
            // Update in-memory metaData for future fetches
            self.metaData = layout.metaData
            return layout.metaData
        } catch let firstError {
            BlazeLogger.warn("⚠️ [FETCHMETA] First attempt failed: \(firstError). Retrying after brief delay...")
            Thread.sleep(forTimeInterval: 0.01)
            do {
                let layout = try StorageLayout.loadSecure(
                    from: metaURLPath,
                    signingKey: encryptionKey,
                    password: password,
                    salt: salt
                )
                BlazeLogger.info("✅ [FETCHMETA] Retry succeeded")
                // Update in-memory metaData for future fetches
                self.metaData = layout.metaData
                return layout.metaData
            } catch {
                BlazeLogger.error("❌ [FETCHMETA] Retry also failed: \(error)")
                return [:]
            }
        }
    }
    
    public func updateMeta(_ newMeta: [String: BlazeDocumentField]) throws {
        guard let salt = "AshPileSalt".data(using: .utf8) else {
            throw BlazeDBError.invalidData(reason: "Failed to encode salt as UTF-8")
        }
        var layout: StorageLayout
        
        // Handle case where layout file doesn't exist yet (new database)
        if FileManager.default.fileExists(atPath: metaURLPath.path) {
            do {
                layout = try StorageLayout.loadSecure(
                    from: metaURLPath,
                    signingKey: encryptionKey,
                    password: password,
                    salt: salt
                )
            } catch {
                BlazeLogger.warn("⚠️ [UPDATEMETA] Failed to load existing layout, creating new one: \(error)")
                layout = StorageLayout.empty()
            }
        } else {
            // New database - create empty layout
            BlazeLogger.debug("📋 [UPDATEMETA] Layout file doesn't exist, creating new layout")
            layout = StorageLayout.empty()
        }
        
        layout.metaData = newMeta
        try layout.saveSecure(to: metaURLPath, signingKey: encryptionKey)
        
        // PERFORMANCE: Update in-memory metaData to avoid loading from disk in saveLayout()
        // This significantly improves delete performance by avoiding expensive signature verification
        self.metaData = newMeta
    }
}

#endif // !BLAZEDB_LINUX_CORE
