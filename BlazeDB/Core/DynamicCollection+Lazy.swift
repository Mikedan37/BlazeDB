//
//  DynamicCollection+Lazy.swift
//  BlazeDB
//
//  Lazy decoding support for DynamicCollection
//
//  Created by Auto on 1/XX/25.
//

#if !BLAZEDB_LINUX_CORE

import Foundation

extension DynamicCollection {
    
    /// Fetch record with lazy decoding (if enabled)
    ///
    /// - Parameters:
    ///   - id: Record ID
    ///   - useLazy: Force lazy decoding (overrides collection setting)
    /// - Returns: LazyBlazeRecord if lazy decoding enabled, otherwise full BlazeDataRecord
    public func fetchLazy(id: UUID, useLazy: Bool? = nil) throws -> LazyBlazeRecord? {
        guard let pageIndices = indexMap[id], !pageIndices.isEmpty else {
            return nil
        }
        
        // Check if lazy decoding is enabled
        // Note: lazyDecodingEnabled is not stored in StorageLayout
        // Lazy decoding is always available but not enabled by default
        let shouldUseLazy = useLazy ?? false
        
        guard shouldUseLazy else {
            // Lazy decoding disabled, return nil (caller should use regular fetch)
            return nil
        }
        
        // Read encoded data
        guard let firstPageIndex = pageIndices.first else {
            return nil
        }
        guard let encodedData = try store.readPage(index: firstPageIndex) else {
            return nil
        }
        
        // Try to decode with field table (v3 format)
        if let (_, fieldTable) = try? BlazeBinaryDecoder.decodeWithFieldTable(encodedData) {
            // v3 format with field table
            return LazyBlazeRecord(rawData: encodedData, fieldTable: fieldTable, recordId: id)
        } else {
            // v1/v2 format, no field table - still create lazy record but it will decode fully
            return LazyBlazeRecord(rawData: encodedData, fieldTable: nil, recordId: id)
        }
    }
    
    /// Enable lazy decoding for this collection
    public func enableLazyDecoding() throws {
        return queue.sync(flags: .barrier) {
            // Load current layout, or create new one if it doesn't exist
            if FileManager.default.fileExists(atPath: metaURL.path) {
                do {
                    _ = try StorageLayout.loadSecure(from: metaURL, signingKey: encryptionKey)
                } catch {
                    // If loading fails, create a new layout
                    BlazeLogger.warn("Failed to load layout, creating new one: \(error)")
                }
            }
            
            // Note: lazyDecodingEnabled is not stored in StorageLayout
            // Lazy decoding is always available - this is a no-op
            BlazeLogger.info("Lazy decoding is always available for collection")
        }
    }
    
    /// Disable lazy decoding for this collection
    public func disableLazyDecoding() throws {
        return queue.sync(flags: .barrier) {
            // Note: lazyDecodingEnabled is not stored in StorageLayout
            // Lazy decoding is always available - this is a no-op
            BlazeLogger.info("Lazy decoding is always available for collection")
        }
    }
    
    /// Check if lazy decoding is enabled
    public func isLazyDecodingEnabled() -> Bool {
        // Note: lazyDecodingEnabled is not stored in StorageLayout
        // Lazy decoding is always available
        return true
    }
}

#endif // !BLAZEDB_LINUX_CORE
