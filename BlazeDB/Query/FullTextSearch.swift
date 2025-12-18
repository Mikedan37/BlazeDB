//  FullTextSearch.swift
//  BlazeDB
//  Created by Michael Danylchuk on 1/7/25.

import Foundation

// MARK: - Full-Text Search

/// Full-text search configuration
public struct SearchConfig {
    /// Minimum word length to index
    public let minWordLength: Int
    
    /// Case sensitive search
    public let caseSensitive: Bool
    
    /// Language for stemming (future feature)
    public let language: String?
    
    /// Fields to search
    public let fields: [String]
    
    public init(
        minWordLength: Int = 2,
        caseSensitive: Bool = false,
        language: String? = nil,
        fields: [String]
    ) {
        self.minWordLength = minWordLength
        self.caseSensitive = caseSensitive
        self.language = language
        self.fields = fields
    }
}

/// Search result with relevance score
public struct FullTextSearchResult: Comparable, Equatable {
    public let record: BlazeDataRecord
    public let score: Double
    public let matches: [String: [String]]  // field → matched terms
    
    public static func < (lhs: FullTextSearchResult, rhs: FullTextSearchResult) -> Bool {
        return lhs.score < rhs.score
    }
    
    public static func == (lhs: FullTextSearchResult, rhs: FullTextSearchResult) -> Bool {
        return lhs.score == rhs.score &&
               lhs.record.storage["id"] == rhs.record.storage["id"]
    }
}

/// Legacy type alias for backward compatibility
public typealias SearchResult = FullTextSearchResult

/// Full-text search engine
public struct FullTextSearchEngine {
    
    /// Tokenize text into searchable words
    public static func tokenize(_ text: String, config: SearchConfig) -> [String] {
        let normalizedText = config.caseSensitive ? text : text.lowercased()
        
        // Split on whitespace and punctuation
        let words = normalizedText.components(separatedBy: CharacterSet.alphanumerics.inverted)
        
        // Filter by minimum length
        return words.filter { $0.count >= config.minWordLength }
    }
    
    /// Search records with relevance scoring
    public static func search(
        records: [BlazeDataRecord],
        query: String,
        config: SearchConfig
    ) -> [FullTextSearchResult] {
        let queryTerms = tokenize(query, config: config)
        guard !queryTerms.isEmpty else { return [] }
        
        BlazeLogger.debug("Full-text search for '\(query)' (\(queryTerms.count) terms) across \(config.fields.count) fields")
        
        var results: [SearchResult] = []
        
        for record in records {
            var score = 0.0
            var matches: [String: [String]] = [:]
            var matchedTerms = Set<String>()  // Track unique matched terms across all fields
            
            // Search each configured field
            for field in config.fields {
                guard let fieldValue = record.storage[field]?.stringValue else { continue }
                
                let fieldTokens = tokenize(fieldValue, config: config)
                var fieldMatches: [String] = []
                
                // Check each query term
                for queryTerm in queryTerms {
                    // Exact match - count term frequency (TF)
                    let exactMatches = fieldTokens.filter { $0 == queryTerm }.count
                    if exactMatches > 0 {
                        score += 10.0 * Double(exactMatches)  // 10 points per occurrence
                        fieldMatches.append(queryTerm)
                        matchedTerms.insert(queryTerm)  // Track this term was found
                    }
                    // Partial match (contains) - count occurrences
                    else {
                        let partialMatches = fieldTokens.filter { $0.contains(queryTerm) }.count
                        if partialMatches > 0 {
                            score += 5.0 * Double(partialMatches)  // 5 points per partial match
                            fieldMatches.append(queryTerm)
                            matchedTerms.insert(queryTerm)  // Track this term was found
                        }
                        // Fuzzy match (field contains term) - respect case sensitivity
                        else {
                            let fuzzyMatch = config.caseSensitive 
                                ? fieldValue.contains(queryTerm)
                                : fieldValue.localizedCaseInsensitiveContains(queryTerm)
                            
                            if fuzzyMatch {
                                score += 2.0  // Low score for fuzzy match
                                fieldMatches.append(queryTerm)
                                matchedTerms.insert(queryTerm)  // Track this term was found
                            }
                        }
                    }
                }
                
                if !fieldMatches.isEmpty {
                    matches[field] = fieldMatches
                }
            }
            
            // Boost score for title matches (if searching title field)
            if config.fields.contains("title") && !(matches["title"]?.isEmpty ?? true) {
                score *= 1.5  // 50% boost for title matches
            }
            
            // AND logic: Only include record if ALL query terms were matched
            if score > 0 && matchedTerms.count == queryTerms.count {
                results.append(FullTextSearchResult(record: record, score: score, matches: matches))
            }
        }
        
        // Sort by relevance (highest score first)
        results.sort(by: >)
        
        BlazeLogger.info("Full-text search found \(results.count) matches from \(records.count) records")
        
        return results
    }
    
