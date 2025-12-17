//
//  DynamicCollection+Migration.swift
//  BlazeDB
//
//  Automatic migration integration for DynamicCollection
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

extension DynamicCollection {
    
    /// Perform automatic migration if needed (called on init)
    internal func performAutoMigrationIfNeeded() throws {
        let migration = AutoMigration(fileURL: store.fileURL, metaURL: metaURL)
        
        do {
            let didMigrate = try migration.checkAndMigrate(pageStore: store)
            
            if didMigrate {
                BlazeLogger.info("✅ Auto-migration completed: JSON → BlazeBinary")
                
                // Reload layout after migration
                try reloadLayout()
            }
        } catch {
            BlazeLogger.error("❌ Auto-migration failed: \(error)")
            // Don't throw - allow database to continue with mixed format
            // It will work in compatibility mode
        }
    }
    
    /// Reload layout from disk (after migration)
    private func reloadLayout() throws {
        if FileManager.default.fileExists(atPath: metaURL.path) {
            let layout = try StorageLayout.load(from: metaURL)
            // StorageLayout.indexMap is already [UUID: [Int]], no conversion needed
            self.indexMap = layout.indexMap
            self.nextPageIndex = layout.nextPageIndex
            
            // Reload secondary indexes (always present, may be empty)
            self.secondaryIndexes = layout.secondaryIndexes.mapValues { inner in
                inner.mapValues { Set($0) }
            }
            
            // Update cached search index
            self.cachedSearchIndex = layout.searchIndex
            self.cachedSearchIndexedFields = layout.searchIndexedFields
            
            BlazeLogger.debug("Layout reloaded after migration")
        }
    }
}

