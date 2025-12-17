//
//  DynamicCollection+Search.swift
//  BlazeDB
//
//  Full-text search integration for DynamicCollection.
//  Provides 50-1000x faster search via inverted indexing.
//
//  Created by Michael Danylchuk on 7/1/25.
//

#if !BLAZEDB_LINUX_CORE

import Foundation

// MARK: - Search Index Management

extension DynamicCollection {
    
    /// Enable full-text search indexing on specified fields
    ///
    /// Once enabled, search operations on these fields will be 50-1000x faster.
    /// The index is automatically maintained on insert/update/delete.
    ///
    /// Memory overhead: ~0.5-1% of database size
    ///
    /// Example:
    /// ```swift
    /// try db.collection.enableSearch(on: ["title", "description", "content"])
    ///
    /// // Searches now use inverted index (ultra-fast!)
    /// let result = try await db.query()
    ///     .search("login bug", in: ["title"])
    ///     .execute()
    /// ```
    ///
    /// - Parameter fields: Fields to index for full-text search
    /// - Throws: If indexing fails
    public func enableSearch(on fields: [String]) throws {
        try queue.sync(flags: .barrier) {
            BlazeLogger.info("Enabling search index on fields: \(fields)")
            let startTime = Date()
            
            // Load existing index or create new one
            let layout = try StorageLayout.load(from: metaURL)
            let searchIndex = layout.searchIndex ?? InvertedIndex()
            
            // Build index from all existing records
            let allRecords = try _fetchAllNoSync()
            searchIndex.indexRecords(allRecords, fields: fields)
            
            // Save to layout
            var updatedLayout = layout
            updatedLayout.searchIndex = searchIndex
            updatedLayout.searchIndexedFields = fields
            try updatedLayout.save(to: metaURL)
            
            let duration = Date().timeIntervalSince(startTime)
            let stats = searchIndex.getStats()
            BlazeLogger.info("""
                Search index enabled in \(String(format: "%.2f", duration))s
                \(stats.description)
                """)
        }
    }
    
    /// Disable search indexing (frees memory)
    public func disableSearch() throws {
        try queue.sync(flags: .barrier) {
            BlazeLogger.info("Disabling search index")
            
            var layout = try StorageLayout.load(from: metaURL)
            layout.searchIndex = nil
            layout.searchIndexedFields = []
            try layout.save(to: metaURL)
            
            BlazeLogger.info("Search index disabled, memory freed")
        }
    }
    
    /// Check if search is enabled
    public func isSearchEnabled() throws -> Bool {
        return try queue.sync {
            let layout = try StorageLayout.load(from: metaURL)
            return layout.searchIndex != nil
        }
    }
    
    /// Get search index statistics
    public func getSearchStats() throws -> IndexStats? {
        return try queue.sync {
            let layout = try StorageLayout.load(from: metaURL)
            return layout.searchIndex?.getStats()
        }
    }
    
    /// Rebuild search index (useful after bulk updates)
    public func rebuildSearchIndex() throws {
        try queue.sync(flags: .barrier) {
            BlazeLogger.info("Rebuilding search index")
            let startTime = Date()
            
            var layout = try StorageLayout.load(from: metaURL)
            guard !layout.searchIndexedFields.isEmpty else {
                BlazeLogger.warn("No indexed fields configured, skipping rebuild")
                return
            }
            
            // Clear and rebuild
            let newIndex = InvertedIndex()
            let allRecords = try _fetchAllNoSync()
            newIndex.indexRecords(allRecords, fields: layout.searchIndexedFields)
            
            layout.searchIndex = newIndex
            try layout.save(to: metaURL)
            
            let duration = Date().timeIntervalSince(startTime)
            BlazeLogger.info("Search index rebuilt in \(String(format: "%.2f", duration))s")
        }
    }
    
    // MARK: - Internal Search Operations
    
    /// Internal: Update search index after insert (optimized - in-memory only)
    ///
    /// The search index is updated in-memory and will be persisted
    /// when the main metadata is flushed (batched writes for performance).
    internal func updateSearchIndexOnInsert(_ record: BlazeDataRecord) throws {
        // Use cached search index instead of loading from disk!
        guard let index = cachedSearchIndex, !cachedSearchIndexedFields.isEmpty else {
            return // Search not enabled
        }
        
        // Update index in-memory (no disk I/O!)
        index.indexRecord(record, fields: cachedSearchIndexedFields)
        // The cached index will be saved when saveLayout() is called
    }
    
    /// Internal: Update search index after update (optimized)
    internal func updateSearchIndexOnUpdate(_ record: BlazeDataRecord) throws {
        // Use cached search index
        guard let index = cachedSearchIndex, !cachedSearchIndexedFields.isEmpty else {
            return // Search not enabled
        }
        
        // Update index in-memory (no disk I/O!)
        index.updateRecord(record, fields: cachedSearchIndexedFields)
        // The cached index will be saved when saveLayout() is called
    }
    
    /// Internal: Update search index after delete (optimized)
    internal func updateSearchIndexOnDelete(_ id: UUID) throws {
        // Use cached search index
        guard let index = cachedSearchIndex else {
            return // Search not enabled
        }
        
        // Remove from index in-memory (no disk I/O!)
        index.removeRecord(id)
        // The cached index will be saved when saveLayout() is called
    }
    
