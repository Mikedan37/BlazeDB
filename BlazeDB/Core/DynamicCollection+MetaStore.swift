#if !BLAZEDB_LINUX_CORE

import Foundation

extension DynamicCollection: MetaStore {
    public func fetchMeta() throws -> [String: BlazeDocumentField] {
        // PERFORMANCE: Load layout to get metaData
        // This avoids expensive signature verification by loading from disk
        let layout = try StorageLayout.loadSecure(
            from: metaURLPath,
            signingKey: encryptionKey,
            password: password,
            salt: kdfSalt,
            allowUnsignedLayoutFallback: true
        )
        if !layout.metaData.isEmpty {
            return layout.metaData
        }
        
        // If layout file doesn't exist, return empty metadata (new database)
        if !FileManager.default.fileExists(atPath: metaURLPath.path) {
            BlazeLogger.debug("📋 [FETCHMETA] Layout file doesn't exist, returning empty metadata")
            return [:]
        }
        
        let salt = kdfSalt
        do {
            let layout = try StorageLayout.loadSecure(
                from: metaURLPath,
                signingKey: encryptionKey,
                password: password,
                salt: salt,
                allowUnsignedLayoutFallback: true
            )
            // metaData is stored in StorageLayout, not DynamicCollection
            return layout.metaData
        } catch let firstError {
            BlazeLogger.warn("⚠️ [FETCHMETA] First attempt failed: \(firstError). Retrying after brief delay...")
            Thread.sleep(forTimeInterval: 0.01)
            do {
                let layout = try StorageLayout.loadSecure(
                    from: metaURLPath,
                    signingKey: encryptionKey,
                    password: password,
                    salt: salt,
                    allowUnsignedLayoutFallback: true
                )
                BlazeLogger.info("✅ [FETCHMETA] Retry succeeded")
                // metaData is stored in StorageLayout, not DynamicCollection
                return layout.metaData
            } catch {
                BlazeLogger.error("❌ [FETCHMETA] Retry also failed: \(error)")
                return [:]
            }
        }
    }
    
    public func updateMeta(_ newMeta: [String: BlazeDocumentField]) throws {
        let salt = kdfSalt
        var layout: StorageLayout
        
        // Handle case where layout file doesn't exist yet (new database)
        if FileManager.default.fileExists(atPath: metaURLPath.path) {
            do {
                layout = try StorageLayout.loadSecure(
                    from: metaURLPath,
                    signingKey: encryptionKey,
                    password: password,
                    salt: salt,
                    allowUnsignedLayoutFallback: true
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
        
        // metaData is stored in StorageLayout, not DynamicCollection
        // It will be loaded from disk when needed
    }
}

#endif // !BLAZEDB_LINUX_CORE
