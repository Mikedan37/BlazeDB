//
//  AdvancedSearch.swift
//  BlazeDB
//
//  Advanced search features: stemming, fuzzy matching, phrase search, highlighting
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - Advanced Search Config

public struct AdvancedSearchConfig {
    public var enableStemming: Bool = true
    public var enableFuzzy: Bool = false
    public var fuzzyMaxDistance: Int = 2  // Levenshtein distance
    public var enablePhraseSearch: Bool = true
    public var boostFields: [String: Double] = [:]  // field -> boost multiplier
    public var highlightResults: Bool = false
    
    public init() {}
}

// MARK: - Search Result with Highlighting

public struct AdvancedSearchResult {
    public let record: BlazeDataRecord
    public let score: Double
    public let highlights: [String: [String]]  // field -> [highlighted snippets]
    public let matchedTerms: [String]
    
    public init(record: BlazeDataRecord, score: Double, highlights: [String: [String]] = [:], matchedTerms: [String] = []) {
        self.record = record
        self.score = score
        self.highlights = highlights
        self.matchedTerms = matchedTerms
    }
}

// MARK: - Stemmer

/// Simple English stemmer (Porter-like algorithm)
internal struct Stemmer {
    
    /// Stem a word to its root form
    static func stem(_ word: String) -> String {
        var stemmed = word.lowercased()
        
        // Remove common suffixes
        let suffixes = [
            ("ing", ""),
            ("ed", ""),
            ("es", ""),
            ("s", ""),
            ("ly", ""),
            ("ness", ""),
            ("ment", ""),
            ("tion", ""),
            ("ation", "")
        ]
        
        for (suffix, replacement) in suffixes {
            if stemmed.hasSuffix(suffix) && stemmed.count > suffix.count + 2 {
                stemmed = String(stemmed.dropLast(suffix.count)) + replacement
                break
            }
        }
        
        return stemmed
    }
}

// MARK: - Fuzzy Matching

/// Levenshtein distance for fuzzy matching
internal struct FuzzyMatcher {
    
    /// Calculate Levenshtein distance between two strings
    static func distance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)
        
        var dp = Array(repeating: Array(repeating: 0, count: s2.count + 1), count: s1.count + 1)
        
        for i in 0...s1.count {
            dp[i][0] = i
        }
        for j in 0...s2.count {
            dp[0][j] = j
        }
        
        for i in 1...s1.count {
            for j in 1...s2.count {
                if s1[i-1] == s2[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1]) + 1
                }
            }
        }
        
        return dp[s1.count][s2.count]
    }
    
    /// Check if two words are fuzzy matches
    static func matches(_ word1: String, _ word2: String, maxDistance: Int) -> Bool {
        return distance(word1, word2) <= maxDistance
    }
}

// MARK: - Phrase Search

internal struct PhraseSearcher {
    
    /// Check if text contains exact phrase
    static func containsPhrase(_ text: String, phrase: String) -> Bool {
        return text.lowercased().contains(phrase.lowercased())
    }
    
    /// Find all phrase occurrences in text
    static func findPhrases(_ text: String, phrase: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        let lowercaseText = text.lowercased()
        let lowercasePhrase = phrase.lowercased()
        
        while let range = lowercaseText.range(of: lowercasePhrase, range: searchStart..<text.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        
        return ranges
    }
}

// MARK: - Highlighter

internal struct SearchHighlighter {
    
    /// Highlight matching terms in text
    static func highlight(_ text: String, terms: [String], tag: String = "<mark>") -> String {
        var highlighted = text
        let closeTag = "</\(tag.dropFirst()))"
        
        for term in terms {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(highlighted.startIndex..., in: highlighted)
                highlighted = regex.stringByReplacingMatches(
                    in: highlighted,
                    range: range,
                    withTemplate: "\(tag)$0\(closeTag)"
                )
            }
        }
        
        return highlighted
    }
    
    /// Extract snippet around match
    static func snippet(_ text: String, term: String, contextLength: Int = 50) -> String {
        guard let range = text.range(of: term, options: .caseInsensitive) else {
            return String(text.prefix(contextLength))
        }
        
        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let snippetStart = max(0, matchStart - contextLength)
        let snippetEnd = min(text.count, matchStart + term.count + contextLength)
        
        let start = text.index(text.startIndex, offsetBy: snippetStart)
        let end = text.index(text.startIndex, offsetBy: snippetEnd)
        
        var snippet = String(text[start..<end])
        
        if snippetStart > 0 {
            snippet = "..." + snippet
        }
        if snippetEnd < text.count {
            snippet = snippet + "..."
        }
        
        return snippet
    }
}

