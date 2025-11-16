//
//  InvertedIndex.swift
//  BlazeDB
//
//  Memory-efficient inverted index for full-text search.
//  Provides 50-1000x faster search by indexing words → record IDs.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import Foundation

/// Memory-efficient inverted index for full-text search
///
/// Maps words to the record IDs that contain them, enabling sub-millisecond searches.
///
/// Features:
/// - O(1) word lookup (hash-based)
/// - O(k) result fetching where k = matches (not O(n) full scan!)
/// - Automatic index maintenance on insert/update/delete
/// - Persistent storage
/// - Field-specific indexes
/// - Memory: ~0.5-1% of database size
///
/// Example:
/// ```swift
/// // Enable search indexing
/// try db.collection.enableSearch(on: ["title", "description"])
///
/// // Searches now 50-1000x faster!
/// let result = try await db.query()
///     .search("login bug", in: ["title"])
///     .execute()
/// ```
public final class InvertedIndex: Codable {
    
    // MARK: - Storage
    
    /// Global index: word → record IDs
    private var globalIndex: [String: Set<UUID>] = [:]
    
    /// Field-specific indexes: field → (word → record IDs)
    private var fieldIndexes: [String: [String: Set<UUID>]] = [:]
    
    /// Indexed fields
    private var indexedFields: Set<String> = []
    
    /// Statistics
    private var stats: IndexStats
    
    /// Thread safety
    private let queue: DispatchQueue
    
    // MARK: - Initialization
    
    public init() {
        self.stats = IndexStats(
            totalWords: 0,
            totalMappings: 0,
            totalRecords: 0,
            memoryUsage: 0
        )
        self.queue = DispatchQueue(label: "com.blazedb.invertedindex", attributes: .concurrent)
    }
    
    // MARK: - Indexing Operations
    
    /// Index a single record
    public func indexRecord(_ record: BlazeDataRecord, fields: [String]) {
        queue.sync(flags: .barrier) {
            guard let id = record.storage["id"]?.uuidValue else {
                BlazeLogger.warn("Cannot index record without UUID id")
                return
            }
            
            BlazeLogger.trace("Indexing record \(id) for fields: \(fields)")
            
            for field in fields {
                guard let text = record.storage[field]?.stringValue else {
                    continue
                }
                
                // Tokenize
                let tokens = self.tokenize(text)
                
                // Add to field-specific index
                var fieldIndex = self.fieldIndexes[field] ?? [:]
                for token in tokens {
                    var ids = fieldIndex[token] ?? Set()
                    ids.insert(id)
                    fieldIndex[token] = ids
                }
                self.fieldIndexes[field] = fieldIndex
                
                // Add to global index
                for token in tokens {
                    var ids = self.globalIndex[token] ?? Set()
                    ids.insert(id)
                    self.globalIndex[token] = ids
                }
                
                // Track indexed field
                self.indexedFields.insert(field)
            }
            
            // Update stats
            self.updateStats()
        }
    }
    
    /// Index multiple records (batch operation)
    public func indexRecords(_ records: [BlazeDataRecord], fields: [String]) {
        BlazeLogger.info("Batch indexing \(records.count) records for fields: \(fields)")
        let startTime = Date()
        
        // Use sync instead of async to ensure indexing completes before returning
        queue.sync(flags: .barrier) {
            for record in records {
                guard let id = record.storage["id"]?.uuidValue else { continue }
                
                for field in fields {
                    guard let text = record.storage[field]?.stringValue else { continue }
                    
                    let tokens = self.tokenize(text)
                    
                    // Add to field index
                    var fieldIndex = self.fieldIndexes[field] ?? [:]
                    for token in tokens {
                        var ids = fieldIndex[token] ?? Set()
                        ids.insert(id)
                        fieldIndex[token] = ids
                    }
                    self.fieldIndexes[field] = fieldIndex
                    
                    // Add to global index
                    for token in tokens {
                        var ids = self.globalIndex[token] ?? Set()
                        ids.insert(id)
                        self.globalIndex[token] = ids
                    }
                }
                
                self.indexedFields.formUnion(fields)
            }
            
            self.updateStats()
            
            let duration = Date().timeIntervalSince(startTime)
            BlazeLogger.info("Batch index complete: \(records.count) records in \(String(format: "%.2f", duration * 1000))ms")
        }
    }
    
