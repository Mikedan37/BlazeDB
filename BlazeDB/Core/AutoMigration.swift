//
//  AutoMigration.swift
//  BlazeDB
//
//  Automatic JSON → CBOR migration on database load
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

/// Manages automatic format migration
public final class AutoMigration {
    
    /// Migration status
    public enum Status {
        case notNeeded           // Already CBOR
        case needed              // Needs migration
        case inProgress          // Currently migrating
        case completed           // Migration done
        case failed(Error)       // Migration failed
    }
    
    private let fileURL: URL
    private let metaURL: URL
    private var status: Status = .notNeeded
    private let lock = NSLock()
    
    public init(fileURL: URL, metaURL: URL) {
        self.fileURL = fileURL
        self.metaURL = metaURL
    }
    
    // MARK: - Check & Migrate
    
    /// Check if migration is needed and perform it automatically
    public func checkAndMigrate(pageStore: PageStore) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        BlazeLogger.debug("🔍 AutoMigration.checkAndMigrate() started")
        
        // Check metadata for format version
        let formatVersion = try? readFormatVersion()
        if let format = formatVersion {
            BlazeLogger.debug("🔍 readFormatVersion() returned: \(format == .json ? "json" : "blazeBinary")")
        } else {
            BlazeLogger.debug("🔍 readFormatVersion() returned: nil")
        }
        
        if let formatVersion = formatVersion {
            if formatVersion == .blazeBinary {
                BlazeLogger.info("✅ Database already using BlazeBinary format")
                status = .notNeeded
                return false
            } else if formatVersion == .json {
                BlazeLogger.info("⚠️ Metadata says JSON - will check pages and migrate!")
            }
        }
        
        // Check if any pages are JSON format
        BlazeLogger.debug("🔍 Calling checkPagesNeedMigration()...")
        let needsMigration = try checkPagesNeedMigration(pageStore: pageStore)
        
        BlazeLogger.debug("🔍 AutoMigration: needsMigration = \(needsMigration)")
        
        if !needsMigration {
            // No migration needed, mark as BlazeBinary
            try saveFormatVersion(.blazeBinary)
            status = .notNeeded
            BlazeLogger.info("✅ No migration needed")
            return false
        }
        
        // Perform migration
        BlazeLogger.info("⚠️  STARTING MIGRATION!")
        BlazeLogger.info("🔄 Starting automatic JSON → BlazeBinary migration...")
        status = .inProgress
        