    // MARK: - Optimized Search Execution
    
    /// Perform optimized full-text search using inverted index
    ///
    /// Automatically uses inverted index if available (50-1000x faster!),
    /// falls back to full scan if index not enabled.
    ///
    /// - Parameters:
    ///   - query: Search query string
    ///   - fields: Fields to search in
    /// - Returns: Array of FullTextSearchResult with relevance scores
    /// - Throws: If search fails
    public func searchOptimized(query: String, in fields: [String], config: SearchConfig? = nil) throws -> [FullTextSearchResult] {
        return try queue.sync {
            let layout = try StorageLayout.load(from: metaURL)
            let searchConfig = config ?? SearchConfig(fields: fields)
            
            // Check if index is available AND case-insensitive mode
            // InvertedIndex always lowercases, so we can't use it for case-sensitive search
            guard let index = layout.searchIndex, !searchConfig.caseSensitive else {
                // Fallback to non-indexed search
                if layout.searchIndex == nil {
                    BlazeLogger.warn("Search index not enabled for this collection, using full scan (slower)")
                    BlazeLogger.info("Tip: Enable index with enableSearch(on: fields) for 50-1000x speedup")
                } else {
                    BlazeLogger.debug("Using full scan for case-sensitive search")
                }
                
                let allRecords = try _fetchAllNoSync()
                return FullTextSearchEngine.search(
                    records: allRecords,
                    query: query,
                    config: searchConfig
                )
            }
            
            let startTime = Date()
            BlazeLogger.debug("Using inverted index for search: '\(query)'")
            
            // Use inverted index (fast!)
            let scoredIDs = index.search(query: query, in: fields)
            
            // Fetch only matching records
            var results: [FullTextSearchResult] = []
            for (id, score) in scoredIDs {
                if let record = try? _fetchNoSync(id: id) {
                    // Extract actual matches for display
                    var matches: [String: [String]] = [:]
                    for field in fields {
                        if let text = record.storage[field]?.stringValue,
                           text.localizedCaseInsensitiveContains(query) {
                            matches[field] = [query]
                        }
                    }
                    
                    results.append(FullTextSearchResult(
                        record: record,
                        score: score,
                        matches: matches
                    ))
                }
            }
            
            let duration = Date().timeIntervalSince(startTime)
            BlazeLogger.info("Indexed search: \(results.count) results in \(String(format: "%.2f", duration * 1000))ms")
            
            return results
        }
    }
    
    // MARK: - Smart Auto-Indexing
    
    /// Enable smart auto-indexing
    ///
    /// Automatically enables search indexing when record count exceeds threshold.
    /// Perfect for databases that start small but grow over time.
    ///
    /// Example:
    /// ```swift
    /// try db.collection.enableSmartSearch(
    ///     threshold: 5000,
    ///     fields: ["title", "description"]
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - threshold: Record count threshold to trigger auto-indexing
    ///   - fields: Fields to index
    public func enableSmartSearch(threshold: Int, fields: [String]) throws {
        BlazeLogger.info("Smart search enabled: will auto-index when count > \(threshold)")
        
        let recordCount = try queue.sync {
            return indexMap.count
        }
        
        if recordCount >= threshold {
            BlazeLogger.info("Record count (\(recordCount)) >= threshold (\(threshold)), enabling search now")
            try enableSearch(on: fields)
        } else {
            BlazeLogger.info("Record count (\(recordCount)) < threshold (\(threshold)), will enable later")
            // Store threshold in metadata for future checks
            var layout = try StorageLayout.load(from: metaURL)
            layout.metaData["_searchAutoThreshold"] = .int(threshold)
            layout.metaData["_searchAutoFields"] = .array(fields.map { .string($0) })
            try layout.save(to: metaURL)
        }
    }
    
    /// Internal: Check if auto-indexing threshold has been reached
    internal func checkAutoIndexThreshold() throws {
        let layout = try StorageLayout.load(from: metaURL)
        
        // Check if auto-indexing is configured
        guard let thresholdField = layout.metaData["_searchAutoThreshold"],
              case .int(let threshold) = thresholdField,
              let fieldsField = layout.metaData["_searchAutoFields"],
              case .array(let fieldValues) = fieldsField else {
            return // Auto-indexing not configured
        }
        
        // Already indexed?
        if layout.searchIndex != nil {
            return
        }
        
        // Check if threshold reached
        let recordCount = indexMap.count
        if recordCount >= threshold {
            let fields = fieldValues.compactMap { field -> String? in
                if case .string(let str) = field { return str }
                return nil
            }
            
            BlazeLogger.info("Auto-index threshold reached (\(recordCount) >= \(threshold)), enabling search index")
            try enableSearch(on: fields)
        }
    }
}

// MARK: - Private Helpers

// NOTE: _fetchAllNoSync() and _fetchNoSync() are now in DynamicCollection.swift (main file)
// to avoid duplication across multiple extensions

#endif // !BLAZEDB_LINUX_CORE
