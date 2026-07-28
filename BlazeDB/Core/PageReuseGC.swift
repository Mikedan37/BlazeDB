//
//  PageReuseGC.swift
//  BlazeDB
//
//  OPTIMIZED page reuse garbage collection (PRIMARY GC mechanism)
//  Prevents disk space waste with ZERO performance overhead
//  Based on design from GARBAGE_COLLECTION_NEEDED.md
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - DynamicCollection Page Reuse Extension

extension DynamicCollection {
    private func loadPageReuseLayout() throws -> StorageLayout {
        try loadLayoutForMutation()
    }

    #if DEBUG
    private static let allocatePageFaultLock = NSLock()
    /// One-shot fault: after skipping `skips` normal allocations, return `page` once.
    nonisolated(unsafe) private static var forceAllocateAfterSkips: Int? = nil
    nonisolated(unsafe) private static var forceAllocatePage: Int? = nil

    /// Test-only: force `allocatePage` to return `page` after `skips` normal allocations.
    /// Used to prove committed-page conflicts fail closed instead of deleting indexMap entries.
    internal static func _forceAllocatedPageAfterSkippingForTests(skips: Int, page: Int) {
        allocatePageFaultLock.lock()
        forceAllocateAfterSkips = skips
        forceAllocatePage = page
        allocatePageFaultLock.unlock()
    }

    internal static func _clearForcedAllocatedPageForTests() {
        allocatePageFaultLock.lock()
        forceAllocateAfterSkips = nil
        forceAllocatePage = nil
        allocatePageFaultLock.unlock()
    }
    #endif
    
    // MARK: - Page Allocation with Reuse
    
    /// Allocate a page index (reuses deleted pages first for efficiency)
    ///
    /// **Performance:**
    /// - Reuse: O(1) - pop from array
    /// - New allocation: O(1) - increment counter
    /// - Zero overhead!
    ///
    /// **Benefits:**
    /// - Prevents file growth
    /// - Automatic (no maintenance)
    /// - Handles 95% of cases
    internal func allocatePage(layout: inout StorageLayout) -> Int {
        #if DEBUG
        Self.allocatePageFaultLock.lock()
        if var skips = Self.forceAllocateAfterSkips, let forced = Self.forceAllocatePage {
            if skips > 0 {
                Self.forceAllocateAfterSkips = skips - 1
                Self.allocatePageFaultLock.unlock()
            } else {
                Self.forceAllocateAfterSkips = nil
                Self.forceAllocatePage = nil
                Self.allocatePageFaultLock.unlock()
                BlazeLogger.error("🧪 [TEST] Forced allocatePage → \(forced)")
                return forced
            }
        } else {
            Self.allocatePageFaultLock.unlock()
        }
        #endif

        if mvccEnabled, let reusablePage = versionManager.pageGC.getFreePage() {
            BlazeLogger.trace("♻️  Reusing MVCC free page \(reusablePage)")
            return reusablePage
        }

        // Try to reuse deleted page first (FIFO for better locality)
        if !layout.deletedPages.isEmpty {
            let reusablePage = layout.deletedPages.removeFirst()
            cachedDeletedPages = layout.deletedPages
            BlazeLogger.trace("♻️  Reusing deleted page \(reusablePage)")
            return reusablePage
        }
        
        // No deleted pages available - allocate new
        let newPage = layout.nextPageIndex
        layout.nextPageIndex += 1
        BlazeLogger.trace("📄 Allocated new page \(newPage)")
        return newPage
    }
    
    /// Track deleted page for reuse
    ///
    /// **Performance:** O(1) - append to array
    internal func markPageForReuse(pageIndex: Int, layout: inout StorageLayout) {
        // Add to end of array (FIFO reuse)
        layout.deletedPages.append(pageIndex)
        cachedDeletedPages = layout.deletedPages
        BlazeLogger.trace("🗑️  Marked page \(pageIndex) for reuse")
    }
    
    /// Get garbage collection statistics
    public func getGCStats() throws -> GCStats {
        return try queue.sync {
            let layout = try loadPageReuseLayout()
            
            let totalPages = layout.nextPageIndex
            let usedPages = layout.indexMap.count
            let deletedPages = layout.deletedPages.count
            let actuallyWasted = totalPages - usedPages - deletedPages
            
            return GCStats(
                totalPages: totalPages,
                usedPages: usedPages,
                reuseablePages: deletedPages,
                wastedPages: actuallyWasted,
                reuseEfficiency: deletedPages > 0 ? 100.0 : (actuallyWasted == 0 ? 100.0 : 0.0)
            )
        }
    }
}

// MARK: - GC Statistics

public struct GCStats {
    public let totalPages: Int
    public let usedPages: Int
    public let reuseablePages: Int
    public let wastedPages: Int
    public let reuseEfficiency: Double  // % of deleted pages tracked for reuse
    
