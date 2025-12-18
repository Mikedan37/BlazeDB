//
//  LikePattern.swift
//  BlazeDB
//
//  LIKE and ILIKE pattern matching with wildcards
//  Optimized with compiled regex patterns and caching
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Pattern Matching

public enum PatternMatchType {
    case like        // Case-sensitive
    case ilike       // Case-insensitive
}

// MARK: - Pattern Cache (Performance Optimization)

private class PatternCache {
    private var cache: [String: NSRegularExpression] = [:]
    private let lock = NSLock()
    
    func getPattern(_ sqlPattern: String, caseSensitive: Bool) throws -> NSRegularExpression {
        let cacheKey = "\(caseSensitive ? "like" : "ilike"):\(sqlPattern)"
        
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = cache[cacheKey] {
            return cached
        }
        
        // Convert SQL LIKE pattern to regex
        let regexPattern = convertSQLPatternToRegex(sqlPattern)
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        
        let regex = try NSRegularExpression(pattern: regexPattern, options: options)
        cache[cacheKey] = regex
        
        return regex
    }
    
    private func convertSQLPatternToRegex(_ sqlPattern: String) -> String {
        var regex = "^"
        
        for char in sqlPattern {
            switch char {
            case "%":
                regex += ".*"  // Zero or more characters
            case "_":
                regex += "."   // Single character
            case "\\":
                // Escape next character
                continue
            default:
                // Escape special regex characters
                if ".*+?^${}[]|()".contains(char) {
                    regex += "\\"
                }
                regex += String(char)
            }
        }
        
        regex += "$"
        return regex
    }
}

nonisolated(unsafe) private let patternCache = PatternCache()

// MARK: - QueryBuilder LIKE Extension

extension QueryBuilder {
    
    /// WHERE field LIKE pattern (case-sensitive)
    @discardableResult
    public func `where`(_ field: String, like pattern: String) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) LIKE '\(pattern)'")
        filters.append { record in
            guard let fieldValue = record.storage[field]?.stringValue else {
                return false
            }
            
            do {
                let regex = try patternCache.getPattern(pattern, caseSensitive: true)
                let range = NSRange(location: 0, length: fieldValue.utf16.count)
                return regex.firstMatch(in: fieldValue, range: range) != nil
            } catch {
                BlazeLogger.warn("Invalid LIKE pattern '\(pattern)': \(error)")
                return false
            }
        }
        return self
    }
    
    /// WHERE field ILIKE pattern (case-insensitive)
    @discardableResult
    public func `where`(_ field: String, ilike pattern: String) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) ILIKE '\(pattern)'")
        filters.append { record in
            guard let fieldValue = record.storage[field]?.stringValue else {
                return false
            }
            
            do {
                let regex = try patternCache.getPattern(pattern, caseSensitive: false)
                let range = NSRange(location: 0, length: fieldValue.utf16.count)
                return regex.firstMatch(in: fieldValue, range: range) != nil
            } catch {
                BlazeLogger.warn("Invalid ILIKE pattern '\(pattern)': \(error)")
                return false
            }
        }
        return self
    }
    
    /// WHERE field NOT LIKE pattern (case-sensitive)
    @discardableResult
    public func `where`(_ field: String, notLike pattern: String) -> QueryBuilder {
        return `where` { record in
            guard let fieldValue = record.storage[field]?.stringValue else {
                return true
            }
            
            do {
                let regex = try patternCache.getPattern(pattern, caseSensitive: true)
                let range = NSRange(location: 0, length: fieldValue.utf16.count)
                return regex.firstMatch(in: fieldValue, range: range) == nil
            } catch {
                return true
            }
        }
    }
    
    /// WHERE field NOT ILIKE pattern (case-insensitive)
    @discardableResult
    public func `where`(_ field: String, notILike pattern: String) -> QueryBuilder {
        return `where` { record in
            guard let fieldValue = record.storage[field]?.stringValue else {
                return true
            }
            
            do {
                let regex = try patternCache.getPattern(pattern, caseSensitive: false)
                let range = NSRange(location: 0, length: fieldValue.utf16.count)
                return regex.firstMatch(in: fieldValue, range: range) == nil
            } catch {
                return true
            }
        }
    }
}

