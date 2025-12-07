//
//  PageGarbageCollector.swift
//  BlazeDB
//
//  Page-level garbage collection for MVCC
//
//  Tracks obsolete disk pages and enables reuse to prevent file blowup.
//  Works in conjunction with VersionManager to keep both memory AND disk clean.
//
//  Created: 2025-11-13
//

import Foundation

/// Tracks and manages obsolete disk pages
///
/// When a record version is garbage collected, its page becomes obsolete.
/// This class tracks those pages and allows them to be reused for new writes,
/// preventing the database file from growing forever.
public class PageGarbageCollector {
    
    /// Set of page numbers that are obsolete and can be reused
    private var freePages: Set<Int> = []
    
    /// Pages that are potentially freeable (waiting for version GC)
    private var pendingPages: Set<Int> = []
    
    /// Track page usage for statistics
    private var totalPagesFreed: Int = 0
    private var totalPagesReused: Int = 0
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Page Tracking
    
    /// Mark a page as obsolete (can be reused)
    ///
    /// Called when a version is garbage collected.
    /// The page that version pointed to is now free.
    public func markPageObsolete(_ pageNumber: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        freePages.insert(pageNumber)
        totalPagesFreed += 1
        
        BlazeLogger.trace("🗑️ Page \(pageNumber) marked as obsolete (total free: \(freePages.count))")
    }
    
    /// Mark multiple pages as obsolete
    public func markPagesObsolete(_ pageNumbers: [Int]) {
        lock.lock()
        defer { lock.unlock() }
        
        for page in pageNumbers {
            freePages.insert(page)
        }
        totalPagesFreed += pageNumbers.count
        
        BlazeLogger.trace("🗑️ \(pageNumbers.count) pages marked obsolete")
    }
    
    /// Get a free page for reuse (if available)
    ///
    /// Returns nil if no free pages available.
    /// This should be called before allocating a new page.
    public func getFreePage() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let page = freePages.first else {
            return nil
        }
        
        freePages.remove(page)
        totalPagesReused += 1
        
        BlazeLogger.trace("♻️ Reusing page \(page) (free pages remaining: \(freePages.count))")
        
        return page
    }
    
    /// Get multiple free pages at once
    public func getMultipleFreePages(count: Int) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        
        let available = Array(freePages.prefix(count))
        freePages.subtract(available)
        totalPagesReused += available.count
        
        return available
    }
    
    /// Mark a page as pending (might become free after version GC)
    public func markPagePending(_ pageNumber: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        pendingPages.insert(pageNumber)
    }
    
    /// Promote pending pages to free (called after version GC)
    public func promotePendingPages() {
        lock.lock()
        defer { lock.unlock() }
        
        freePages.formUnion(pendingPages)
        totalPagesFreed += pendingPages.count
        pendingPages.removeAll()
        
        BlazeLogger.debug("♻️ Promoted \(pendingPages.count) pending pages to free")
    }
    
    // MARK: - Statistics
    
    /// Get page GC statistics
    public func getStats() -> PageGCStats {
        lock.lock()
        defer { lock.unlock() }
        
        return PageGCStats(
            freePagesAvailable: freePages.count,
            pendingPages: pendingPages.count,
            totalPagesFreed: totalPagesFreed,
            totalPagesReused: totalPagesReused,
            reuseRate: totalPagesFreed > 0 ? Double(totalPagesReused) / Double(totalPagesFreed) : 0
        )
    }
    
    /// Clear all free pages (for testing)
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        freePages.removeAll()
        pendingPages.removeAll()
    }
}

/// Page GC statistics
public struct PageGCStats {
    public let freePagesAvailable: Int
    public let pendingPages: Int
    public let totalPagesFreed: Int
    public let totalPagesReused: Int
    public let reuseRate: Double
    
    public var description: String {
        """
        Page GC Stats:
          Free pages:      \(freePagesAvailable)
          Pending:         \(pendingPages)
          Total freed:     \(totalPagesFreed)
          Total reused:    \(totalPagesReused)
          Reuse rate:      \(String(format: "%.1f", reuseRate * 100))%
        """
    }
}

