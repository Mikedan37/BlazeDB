#if BLAZEDB_LINUX_CORE

import Foundation

// Linux-core compatibility surface for search APIs that are index-backed on non-Linux builds.
extension DynamicCollection {
    public func enableSearch(on fields: [String]) throws {
        BlazeLogger.debug("Search index enable requested on Linux core; using scan fallback for query/search APIs")
    }

    public func disableSearch() throws {
        BlazeLogger.debug("Search index disable requested on Linux core")
    }

    public func isSearchEnabled() throws -> Bool {
        false
    }

    public func getSearchStats() throws -> IndexStats? {
        nil
    }

    public func rebuildSearchIndex() throws {
        BlazeLogger.debug("Search index rebuild requested on Linux core; no persisted index to rebuild")
    }

    public func searchOptimized(
        query: String,
        in fields: [String],
        config: SearchConfig? = nil
    ) throws -> [FullTextSearchResult] {
        try queue.sync {
            let allRecords = try _fetchAllNoSync()
            let searchConfig = config ?? SearchConfig(fields: fields)
            return FullTextSearchEngine.search(records: allRecords, query: query, config: searchConfig)
        }
    }

    public func enableSmartSearch(threshold: Int, fields: [String]) throws {
        BlazeLogger.debug("Smart search requested on Linux core; scan fallback remains active")
    }

    internal func checkAutoIndexThreshold() throws {
        // No-op on Linux core where index-backed search is unavailable.
    }
}

#endif