    /// Remove record from index
    public func removeRecord(_ id: UUID) {
        queue.sync(flags: .barrier) {
            BlazeLogger.trace("Removing record \(id) from search index")
            
            // Remove from global index
            for (word, var ids) in self.globalIndex {
                if ids.remove(id) != nil {
                    if ids.isEmpty {
                        self.globalIndex.removeValue(forKey: word)
                    } else {
                        self.globalIndex[word] = ids
                    }
                }
            }
            
            // Remove from field indexes
            for (field, var fieldIndex) in self.fieldIndexes {
                for (word, var ids) in fieldIndex {
                    if ids.remove(id) != nil {
                        if ids.isEmpty {
                            fieldIndex.removeValue(forKey: word)
                        } else {
                            fieldIndex[word] = ids
                        }
                    }
                }
                self.fieldIndexes[field] = fieldIndex
            }
            
            self.updateStats()
        }
    }
    
    /// Update index for a record (remove old + add new)
    public func updateRecord(_ record: BlazeDataRecord, fields: [String]) {
        guard let id = record.storage["id"]?.uuidValue else { return }
        
        // Remove old
        removeRecord(id)
        
        // Re-index
        indexRecord(record, fields: fields)
    }
    
    // MARK: - Search Operations
    
    /// Search for records matching query terms
    /// Returns record IDs with relevance scores, sorted by score (highest first)
    public func search(query: String, in fields: [String]) -> [(id: UUID, score: Double)] {
        let queryTerms = tokenize(query)
        guard !queryTerms.isEmpty else { return [] }
        
        return queue.sync {
            BlazeLogger.debug("Inverted index search: '\(query)' (\(queryTerms.count) terms) in fields [\(fields.joined(separator: ", "))]")
            
            var scores: [UUID: Double] = [:]
            
            // For each search term
            for term in queryTerms {
                // Search in each field
                for field in fields {
                    guard let fieldIndex = self.fieldIndexes[field],
                          let ids = fieldIndex[term] else {
                        continue
                    }
                    
                    // Add base score for each matching record
                    for id in ids {
                        scores[id, default: 0] += 10.0  // Exact word match
                        
                        // Field-specific boosting
                        if field == "title" {
                            scores[id, default: 0] += 5.0  // Title boost
                        } else if field == "description" {
                            scores[id, default: 0] += 3.0  // Description boost
                        }
                    }
                }
            }
            
            // AND logic: Filter to ONLY records matching ALL terms
            let recordsMatchingAllTerms = scores.filter { (id, score) in
                // Count how many terms this record matched
                var matchedTerms = 0
                for term in queryTerms {
                    // Check if record matched this term in any field
                    var foundTerm = false
                    for field in fields {
                        if let fieldIndex = self.fieldIndexes[field],
                           let ids = fieldIndex[term],
                           ids.contains(id) {
                            foundTerm = true
                            break
                        }
                    }
                    if foundTerm {
                        matchedTerms += 1
                    }
                }
                return matchedTerms == queryTerms.count
            }
            
            // Boost title matches in the filtered set
            var finalScores = recordsMatchingAllTerms
            for id in finalScores.keys {
                // Check if match was in title field
                var hasTitle = false
                for term in queryTerms {
                    if let titleIndex = self.fieldIndexes["title"],
                       let ids = titleIndex[term],
                       ids.contains(id) {
                        hasTitle = true
                        break
                    }
                }
                if hasTitle {
                    finalScores[id, default: 0] *= 1.5  // 50% boost for title matches
                }
            }
            
            // Sort by score (highest first)
            let sorted = finalScores.map { ($0.key, $0.value) }
                .sorted { $0.1 > $1.1 }
            
            BlazeLogger.info("Index search found \(sorted.count) matches for '\(query)'")
            
            return sorted
        }
    }
    
    /// Check if a field is indexed
    public func isFieldIndexed(_ field: String) -> Bool {
        return queue.sync { indexedFields.contains(field) }
    }
    
    // MARK: - Tokenization
    