    /// Simple text search (convenience)
    static func simpleSearch(
        records: [BlazeDataRecord],
        query: String,
        fields: [String]
    ) -> [BlazeDataRecord] {
        let config = SearchConfig(fields: fields)
        let results = search(records: records, query: query, config: config)
        return results.map { $0.record }
    }
}

// MARK: - QueryBuilder Extension

extension QueryBuilder {
    /// Perform full-text search across specified fields
    ///
    /// Automatically uses inverted index if enabled (50-1000x faster!).
    /// Falls back to full scan if index not available.
    ///
    /// To enable index for ultra-fast search:
    /// ```swift
    /// try db.collection.enableSearch(on: ["title", "description"])
    /// ```
    ///
    /// - Parameters:
    ///   - query: Search query string
    ///   - fields: Fields to search in
    ///   - config: Search configuration (optional)
    /// - Returns: Array of SearchResult with relevance scores
    public func search(
        _ query: String,
        in fields: [String],
        config: SearchConfig? = nil
    ) throws -> [SearchResult] {
        guard let collection = collection else {
            BlazeLogger.error("Search failed: Collection has been deallocated")
            throw BlazeDBError.transactionFailed("Collection has been deallocated")
        }
        
        let startTime = Date()
        let searchConfig = config ?? SearchConfig(fields: fields)
        BlazeLogger.info("Executing full-text search: '\(query)' in fields [\(fields.joined(separator: ", "))] (caseSensitive: \(searchConfig.caseSensitive))")
        
        // TRY OPTIMIZED SEARCH FIRST (inverted index)
        // This is 50-1000x faster if index is enabled!
        // searchOptimized() will automatically fall back to manual search if caseSensitive is true
        #if !BLAZEDB_LINUX_CORE
        var results = try collection.searchOptimized(query: query, in: fields, config: searchConfig)
        #else
        var results: [FullTextSearchResult] = []
        // Fallback to manual search on Linux
        let allRecords = try collection.fetchAll()
        for record in allRecords {
            for field in fields {
                if let value = record.storage[field]?.stringValue {
                    let searchValue = searchConfig.caseSensitive ? value : value.lowercased()
                    let searchQuery = searchConfig.caseSensitive ? query : query.lowercased()
                    if searchValue.contains(searchQuery) {
                        // Create a simple search result with score 1.0
                        let result = FullTextSearchResult(
                            record: record,
                            score: 1.0,
                            matches: [field: [query]]
                        )
                        results.append(result)
                        break
                    }
                }
            }
        }
        #endif
        
        // Apply WHERE filters (if any)
        if !filters.isEmpty {
            let combinedFilter: (BlazeDataRecord) -> Bool = { record in
                for filter in self.filters {
                    if !filter(record) { return false }
                }
                return true
            }
            results = results.filter { combinedFilter($0.record) }
        }
        
        // Apply limit/offset
        if offsetValue > 0 {
            results = Array(results.dropFirst(Swift.min(offsetValue, results.count)))
        }
        
        if let limit = limitValue {
            results = Array(results.prefix(Swift.max(0, limit)))
        }
        
        let duration = Date().timeIntervalSince(startTime)
        BlazeLogger.info("Search complete: \(results.count) results in \(String(format: "%.2f", duration * 1000))ms")
        
        return results
    }
    
    /// Simple text search (returns records, not SearchResult)
    public func searchSimple(
        _ query: String,
        in fields: [String]
    ) throws -> [BlazeDataRecord] {
        let results = try search(query, in: fields, config: nil)
        return results.map { $0.record }
    }
}

