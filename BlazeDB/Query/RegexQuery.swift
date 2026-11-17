//
//  RegexQuery.swift
//  BlazeDB
//
//  Regular expression query support
//  Optimized with compiled regex cache
//
import Foundation

// MARK: - Regex Cache (Performance Optimization)

private class RegexCache {
    private var cache: [String: NSRegularExpression] = [:]
    private let lock = NSLock()
    
    func getRegex(_ pattern: String, options: NSRegularExpression.Options = []) throws -> NSRegularExpression {
        let cacheKey = "\(options.rawValue):\(pattern)"
        
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = cache[cacheKey] {
            return cached
        }
        
        let regex = try NSRegularExpression(pattern: pattern, options: options)
        cache[cacheKey] = regex
        
        return regex
    }
    
    func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}

nonisolated(unsafe) private let regexCache = RegexCache()

// MARK: - QueryBuilder Regex Extension

extension QueryBuilder {
    
    /// WHERE field matches regex pattern
    @discardableResult
    public func `where`(_ field: String, matches regexPattern: String, options: NSRegularExpression.Options = []) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) ~ '\(regexPattern)'")
        recordRegexFilter(field: field, operation: "matches", pattern: regexPattern, options: options)
        filters.append { record in
            guard let fieldValue = record.storage[field]?.stringValue else {
                return false
            }
            
            do {
                let regex = try regexCache.getRegex(regexPattern, options: options)
                let range = NSRange(location: 0, length: fieldValue.utf16.count)
                return regex.firstMatch(in: fieldValue, range: range) != nil
            } catch {
                BlazeLogger.warn("Invalid regex pattern '\(regexPattern)': \(error)")
                return false
            }
        }
        return self
    }
    
    /// WHERE field does NOT match regex pattern
    @discardableResult
    public func `where`(_ field: String, notMatches regexPattern: String, options: NSRegularExpression.Options = []) -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) !~ '\(regexPattern)'")
        recordRegexFilter(field: field, operation: "notmatches", pattern: regexPattern, options: options)
        filters.append { record in
            guard let fieldValue = record.storage[field]?.stringValue else {
                return true
            }
            
            do {
                let regex = try regexCache.getRegex(regexPattern, options: options)
                let range = NSRange(location: 0, length: fieldValue.utf16.count)
                return regex.firstMatch(in: fieldValue, range: range) == nil
            } catch {
                return true
            }
        }
        return self
    }

    /// Regex options change which rows match, so they belong in the cache key.
    private func recordRegexFilter(
        field: String,
        operation: String,
        pattern: String,
        options: NSRegularExpression.Options
    ) {
        filterFields.insert(field)
        filterDescriptors.append(
            FilterDescriptor(
                field: field,
                operation: "\(operation):\(options.rawValue)",
                value: .string(pattern)
            )
        )
    }
    
    /// WHERE field matches regex (case-insensitive)
    @discardableResult
    public func `where`(_ field: String, matchesCaseInsensitive regexPattern: String) -> QueryBuilder {
        return `where`(field, matches: regexPattern, options: [.caseInsensitive])
    }
}