        do {
            try performMigration(pageStore: pageStore)
            try saveFormatVersion(.blazeBinary)
            status = .completed
            BlazeLogger.info("✅ Migration completed successfully!")
            return true
        } catch {
            status = .failed(error)
            BlazeLogger.error("❌ Migration failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Migration Implementation
    
    private func checkPagesNeedMigration(pageStore: PageStore) throws -> Bool {
        // Check encodingFormat in metadata first (faster!)
        if FileManager.default.fileExists(atPath: metaURL.path) {
            let data = try Data(contentsOf: metaURL)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let format = json["encodingFormat"] as? String {
                BlazeLogger.debug("🔍 Metadata encodingFormat: \(format)")
                // If format is "json", migration IS needed
                if format == "json" {
                    BlazeLogger.info("✅ Metadata says 'json' - migration needed!")
                    return true
                }
                // If format is already "blazeBinary", no migration needed
                if format == "blazeBinary" {
                    BlazeLogger.info("✅ Metadata says 'blazeBinary' - no migration needed")
                    return false
                }
            }
        }
        
        // Sample first few pages to detect format
        BlazeLogger.debug("🔍 No encodingFormat in metadata, sampling pages...")
        let samplesToCheck = min(10, pageStore.getTotalPages())
        
        for pageIndex in 0..<samplesToCheck {
            if let pageData = try? pageStore.readPage(index: pageIndex) {
                let isJSON = BlazeEncoder.needsMigration(pageData)
                BlazeLogger.debug("   Page \(pageIndex): \(isJSON ? "JSON" : "BlazeBinary")")
                if isJSON {
                    BlazeLogger.debug("Found JSON page at index \(pageIndex), migration needed")
                    return true
                }
            }
        }
        
        BlazeLogger.info("✅ All sampled pages are BlazeBinary")
        return false
    }
    
    private func performMigration(pageStore: PageStore) throws {
        let totalPages = pageStore.getTotalPages()
        BlazeLogger.info("🔧 MIGRATION: Starting on \(totalPages) pages")
        
        var migratedCount = 0
        var skippedCount = 0
        
        for pageIndex in 0..<totalPages {
            guard let pageData = try? pageStore.readPage(index: pageIndex) else {
                BlazeLogger.warn("   Page \(pageIndex): Failed to read")
                skippedCount += 1
                continue
            }
            
            // Check if this page needs migration
            let needsMigration = BlazeEncoder.needsMigration(pageData)
            let firstByte = pageData.count > 0 ? pageData[0] : 0
            BlazeLogger.debug("   Page \(pageIndex): size=\(pageData.count), firstByte=0x\(String(firstByte, radix: 16)), needsMigration=\(needsMigration)")
            
            if needsMigration {
                // Migrate: JSON → Decode → BlazeBinary
                do {
                    BlazeLogger.debug("      → Calling BlazeEncoder.migrate()...")
                    let migrated = try BlazeEncoder.migrate(
                        pageData,
                        as: BlazeDataRecord.self
                    )
                    
                    BlazeLogger.debug("      ✅ Got migrated data: \(migrated.count) bytes")
                    
                    // Write back as BlazeBinary
                    BlazeLogger.debug("      → Writing back to page \(pageIndex)...")
                    try pageStore.writePage(index: pageIndex, plaintext: migrated)
                    BlazeLogger.debug("      ✅ Written successfully!")
                    
                    migratedCount += 1
                    
                    if migratedCount % 10 == 0 {
                        BlazeLogger.info("      📊 Progress: \(migratedCount)/\(totalPages) pages migrated")
                    }
                } catch {
                    BlazeLogger.error("      ❌ MIGRATION ERROR on page \(pageIndex): \(error)")
                    skippedCount += 1
                }
            } else {
                // Already BlazeBinary, skip
                skippedCount += 1
            }
        }
        
        BlazeLogger.info("📊 MIGRATION COMPLETE: \(migratedCount) migrated, \(skippedCount) skipped out of \(totalPages) total")
        
        // CRITICAL: Flush all writes to disk!
        BlazeLogger.info("🔧 Flushing all migrated pages to disk...")
        do {
            try pageStore.synchronize()
            BlazeLogger.info("✅ Flush complete!")
        } catch {
            BlazeLogger.error("❌ FLUSH FAILED: \(error)")
            throw error
        }
        
        // Verify first page was migrated
        if migratedCount > 0 {
            if let verifyData = try? pageStore.readPage(index: 0) {
                BlazeLogger.debug("🔍 Verification: Page 0 size after migration = \(verifyData.count) bytes")
                if verifyData.count >= 8 {
                    let magic = String(format: "%02X%02X%02X%02X%02X", 
                                      verifyData[0], verifyData[1], verifyData[2], verifyData[3], verifyData[4])
                    BlazeLogger.debug("🔍 Verification: Magic bytes = \(magic) (should be 424C415A45 = 'BLAZE')")
                }
            }
        }
        
        BlazeLogger.info("Migration complete: \(migratedCount) migrated, \(skippedCount) skipped")
    }
    
    // MARK: - Format Version Storage
    
    private func readFormatVersion() throws -> EncodingFormat? {
        guard FileManager.default.fileExists(atPath: metaURL.path) else {
            BlazeLogger.debug("🔍 readFormatVersion: metaURL doesn't exist")
            return nil
        }
        
        // DEBUG: Read raw JSON to see what's actually on disk
        let rawData = try Data(contentsOf: metaURL)
        if let rawJson = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
            BlazeLogger.debug("🔍 readFormatVersion: RAW encodingFormat from disk = \(rawJson["encodingFormat"] ?? "nil")")
        }
        
        // Read format from StorageLayout JSON (not as binary prefix!)
        let layout = try? StorageLayout.load(from: metaURL)
        
        // Check the encodingFormat field (defaults to "blazeBinary")
        if let formatString = layout?.encodingFormat {
            BlazeLogger.debug("🔍 readFormatVersion: StorageLayout.encodingFormat = \(formatString)")
            switch formatString {
            case "json": return .json
            case "blazeBinary": return .blazeBinary
            default: return .blazeBinary
            }
        }
        
        // If no format field, assume old version (JSON)
        BlazeLogger.debug("🔍 readFormatVersion: No encodingFormat in layout")
        return layout == nil ? nil : .json
    }
    
    private func saveFormatVersion(_ format: EncodingFormat) throws {
        // ✅ FIX: Store format INSIDE JSON, not as binary prefix!
        var layout = (try? StorageLayout.load(from: metaURL)) ?? StorageLayout.empty()
        
        // Update the encodingFormat field - always use BlazeBinary (default format)
        layout.encodingFormat = "blazeBinary"
        
        // Save the updated layout
        try layout.save(to: metaURL)
    }
    
    // MARK: - Status
    
    public func getStatus() -> Status {
        lock.lock()
        defer { lock.unlock() }
        return status
    }
}

// MARK: - PageStore Extension

extension PageStore {
    /// Get total number of pages in the store
    func getTotalPages() -> Int {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
            return fileSize / 4096  // Page size
        } catch {
            return 0
        }
    }
}