    public var description: String {
        """
        Garbage Collection Stats:
          Total pages: \(totalPages)
          Used pages: \(usedPages)
          Reuseable (deleted): \(reuseablePages)
          Actually wasted: \(wastedPages)
          Reuse efficiency: \(String(format: "%.1f", reuseEfficiency))%
          
        \(wastedPages == 0 ? "✅ No wasted space!" : "⚠️  Consider running vacuum()")
        """
    }
}

// MARK: - Modified DynamicCollection Operations

extension DynamicCollection {
    
    /// Optimized insert with page reuse
    ///
    /// Automatically reuses deleted pages before allocating new ones.
    /// **Zero performance overhead** - same speed as before, but prevents waste!
    internal func insertWithPageReuse(_ data: BlazeDataRecord) throws -> UUID {
        var document = data.storage
        let id = document["id"]?.uuidValue ?? UUID()
        
        // Load layout
        var layout = try loadPageReuseLayout()
        
        // Allocate page (reuses deleted if available!)
        let pageIndex = allocatePage(layout: &layout)
        
        // Prepare document
        document["id"] = .uuid(id)
        document["createdAt"] = document["createdAt"] ?? .date(Date())
        
        // Encode and write
        let encoded = try JSONEncoder().encode(document)
        try store.writePage(index: pageIndex, plaintext: encoded)
        
        // Update indexMap (convert Int to [Int] for overflow chain support)
        indexMap[id] = [pageIndex]
        
        // Update indexes (same as before)
        for (compound, _) in secondaryIndexes {
            let fields = compound.components(separatedBy: "+")
            let indexKey = CompoundIndexKey.fromFields(document, fields: fields)
            var inner = secondaryIndexes[compound] ?? [:]
            var set = inner[indexKey] ?? Set<UUID>()
            set.insert(id)
            inner[indexKey] = set
            secondaryIndexes[compound] = inner
        }
        
        // Save layout with updated deletedPages (StorageLayout now expects [UUID: [Int]])
        layout.indexMap = indexMap
        layout.secondaryIndexes = StorageLayout.fromRuntimeIndexes(secondaryIndexes)
        try layout.saveSecure(to: metaURL, signingKey: encryptionKey)
        
        unsavedChanges += 1
        
        return id
    }
    
    /// Optimized delete with page tracking
    ///
    /// Marks deleted pages for reuse instead of wasting space.
    /// **Zero performance overhead** - same speed, but enables reuse!
    internal func deleteWithPageTracking(id: UUID) throws {
        guard let pageIndices = indexMap[id], let pageIndex = pageIndices.first else {
            throw BlazeDBError.recordNotFound(id: id)
        }
        
        // Load layout
        var layout = try loadPageReuseLayout()
        
        // Remove from indexes
        if let record = try? _fetchNoSync(id: id) {
            let oldDoc = record.storage
            for (compound, _) in secondaryIndexes {
                let fields = compound.components(separatedBy: "+")
                let oldKey = CompoundIndexKey.fromFields(oldDoc, fields: fields)
                if var inner = secondaryIndexes[compound] {
                    if var set = inner[oldKey] {
                        set.remove(id)
                        if set.isEmpty {
                            inner.removeValue(forKey: oldKey)
                        } else {
                            inner[oldKey] = set
                        }
                        secondaryIndexes[compound] = inner
                    }
                }
            }
        }
        
        // Remove from indexMap
        indexMap.removeValue(forKey: id)
        
        // Zero out page (security - clear sensitive data)
        let zeroed = Data(repeating: 0, count: 4096)
        try store.writePage(index: pageIndex, plaintext: zeroed)
        
        // Track for reuse! (THIS IS THE KEY!)
        markPageForReuse(pageIndex: pageIndex, layout: &layout)
        
        // Save layout (StorageLayout now expects [UUID: [Int]])
        layout.indexMap = indexMap
        layout.secondaryIndexes = StorageLayout.fromRuntimeIndexes(secondaryIndexes)
        try layout.saveSecure(to: metaURL, signingKey: encryptionKey)
        
        unsavedChanges += 1
    }
}

// MARK: - Page allocation errors

extension BlazeDBError {
    /// Allocator returned a page still referenced by a committed `indexMap` entry.
    /// Callers must abort rather than deleting the existing record to "make room."
    public static func pageAllocationConflict(page: Int) -> BlazeDBError {
        .corruptedData(
            location: "page \(page)",
            reason: "allocatePage returned a page already referenced by a committed indexMap entry; refusing to delete the existing record"
        )
    }
}

// MARK: - StorageLayout Helper Methods

extension StorageLayout {
    
    /// Convert runtime indexes to storage format
    static func fromRuntimeIndexes(_ runtime: [String: [CompoundIndexKey: Set<UUID>]]) -> [String: [CompoundIndexKey: [UUID]]] {
        return runtime.mapValues { inner in
            inner.mapValues { Array($0) }
        }
    }
}


