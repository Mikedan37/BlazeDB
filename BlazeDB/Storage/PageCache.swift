//
//  PageCache.swift
//  BlazeDB
//
//  High-performance page cache with LRU eviction and parallel read support
//
//  Created by Michael Danylchuk on 1/15/25.
//

import Foundation

/// High-performance page cache with LRU eviction
final class PageCache {
    private var cache: [Int: Data] = [:]
    internal var accessOrder: [Int] = []  // LRU tracking (internal for optimized extensions)
    private let maxSize: Int
    private let lock = NSLock()
    
    init(maxSize: Int = 1000) {  // Cache up to 1000 pages (~4MB)
        self.maxSize = maxSize
    }
    
    func get(_ pageIndex: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let data = cache[pageIndex] else {
            return nil
        }
        
        // Move to end (most recently used)
        if let index = accessOrder.firstIndex(of: pageIndex) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(pageIndex)
        
        return data
    }
    
    func set(_ pageIndex: Int, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        
        // Evict oldest if at capacity
        if cache.count >= maxSize && !cache.keys.contains(pageIndex) {
            if let oldest = accessOrder.first {
                cache.removeValue(forKey: oldest)
                accessOrder.removeFirst()
            }
        }
        
        cache[pageIndex] = data
        
        // Update access order
        if let index = accessOrder.firstIndex(of: pageIndex) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(pageIndex)
    }
    
    func remove(_ pageIndex: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeValue(forKey: pageIndex)
        if let index = accessOrder.firstIndex(of: pageIndex) {
            accessOrder.remove(at: index)
        }
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeAll()
        accessOrder.removeAll()
    }
    
    func prefetch(_ pageIndices: [Int], reader: (Int) throws -> Data?) throws {
        // Serial prefetch for Swift 6 concurrency compliance
        var errors: [Error] = []
        
        for index in pageIndices {
            // Skip if already cached
            if get(index) != nil { continue }
            
            do {
                if let data = try reader(index) {
                    set(index, data: data)
                }
            } catch {
                errors.append(error)
            }
        }
        
        if let firstError = errors.first {
            throw firstError
        }
    }
}