// MARK: - DynamicCollection Advanced Search Extension

extension DynamicCollection {
    
    /// Advanced search with stemming, fuzzy matching, and highlighting
    ///
    /// - Parameters:
    ///   - query: Search query
    ///   - fields: Fields to search in
    ///   - config: Advanced search configuration
    /// - Returns: Array of advanced search results with scores and highlights
    ///
    /// ## Example
    /// ```swift
    /// var config = AdvancedSearchConfig()
    /// config.enableStemming = true
    /// config.enableFuzzy = true
    /// config.boostFields = ["title": 2.0]  // Title matches count double
    /// config.highlightResults = true
    ///
    /// let results = try db.collection.advancedSearch(
    ///     query: "running quickly",
    ///     in: ["title", "description"],
    ///     config: config
    /// )
    ///
    /// for result in results {
    ///     print("Score: \(result.score)")
    ///     print("Title: \(result.highlights["title"]?.first ?? "")")
    /// }
    /// ```
    public func advancedSearch(
        query: String,
        in fields: [String],
        config: AdvancedSearchConfig = AdvancedSearchConfig()
    ) throws -> [AdvancedSearchResult] {
        BlazeLogger.info("🔍 Advanced search: '\(query)' in \(fields)")
        
        let allRecords = try _fetchAllNoSync()
        var results: [AdvancedSearchResult] = []
        
        // Tokenize query
        let queryTerms = query.components(separatedBy: CharacterSet.whitespaces)
            .filter { !$0.isEmpty }
        
        let stemmedQueryTerms = config.enableStemming ? queryTerms.map { Stemmer.stem($0) } : queryTerms
        
        // Check for phrase search (quoted terms)
        let phraseQuery = query.trimmingCharacters(in: CharacterSet.whitespaces)
        let isPhrase = config.enablePhraseSearch && phraseQuery.hasPrefix("\"") && phraseQuery.hasSuffix("\"")
        let phrase = isPhrase ? String(phraseQuery.dropFirst().dropLast()) : ""
        
        for record in allRecords {
            var score: Double = 0.0
            var highlights: [String: [String]] = [:]
            var matchedTerms: [String] = []
            
            for field in fields {
                guard let fieldValue = record.storage[field]?.stringValue else { continue }
                
                let fieldBoost = config.boostFields[field] ?? 1.0
                
                if isPhrase {
                    // Phrase search
                    if PhraseSearcher.containsPhrase(fieldValue, phrase: phrase) {
                        score += 10.0 * fieldBoost  // Phrase match = high score
                        matchedTerms.append(phrase)
                        
                        if config.highlightResults {
                            let snippet = SearchHighlighter.snippet(fieldValue, term: phrase)
                            highlights[field] = [snippet]
                        }
                    }
                } else {
                    // Term search
                    let textTerms = fieldValue.components(separatedBy: CharacterSet.whitespaces)
                    let stemmedTextTerms = config.enableStemming ? textTerms.map { Stemmer.stem($0) } : textTerms
                    
                    for (index, queryTerm) in stemmedQueryTerms.enumerated() {
                        var found = false
                        
                        // Exact match
                        if stemmedTextTerms.contains(queryTerm) {
                            score += 1.0 * fieldBoost
                            found = true
                            matchedTerms.append(queryTerms[index])
                        }
                        // Fuzzy match
                        else if config.enableFuzzy {
                            for textTerm in stemmedTextTerms {
                                if FuzzyMatcher.matches(queryTerm, textTerm, maxDistance: config.fuzzyMaxDistance) {
                                    score += 0.5 * fieldBoost  // Fuzzy = lower score
                                    found = true
                                    matchedTerms.append(queryTerms[index])
                                    break
                                }
                            }
                        }
                        
                        if found && config.highlightResults {
                            let snippet = SearchHighlighter.snippet(fieldValue, term: queryTerms[index])
                            if highlights[field] == nil {
                                highlights[field] = []
                            }
                            highlights[field]?.append(snippet)
                        }
                    }
                }
            }
            
            if score > 0 {
                results.append(AdvancedSearchResult(
                    record: record,
                    score: score,
                    highlights: highlights,
                    matchedTerms: matchedTerms
                ))
            }
        }
        
        // Sort by score (highest first)
        results.sort { $0.score > $1.score }
        
        BlazeLogger.info("✅ Advanced search found \(results.count) results")
        return results
    }
}