    private func tokenize(_ text: String) -> [String] {
        // Normalize: lowercase, split on non-alphanumeric
        let normalized = text.lowercased()
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
        
        // Filter: minimum 2 characters, remove numbers-only
        return words.filter { word in
            word.count >= 2 && !word.allSatisfy { $0.isNumber }
        }
    }
    
    // MARK: - Statistics
    
    private func updateStats() {
        var totalMappings = 0
        for ids in globalIndex.values {
            totalMappings += ids.count
        }
        
        // Estimate memory
        let memoryUsage = estimateMemory()
        
        stats = IndexStats(
            totalWords: globalIndex.count,
            totalMappings: totalMappings,
            totalRecords: Set(globalIndex.values.flatMap { $0 }).count,
            memoryUsage: memoryUsage
        )
    }
    
    public func getStats() -> IndexStats {
        return queue.sync {
            updateStats()
            return stats
        }
    }
    
    private func estimateMemory() -> Int {
        var bytes = 0
        
        // Global index
        for (word, ids) in globalIndex {
            bytes += word.utf8.count + 8  // String + pointer
            bytes += ids.count * 24  // 16 bytes UUID + 8 bytes overhead
        }
        
        // Field indexes
        for (field, fieldIndex) in fieldIndexes {
            bytes += field.utf8.count + 8
            for (word, ids) in fieldIndex {
                bytes += word.utf8.count + 8
                bytes += ids.count * 24
            }
        }
        
        return bytes
    }
    
    /// Clear entire index
    public func clear() {
        queue.sync(flags: .barrier) {
            self.globalIndex.removeAll()
            self.fieldIndexes.removeAll()
            self.indexedFields.removeAll()
            self.updateStats()
            BlazeLogger.debug("Search index cleared")
        }
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case globalIndex
        case fieldIndexes
        case indexedFields
        case stats
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Convert Set<UUID> to [String] for encoding
        // Force evaluation of mapValues to create a real Dictionary
        let globalEncoded: [String: [String]] = Dictionary(uniqueKeysWithValues: globalIndex.map { (key, ids) in
            (key, ids.map { $0.uuidString })
        })
        try container.encode(globalEncoded, forKey: .globalIndex)
        
        // Convert field indexes
        // Force evaluation to create a real Dictionary
        let fieldEncoded: [String: [String: [String]]] = Dictionary(uniqueKeysWithValues: fieldIndexes.map { (fieldKey, wordIndex) in
            let innerDict: [String: [String]] = Dictionary(uniqueKeysWithValues: wordIndex.map { (word, ids) in
                (word, ids.map { $0.uuidString })
            })
            return (fieldKey, innerDict)
        })
        try container.encode(fieldEncoded, forKey: .fieldIndexes)
        
        try container.encode(Array(indexedFields), forKey: .indexedFields)
        try container.encode(stats, forKey: .stats)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode global index
        let globalEncoded = try container.decode([String: [String]].self, forKey: .globalIndex)
        self.globalIndex = globalEncoded.mapValues { uuidStrings in
            Set(uuidStrings.compactMap { UUID(uuidString: $0) })
        }
        
        // Decode field indexes
        let fieldEncoded = try container.decode([String: [String: [String]]].self, forKey: .fieldIndexes)
        self.fieldIndexes = fieldEncoded.mapValues { wordIndex in
            wordIndex.mapValues { uuidStrings in
                Set(uuidStrings.compactMap { UUID(uuidString: $0) })
            }
        }
        
        let fieldsArray = try container.decode([String].self, forKey: .indexedFields)
        self.indexedFields = Set(fieldsArray)
        
        self.stats = try container.decode(IndexStats.self, forKey: .stats)
        
        self.queue = DispatchQueue(label: "com.blazedb.invertedindex", attributes: .concurrent)
    }
}

// MARK: - Statistics

public struct IndexStats: Codable, Equatable {
    public let totalWords: Int
    public let totalMappings: Int
    public let totalRecords: Int
    public let memoryUsage: Int
    
    public var description: String {
        let memoryMB = Double(memoryUsage) / 1024 / 1024
        return """
        Inverted Index Stats:
          Unique words: \(totalWords)
          Total mappings: \(totalMappings)
          Indexed records: \(totalRecords)
          Memory: \(String(format: "%.2f", memoryMB)) MB (\(memoryUsage / 1024) KB)
        """
    }
}

