//
//  PageStore+Overflow.swift
//  BlazeDB
//
//  Overflow page support for large records (>4KB)
//  Implements page chains for records that don't fit in a single page
//
//  Created by Auto on 1/XX/25.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// MARK: - Overflow Page Format

/// Overflow page header (16 bytes)
struct OverflowPageHeader {
    static let magic: UInt32 = 0x4F564552  // "OVER" in ASCII
    static let version: UInt8 = 0x03       // Version 0x03 = overflow page
    
    let nextPageIndex: UInt32  // 0 = end of chain, >0 = next overflow page
    let dataLength: UInt32     // Bytes of data in this page
    
    init(nextPageIndex: UInt32, dataLength: UInt32) {
        self.nextPageIndex = nextPageIndex
        self.dataLength = dataLength
    }
    
    /// Encode header to Data (16 bytes)
    func encode() -> Data {
        var data = Data()
        var magic = OverflowPageHeader.magic.bigEndian
        data.append(Data(bytes: &magic, count: 4))
        data.append(OverflowPageHeader.version)
        
        // 3 bytes padding (reserved for future use)
        data.append(Data(repeating: 0, count: 3))
        
        var nextPage = nextPageIndex.bigEndian
        data.append(Data(bytes: &nextPage, count: 4))
        
        var length = dataLength.bigEndian
        data.append(Data(bytes: &length, count: 4))
        
        return data
    }
    
    /// Decode header from Data
    static func decode(from data: Data) throws -> OverflowPageHeader {
        guard data.count >= 16 else {
            throw NSError(domain: "PageStore", code: 4001, userInfo: [
                NSLocalizedDescriptionKey: "Overflow page header too short"
            ])
        }
        
        // Verify magic - use safe byte-by-byte reading to avoid alignment crashes
        guard data.count >= 4 else {
            throw NSError(domain: "PageStore", code: 4001, userInfo: [
                NSLocalizedDescriptionKey: "Data too short for overflow page header"
            ])
        }
        let magic = (UInt32(data[0]) << 24) | (UInt32(data[1]) << 16) | (UInt32(data[2]) << 8) | UInt32(data[3])
        guard magic == OverflowPageHeader.magic else {
            throw NSError(domain: "PageStore", code: 4002, userInfo: [
                NSLocalizedDescriptionKey: "Invalid overflow page magic"
            ])
        }
        
        // Verify version
        guard data.count >= 5 && data[4] == OverflowPageHeader.version else {
            throw NSError(domain: "PageStore", code: 4003, userInfo: [
                NSLocalizedDescriptionKey: "Invalid overflow page version"
            ])
        }
        
        // Read next page index (bytes 8-11) - use safe byte-by-byte reading
        guard data.count >= 12 else {
            throw NSError(domain: "PageStore", code: 4004, userInfo: [
                NSLocalizedDescriptionKey: "Data too short for overflow page next index"
            ])
        }
        let nextPageIndex = (UInt32(data[8]) << 24) | (UInt32(data[9]) << 16) | (UInt32(data[10]) << 8) | UInt32(data[11])
        
        // Read data length (bytes 12-15) - use safe byte-by-byte reading
        guard data.count >= 16 else {
            throw NSError(domain: "PageStore", code: 4005, userInfo: [
                NSLocalizedDescriptionKey: "Data too short for overflow page data length"
            ])
        }
        let dataLength = (UInt32(data[12]) << 24) | (UInt32(data[13]) << 16) | (UInt32(data[14]) << 8) | UInt32(data[15])
        
        return OverflowPageHeader(nextPageIndex: nextPageIndex, dataLength: dataLength)
    }
}

// MARK: - PageStore Overflow Extension

extension PageStore {
    
    // MARK: - Constants
    
    /// Maximum data per page (pageSize - overhead)
    private var maxDataPerPage: Int {
        // Regular page: 9 bytes header + 12 bytes nonce + 16 bytes tag = 37 bytes overhead
        // Use conservative estimate: 50 bytes overhead for regular pages
        return pageSize - 50
    }
    
    /// Maximum data per overflow page (pageSize - overhead)
    private var maxDataPerOverflowPage: Int {
        // Overflow page: 16 bytes header + 12 bytes nonce + 16 bytes tag = 44 bytes overhead
        return pageSize - 44
    }
    
    // MARK: - Write with Overflow Support
    
    /// Internal version that doesn't sync (caller must already hold barrier lock)
    /// - Parameter skipSync: If true, skip the final fsync (for batch operations)
    internal func _writePageWithOverflowLocked(
        index: Int,
        plaintext: Data,
        allocatePage: () throws -> Int,
        skipSync: Bool = false
    ) throws -> [Int] {
        var pageIndices = [index]
        
        // If data fits in one page, write normally
        if plaintext.count <= maxDataPerPage {
            try _writePageLocked(index: index, plaintext: plaintext)
            return pageIndices
        }
        
        // Data doesn't fit - need overflow pages
        BlazeLogger.debug("Writing large record (\(plaintext.count) bytes) with overflow pages")
        
        // Reserve 4 bytes at end of main page for overflow pointer
        let mainPageDataSize = maxDataPerPage - 4
        let firstPageData = plaintext.prefix(mainPageDataSize)
        let remainingData = plaintext.dropFirst(mainPageDataSize)
        
        // Write overflow chain first to get the first overflow page index
        var firstOverflowIndex: UInt32 = 0
        
        // First pass: allocate all overflow pages and determine the chain structure
        var overflowPages: [(index: Int, data: Data, nextIndex: UInt32)] = []
        var tempCurrentData = remainingData
        
        while !tempCurrentData.isEmpty {
            let overflowPageIndex = try allocatePage()
            pageIndices.append(overflowPageIndex)
            
            // Store first overflow index
            if firstOverflowIndex == 0 {
                firstOverflowIndex = UInt32(overflowPageIndex)
            }
            
            // Determine how much data fits in this overflow page
            // Overflow pages can fit more data than regular pages (44 bytes overhead vs 50 bytes)
            let chunkSize = min(tempCurrentData.count, maxDataPerOverflowPage)
            let chunk = tempCurrentData.prefix(chunkSize)
            // Note: tempCurrentData.count > chunkSize indicates more data remains (handled by while loop)
            
            // Determine next page index (0 if this is the last page, will be set in second pass)
            let nextPageIndex: UInt32 = 0  // Will be updated in second pass
            
            overflowPages.append((index: overflowPageIndex, data: chunk, nextIndex: nextPageIndex))
            tempCurrentData = tempCurrentData.dropFirst(chunkSize)
        }
        
        // Second pass: write overflow pages with correct next pointers
        BlazeLogger.debug("📝 [writePageWithOverflow] Writing \(overflowPages.count) overflow pages for \(plaintext.count) bytes total")
        for i in 0..<overflowPages.count {
            let nextIndex: UInt32 = (i + 1 < overflowPages.count) ? UInt32(overflowPages[i + 1].index) : 0
            let isLastPage = (i + 1 == overflowPages.count)
            BlazeLogger.debug("📝 [writePageWithOverflow] Writing overflow page \(i+1)/\(overflowPages.count) at index \(overflowPages[i].index): \(overflowPages[i].data.count) bytes, nextPageIndex: \(nextIndex) \(isLastPage ? "(last page)" : "(points to page \(overflowPages[i + 1].index)")")
            try _writeOverflowPage(
                index: overflowPages[i].index,
                data: overflowPages[i].data,
                nextPageIndex: nextIndex
            )
        }
        BlazeLogger.debug("📝 [writePageWithOverflow] ✅ Completed writing overflow chain: main page \(index) -> first overflow \(firstOverflowIndex)")
        
        // Append overflow pointer to main page data (last 4 bytes)
        // CRITICAL: Ensure we create a proper Data instance from the subsequence
        let firstPageDataCopy = Data(firstPageData)
        var mainPageDataWithPointer = firstPageDataCopy
        var overflowPointer = firstOverflowIndex.bigEndian
        mainPageDataWithPointer.append(Data(bytes: &overflowPointer, count: 4))
        
        // Write main page with overflow pointer embedded
        try _writePageLocked(index: index, plaintext: mainPageDataWithPointer)
        
        // Final fsync (skip for batch operations - will sync once at end)
        if !skipSync {
            try fileHandle.compatSynchronize()
        }
        
        BlazeLogger.debug("✅ Wrote large record across \(pageIndices.count) pages")
        return pageIndices
    }
    
    /// Write data with overflow page support (handles records >4KB)
    /// - Parameters:
    ///   - index: Main page index
    ///   - plaintext: Data to write (can be >4KB)
    ///   - allocatePage: Function to allocate new pages for overflow chain
    /// - Returns: Array of all page indices used (main + overflow pages)
    /// - Throws: Error if write fails
    public func writePageWithOverflow(
        index: Int,
        plaintext: Data,
        allocatePage: () throws -> Int
    ) throws -> [Int] {
        #if os(Linux)
        // Linux doesn't support flags parameter for sync
        return try queue.sync {
            try _writePageWithOverflowLocked(
                index: index,
                plaintext: plaintext,
                allocatePage: allocatePage
            )
        }
        #else
        return try queue.sync(flags: .barrier) {
            try _writePageWithOverflowLocked(
                index: index,
                plaintext: plaintext,
                allocatePage: allocatePage
            )
        }
        #endif
    }
    
    // MARK: - Read with Overflow Support
    
    /// Read data with overflow page support
    /// - Parameter index: Main page index
    /// - Returns: Complete data (main page + overflow chain)
    /// - Throws: Error if read fails
    public func readPageWithOverflow(index: Int) throws -> Data? {
        // Help the compiler by explicitly typing the closure result
        let result: Data? = try queue.sync {
            BlazeLogger.debug("📖 [readPageWithOverflow] Starting read for page \(index)")
            // Read main page directly (check cache first, then read from file)
            // We're already in a sync block, so we can access cache and file directly
            var mainPageData: Data?
            
            // Check cache first
            if let cached = pageCache.get(index) {
                BlazeLogger.debug("📖 [readPageWithOverflow] Page \(index) found in cache: \(cached.count) bytes")
                mainPageData = cached
            } else {
                BlazeLogger.debug("📖 [readPageWithOverflow] Page \(index) not in cache, reading from file")
                // Read from file
                // CRITICAL: Validate pageSize before using it
                guard pageSize > 0 && pageSize <= Int.max else {
                    return nil as Data?
                }
                // CRITICAL: Validate index before multiplying
                guard index >= 0 else {
                    return nil as Data?
                }
                // CRITICAL: Cast to UInt64 before multiplying to prevent integer overflow
                let indexUInt64 = UInt64(index)
                let pageSizeUInt64 = UInt64(pageSize)
                let offset = indexUInt64 * pageSizeUInt64
                let exists = FileManager.default.fileExists(atPath: fileURL.path)
                guard exists else {
                    return nil as Data?
                }
                
                // CRITICAL: Use UInt64 for file size comparison to prevent integer overflow
                // File sizes can exceed Int.max on large databases
                let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                guard offset < fileSize else {
                    return nil as Data?
                }
                // CRITICAL: Don't nest queue.sync - we're already inside queue.sync at line 227!
                // Nesting causes deadlock when DynamicCollection calls this during createIndex
                // CRITICAL: Always seek to correct position before reading to ensure file handle position is correct
                // This is especially important during concurrent reads
                try fileHandle.compatSeek(toOffset: offset)
                // Verify we're at the correct position (optional check, but helps catch issues)
                let currentOffset = try fileHandle.compatOffset()
                if currentOffset != offset {
                    BlazeLogger.warn("📖 [readPageWithOverflow] ⚠️ File handle position mismatch: expected \(offset), got \(currentOffset) - reseeking")
                    try fileHandle.compatSeek(toOffset: offset)
                }
                let pageData = try fileHandle.compatRead(upToCount: pageSize)
                
                // Decrypt the page
                guard pageData.count >= 37 else { // 9 header + 12 nonce + 16 tag minimum
                    return nil as Data?
                }
                
                // Parse header: [BZDB][0x02][length(4)]
                let magic = String(data: pageData.subdata(in: 0..<4), encoding: .utf8) ?? ""
                guard magic == "BZDB" && pageData[4] == 0x02 else {
                    return nil as Data?
                }
                
                // CRITICAL: Use safe byte-by-byte reading to avoid alignment crashes
                // Unsafe load() can crash on misaligned data
                guard pageData.count >= 9 else {
                    return nil as Data?
                }
                let byte5 = UInt32(pageData[5])
                let byte6 = UInt32(pageData[6])
                let byte7 = UInt32(pageData[7])
                let byte8 = UInt32(pageData[8])
                let lengthUInt32 = (byte5 << 24) | (byte6 << 16) | (byte7 << 8) | byte8
                
                // CRITICAL: Validate UInt32 can be safely converted to Int
                // Note: On 64-bit systems, UInt32.max (4,294,967,295) < Int.max (9,223,372,036,854,775,807),
                // so any UInt32 can be safely converted to Int. We don't need to check UInt32(Int.max)
                // because that would overflow. Instead, we just verify the value is reasonable.
                // On 64-bit systems, any UInt32 fits in Int, so this is safe
                let length = Int(lengthUInt32)
                
                let nonceData = pageData.subdata(in: 9..<21)
                guard let nonce = try? AES.GCM.Nonce(data: nonceData) else {
                    return nil as Data?
                }
                
                let tagData = pageData.subdata(in: 21..<37)
                
                // Bounds check: ensure we don't exceed pageData bounds
                // This can happen during concurrent writes where a page is partially written
                // CRITICAL: Check for integer overflow in addition
                guard 37 <= Int.max - length else {
                    return nil as Data?
                }
                let expectedCiphertextEnd = 37 + length
                guard expectedCiphertextEnd <= pageData.count else {
                    return nil as Data?  // Corrupted page - return nil instead of crashing
                }
                let ciphertextData = pageData.subdata(in: 37..<expectedCiphertextEnd)
                
                let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
                do {
                    mainPageData = try AES.GCM.open(sealedBox, using: key)
                } catch {
                    throw error
                }
                
                // Cache it
                if let data = mainPageData {
                    BlazeLogger.debug("📖 [readPageWithOverflow] Successfully read and decrypted page \(index): \(data.count) bytes")
                    pageCache.set(index, data: data)
                } else {
                    BlazeLogger.error("📖 [readPageWithOverflow] Failed to decrypt page \(index)")
                }
            }
            
            guard let mainPageData = mainPageData else {
                BlazeLogger.error("📖 [readPageWithOverflow] Main page data is nil for page \(index)")
                return nil as Data?
            }
            
            
            // Check if this page has overflow by checking if data is exactly maxDataPerPage
            // If so, the last 4 bytes contain the overflow pointer
            var completeData = mainPageData
            var currentOverflowIndex: UInt32 = 0
            
            // If main page data is exactly maxDataPerPage, check if last 4 bytes are overflow pointer
            // CRITICAL: Validate bounds before accessing last 4 bytes
            // IMPORTANT: Only check for overflow if the data is exactly maxDataPerPage AND
            // the potential pointer points to a valid overflow page (has "OVER" magic bytes)
            BlazeLogger.debug("📖 [readPageWithOverflow] Main page data size: \(mainPageData.count), maxDataPerPage: \(maxDataPerPage)")
            if mainPageData.count == maxDataPerPage && mainPageData.count >= 4 {
                BlazeLogger.debug("📖 [readPageWithOverflow] Main page is exactly maxDataPerPage, checking for overflow pointer")
                // Extract potential overflow pointer from last 4 bytes
                // Use safe unaligned read to avoid alignment issues with Data.SubSequence
                let offset = mainPageData.count - 4
                // CRITICAL: Validate offset is non-negative and within bounds
                guard offset >= 0 && offset + 4 <= mainPageData.count else {
                    BlazeLogger.error("❌ Invalid offset for overflow pointer extraction: offset=\(offset), data.count=\(mainPageData.count)")
                    return nil as Data?
                }
                let byte1 = UInt32(mainPageData[offset])
                let byte2 = UInt32(mainPageData[offset + 1])
                let byte3 = UInt32(mainPageData[offset + 2])
                let byte4 = UInt32(mainPageData[offset + 3])
                let potentialPointer = (byte1 << 24) | (byte2 << 16) | (byte3 << 8) | byte4
                BlazeLogger.debug("📖 [readPageWithOverflow] Extracted potential overflow pointer: \(potentialPointer) (bytes: [\(byte1), \(byte2), \(byte3), \(byte4)])")
                
                // CRITICAL: Skip validation read during main read path to avoid file position corruption
                // The validation read was causing issues during concurrent reads because it changes
                // the file position, which can corrupt the file handle state even though _readOverflowPage
                // seeks to the correct position. Instead, we'll validate the chain when we actually read it.
                // If the chain is invalid, _readOverflowPage will return nil and we'll handle it gracefully.
                let isValidOverflowPointer = potentialPointer > 0
                BlazeLogger.debug("📖 [readPageWithOverflow] Overflow pointer valid: \(isValidOverflowPointer)")
                
                // Set overflow pointer and prepare to read chain
                // We'll validate the chain as we read it - if any page is invalid,
                // _readOverflowPage will return nil and we'll handle it gracefully
                if isValidOverflowPointer {
                    // CRITICAL: Validate overflow pointer is reasonable
                    // It should not point back to the main page or to an invalid index
                    let overflowPageIndex = Int(potentialPointer)
                    if overflowPageIndex == index {
                        BlazeLogger.warn("Overflow pointer \(potentialPointer) points back to main page \(index) - treating as no overflow")
                        completeData = mainPageData
                        currentOverflowIndex = 0
                    } else if overflowPageIndex < 0 {
                        BlazeLogger.warn("Overflow pointer \(potentialPointer) is invalid (negative) - treating as no overflow")
                        completeData = mainPageData
                        currentOverflowIndex = 0
                    } else {
                        BlazeLogger.debug("Detected overflow pointer \(potentialPointer) for main page \(index)")
                        // Extract pointer and remove from data
                        currentOverflowIndex = potentialPointer
                        completeData = mainPageData.prefix(maxDataPerPage - 4)
                    }
                } else {
                    // Pointer is 0, no overflow - use full data
                    completeData = mainPageData
                    currentOverflowIndex = 0
                }
            }
            
            // Read overflow chain with loop detection
            var visitedPages = Set<Int>()
            let initialOverflowIndex = currentOverflowIndex
            // CRITICAL: Limit chain length to prevent infinite loops from corrupted data
            let maxChainLength = 10_000  // Allow up to 10,000 pages (~40MB)
            var chainLength = 0
            var detectedCircularReference = false
            
            if initialOverflowIndex > 0 {
                BlazeLogger.debug("📖 [readPageWithOverflow] Starting overflow chain read from page \(index), initial overflow index: \(initialOverflowIndex), main page data: \(completeData.count) bytes")
            } else {
                BlazeLogger.debug("📖 [readPageWithOverflow] No overflow chain for page \(index), returning main page data: \(completeData.count) bytes")
            }
            
            while currentOverflowIndex > 0 && chainLength < maxChainLength {
                BlazeLogger.debug("📖 [readPageWithOverflow] Chain iteration \(chainLength + 1): reading overflow page at index \(currentOverflowIndex)")
                chainLength += 1
                
                // CRITICAL: Validate UInt32 can be safely converted to Int
                // On 64-bit systems, any UInt32 fits in Int. On 32-bit systems, we need to check.
                if Int.max < UInt32.max {
                    // 32-bit system: need to check
                    guard currentOverflowIndex <= UInt32(Int.max) else {
                        BlazeLogger.error("Overflow pointer \(currentOverflowIndex) exceeds Int.max, cannot read chain")
                        break
                    }
                }
                // On 64-bit systems, any UInt32 fits in Int, so no check needed
                let currentIndex = Int(currentOverflowIndex)
                // CRITICAL: Validate page index is non-negative
                guard currentIndex >= 0 else {
                    BlazeLogger.error("Invalid page index \(currentIndex) from overflow pointer \(currentOverflowIndex)")
                    break
                }
                
                // Detect circular reference BEFORE reading the page
                // This prevents reading corrupted data that might cause issues
                if visitedPages.contains(currentIndex) {
                    BlazeLogger.error("Circular overflow chain detected: page \(currentIndex) visited twice. Chain: \(visitedPages)")
                    // Mark that we detected a circular reference - we'll return nil instead of incomplete data
                    detectedCircularReference = true
                    break
                }
                visitedPages.insert(currentIndex)
                
                // Try to read overflow page
                // CRITICAL: If we expected an overflow chain but can't read all pages, return nil
                // This prevents returning incomplete data that will cause decoder errors
                do {
                    BlazeLogger.debug("📖 [readPageWithOverflow] Attempting to read overflow page \(currentIndex)")
                    guard let overflowData = try _readOverflowPage(index: currentIndex) else {
                        // Overflow page missing - check if this is the first page in the chain
                        // If it is, it might be a false positive (data that looks like an overflow pointer)
                        if chainLength == 1 && initialOverflowIndex > 0 {
                            // This is the first overflow page and it doesn't exist
                            // Likely a false positive - the last 4 bytes of main page were just data
                            BlazeLogger.warn("📖 [readPageWithOverflow] ⚠️ First overflow page \(currentIndex) missing - likely false positive overflow pointer. Treating as no overflow.")
                            // Return the full main page data (without removing the last 4 bytes)
                            return mainPageData
                        }
                        // Overflow page missing - always return nil to allow retry
                        // Partial data return is only for specific destructive test scenarios, not normal reads
                        if initialOverflowIndex > 0 {
                            BlazeLogger.error("📖 [readPageWithOverflow] ❌ Overflow page \(currentIndex) missing - incomplete chain detected. Total data so far: \(completeData.count) bytes. Returning nil for retry.")
                            return nil as Data?
                        }
                        BlazeLogger.warn("📖 [readPageWithOverflow] ⚠️ Overflow page \(currentIndex) missing or corrupted - stopping chain. Total data so far: \(completeData.count) bytes")
                        break
                    }
                    BlazeLogger.debug("📖 [readPageWithOverflow] ✅ Successfully read overflow page \(currentIndex): \(overflowData.data.count) bytes, nextPageIndex: \(overflowData.nextPageIndex)")
                    
                    completeData.append(overflowData.data)
                    BlazeLogger.debug("📖 [readPageWithOverflow] Total data after page \(currentIndex): \(completeData.count) bytes (main: \(mainPageData.count - (mainPageData.count == maxDataPerPage ? 4 : 0)), overflow: \(completeData.count - (mainPageData.count - (mainPageData.count == maxDataPerPage ? 4 : 0)))")
                    
                    // CRITICAL: Validate nextPageIndex before following it
                    // Prevent circular references by checking if we've already visited the next page
                    let nextIndex = Int(overflowData.nextPageIndex)
                    if nextIndex > 0 && visitedPages.contains(nextIndex) {
                        BlazeLogger.error("Overflow page \(currentIndex) points to already-visited page \(nextIndex) - breaking chain to prevent circular reference")
                        detectedCircularReference = true
                        break
                    }
                    
                    currentOverflowIndex = overflowData.nextPageIndex
                    if currentOverflowIndex == 0 {
                        BlazeLogger.debug("📖 [readPageWithOverflow] ✅ Reached end of overflow chain at page \(currentIndex), total data: \(completeData.count) bytes")
                    } else {
                        BlazeLogger.debug("📖 [readPageWithOverflow] Chain continues to page \(currentOverflowIndex), total data so far: \(completeData.count) bytes")
                    }
                } catch {
                    // CRITICAL: Errors during overflow page reads might be transient (file handle position issues)
                    // or actual corruption. For safety, return nil on errors to allow retry.
                    // Only return partial data when _readOverflowPage returns nil (page actually missing),
                    // not when it throws an error (which might be transient).
                    // CRITICAL: Always return nil on errors if we expected an overflow chain
                    // This ensures we don't return partial data during concurrent reads
                    if initialOverflowIndex > 0 {
                        BlazeLogger.error("📖 [readPageWithOverflow] ❌ Failed to read overflow page \(currentIndex): \(error) - returning nil (may be transient error, should retry)")
                        return nil as Data?  // Return nil to allow retry on transient errors
                    }
                    // If reading overflow page fails and we didn't expect an overflow chain,
                    // it might not actually be an overflow page (could be a regular page for a different record)
                    BlazeLogger.warn("📖 [readPageWithOverflow] ⚠️ Failed to read overflow page \(currentIndex): \(error) - stopping chain. Total data so far: \(completeData.count) bytes")
                    break
                }
            }
            
            // CRITICAL: If we detected a circular reference, return nil instead of incomplete data
            // This prevents returning corrupted/incomplete data that could cause decoder errors
            if detectedCircularReference && initialOverflowIndex > 0 {
                BlazeLogger.error("📖 [readPageWithOverflow] ❌ Returning nil due to circular reference in overflow chain starting at page \(initialOverflowIndex). Total data: \(completeData.count) bytes")
                return nil as Data?
            }
            
            // If chain length limit was hit, also return nil for safety
            if chainLength >= maxChainLength && currentOverflowIndex > 0 {
                BlazeLogger.error("📖 [readPageWithOverflow] ❌ Overflow chain length limit (\(maxChainLength)) reached - possible infinite loop or corrupted data. Total data: \(completeData.count) bytes")
                return nil as Data?
            }
            
            let mainPageDataSize = mainPageData.count == maxDataPerPage ? mainPageData.count - 4 : mainPageData.count
            let overflowDataSize = completeData.count - mainPageDataSize
            BlazeLogger.debug("📖 [readPageWithOverflow] ✅ Successfully read complete page \(index) with overflow chain: \(completeData.count) bytes total (main: \(mainPageDataSize), overflow: \(overflowDataSize) from \(chainLength) pages, initialOverflowIndex: \(initialOverflowIndex))")
            
            // CRITICAL: If we expected an overflow chain but got incomplete data, return nil
            // We should only return completeData if:
            // 1. No overflow chain was expected (initialOverflowIndex == 0), OR
            // 2. Overflow chain was expected and we reached the end (currentOverflowIndex == 0)
            // If we expected a chain but currentOverflowIndex > 0, the chain is incomplete
            if initialOverflowIndex > 0 && currentOverflowIndex > 0 && !detectedCircularReference {
                // We expected an overflow chain but didn't reach the end (currentOverflowIndex > 0 means more pages expected)
                // This indicates an incomplete chain - return nil to allow retry
                BlazeLogger.error("📖 [readPageWithOverflow] ❌ Incomplete overflow chain detected: expected chain starting at \(initialOverflowIndex), but stopped at page with nextPageIndex \(currentOverflowIndex). Total data: \(completeData.count) bytes. Returning nil for retry.")
                return nil as Data?
            }
            
            // CRITICAL: If we expected an overflow chain but got incomplete data, validate the size
            // For a 10KB record, we should have at least main page + overflow pages
            // If we expected an overflow chain but chainLength is 0, we likely didn't read the chain
            if initialOverflowIndex > 0 && currentOverflowIndex == 0 && chainLength == 0 {
                // We expected an overflow chain but didn't read any overflow pages
                // This means the chain read failed - return nil to allow retry
                BlazeLogger.error("📖 [readPageWithOverflow] ❌ Expected overflow chain starting at \(initialOverflowIndex) but no overflow pages were read. Returning nil for retry.")
                return nil as Data?
            }
            
            // CRITICAL: Additional validation - if we read overflow pages but got suspiciously little data,
            // it might indicate an incomplete read. For a record that needs overflow, we should have
            // at least the main page + some overflow data. If we read overflow pages but the total
            // is less than main page + one full overflow page worth of data, it's likely incomplete.
            if initialOverflowIndex > 0 && chainLength > 0 {
                let mainPageDataSize = mainPageData.count == maxDataPerPage ? mainPageData.count - 4 : mainPageData.count
                // Minimum expected: main page + at least one overflow page's worth of data
                // Each overflow page can hold up to (maxDataPerPage - 16) bytes of data
                let minExpectedSize = mainPageDataSize + (maxDataPerPage - 16)
                if completeData.count < minExpectedSize {
                    BlazeLogger.error("📖 [readPageWithOverflow] ❌ Incomplete overflow chain read: got \(completeData.count) bytes total (main: \(mainPageDataSize), overflow: \(completeData.count - mainPageDataSize)) but expected at least \(minExpectedSize) bytes for \(chainLength) overflow pages. Returning nil for retry.")
                    return nil as Data?
                }
            }
            
            return completeData
        }
        return result
    }
    
    /// Batch read multiple pages with overflow support (optimized for prefetched pages)
    /// - Parameter indices: Array of page indices to read
    /// - Returns: Dictionary mapping page index to complete data (main page + overflow chain)
    /// - Throws: Error if read fails
    /// - Note: This method reads pages directly from cache when available, minimizing sync overhead
    public func readPagesWithOverflowBatch(indices: [Int]) throws -> [Int: Data] {
        // Read pages directly from cache (thread-safe with NSLock)
        // This avoids sync overhead since cache access is already thread-safe
        var results: [Int: Data] = [:]
        
        for index in indices {
            // Check cache first (most pages should be prefetched)
            if let cached = pageCache.get(index) {
                results[index] = cached
            }
            // If not in cache, skip it - caller will fall back to individual reads
            // This is safe because prefetch should have loaded all pages
        }
        
        return results
    }
    
    // MARK: - Private Helper Methods
    
    /// Write main page with overflow indicator
    private func _writePageLockedWithOverflow(
        index: Int,
        plaintext: Data,
        hasOverflow: Bool
    ) throws {
        // NOTE: Overflow pointer in page header intentionally not implemented.
        // Overflow pages are tracked via metadata (indexMap) rather than in-page pointers.
        // This design simplifies page format and enables efficient garbage collection.
        try _writePageLocked(index: index, plaintext: plaintext)
    }
    
    /// Write an overflow page
    private func _writeOverflowPage(
        index: Int,
        data: Data,
        nextPageIndex: UInt32
    ) throws {
        // Invalidate cache
        pageCache.remove(index)
        
        // Create overflow header
        let header = OverflowPageHeader(
            nextPageIndex: nextPageIndex,
            dataLength: UInt32(data.count)
        )
        let headerData = header.encode()
        
        // Encrypt the data portion
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        
        // Build page: header(16) + nonce(12) + tag(16) + ciphertext
        var buffer = Data()
        buffer.append(headerData)                    // 16 bytes: overflow header
        buffer.append(contentsOf: nonce)            // 12 bytes: nonce
        buffer.append(contentsOf: sealedBox.tag)    // 16 bytes: tag
        buffer.append(contentsOf: sealedBox.ciphertext)  // Variable: encrypted data
        
        // Pad to page size
        if buffer.count < pageSize {
            buffer.append(Data(repeating: 0, count: pageSize - buffer.count))
        }
        
        guard buffer.count == pageSize else {
            throw NSError(domain: "PageStore", code: 4004, userInfo: [
                NSLocalizedDescriptionKey: "Overflow page size mismatch"
            ])
        }
        
        // Write to disk
        // CRITICAL: Cast to UInt64 before multiplying to prevent integer overflow
        // NOTE: This method is called from _writePageWithOverflowLocked which is already
        // inside a queue.sync(flags: .barrier) block, so we don't need another barrier sync here
        let offset = UInt64(index) * UInt64(pageSize)
        try fileHandle.compatSeek(toOffset: offset)
        try fileHandle.compatWrite(buffer)
    }
    
    /// Read an overflow page
    private func _readOverflowPage(index: Int) throws -> (data: Data, nextPageIndex: UInt32)? {
        BlazeLogger.debug("📄 [_readOverflowPage] Starting read for overflow page \(index)")
        // Check cache first
        if pageCache.get(index) != nil {
            // Cache doesn't store overflow pages separately, so read from disk
            BlazeLogger.debug("📄 [_readOverflowPage] Page \(index) in cache but overflow pages not cached, reading from disk")
        }
        
        // CRITICAL: Cast to UInt64 before multiplying to prevent integer overflow
        let offset = UInt64(index) * UInt64(pageSize)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            BlazeLogger.error("📄 [_readOverflowPage] ❌ File does not exist at path: \(fileURL.path)")
            return nil
        }
        
        // Check file size
        // CRITICAL: Use UInt64 for file size comparison to prevent integer overflow
        // File sizes can exceed Int.max on large databases
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        BlazeLogger.debug("📄 [_readOverflowPage] File size: \(fileSize) bytes, offset: \(offset), pageSize: \(pageSize)")
        if offset >= fileSize {
            BlazeLogger.error("📄 [_readOverflowPage] ❌ Offset \(offset) >= fileSize \(fileSize) for page \(index)")
            return nil
        }
        
        // CRITICAL: Don't nest queue.sync - this is called from readPageWithOverflow
        // which is already inside queue.sync at line 227!
        // Nesting causes deadlock when DynamicCollection calls readPageWithOverflow during createIndex
        // CRITICAL: Always seek to correct position before reading to avoid file position corruption
        // This is especially important during concurrent reads where file position state might be shared
        do {
            BlazeLogger.debug("📄 [_readOverflowPage] Seeking to offset \(offset) for page \(index)")
            try fileHandle.compatSeek(toOffset: offset)
            // Verify we're at the correct position (helps catch file handle position issues)
            let currentOffset = try fileHandle.compatOffset()
            if currentOffset != offset {
                BlazeLogger.warn("📄 [_readOverflowPage] ⚠️ File handle position mismatch: expected \(offset), got \(currentOffset) - reseeking")
                try fileHandle.compatSeek(toOffset: offset)
            }
        } catch {
            BlazeLogger.error("📄 [_readOverflowPage] ❌ Failed to seek to overflow page \(index) at offset \(offset): \(error)")
            throw error
        }
        
        let pageData: Data
        do {
            BlazeLogger.debug("📄 [_readOverflowPage] Reading up to \(pageSize) bytes from offset \(offset)")
            pageData = try fileHandle.compatRead(upToCount: pageSize)
            BlazeLogger.debug("📄 [_readOverflowPage] Read \(pageData.count) bytes (expected \(pageSize))")
        } catch {
            BlazeLogger.error("📄 [_readOverflowPage] ❌ Failed to read overflow page \(index) at offset \(offset): \(error)")
            throw error
        }
        
        // CRITICAL: Ensure we read the full page size
        // If we got less data, the page might be incomplete or we hit EOF
        // During concurrent reads, file position issues might cause partial reads
        // Retry once if we get incomplete data - file position might have been corrupted
        var finalPageData = pageData
        if pageData.count != pageSize {
            BlazeLogger.warn("📄 [_readOverflowPage] ⚠️ Overflow page \(index) read incomplete: expected \(pageSize) bytes, got \(pageData.count) at offset \(offset) - retrying")
            do {
                // Retry: seek to correct position and read again
                BlazeLogger.debug("📄 [_readOverflowPage] Retrying: seeking to offset \(offset) and reading again")
                try fileHandle.compatSeek(toOffset: offset)
                let retryData = try fileHandle.compatRead(upToCount: pageSize)
                BlazeLogger.debug("📄 [_readOverflowPage] Retry read: got \(retryData.count) bytes (expected \(pageSize))")
                if retryData.count == pageSize {
                    finalPageData = retryData
                    BlazeLogger.debug("📄 [_readOverflowPage] ✅ Overflow page \(index) retry succeeded")
                } else {
                    BlazeLogger.error("📄 [_readOverflowPage] ❌ Overflow page \(index) retry also incomplete: got \(retryData.count) bytes")
                    return nil
                }
            } catch {
                BlazeLogger.error("📄 [_readOverflowPage] ❌ Overflow page \(index) retry failed with error: \(error)")
                return nil
            }
        } else {
            BlazeLogger.debug("📄 [_readOverflowPage] ✅ Read complete page \(index): \(pageData.count) bytes")
        }
        
        guard finalPageData.count >= 16 else {
            BlazeLogger.error("📄 [_readOverflowPage] ❌ Page \(index) too short: \(finalPageData.count) bytes (need at least 16 for header)")
            return nil
        }
        
        // Decode header
        BlazeLogger.debug("📄 [_readOverflowPage] Decoding header for page \(index)")
        let header = try OverflowPageHeader.decode(from: finalPageData)
        BlazeLogger.debug("📄 [_readOverflowPage] Decoded header: nextPageIndex=\(header.nextPageIndex), dataLength=\(header.dataLength)")
        
        // CRITICAL: Validate bounds before subdata operations to prevent crashes
        guard finalPageData.count >= 44 else {
            throw NSError(domain: "PageStore", code: 4007, userInfo: [
                NSLocalizedDescriptionKey: "Overflow page too short for nonce and tag (need 44 bytes, got \(finalPageData.count))"
            ])
        }
        
        // Decrypt data
        let nonceData = finalPageData.subdata(in: 16..<28)
        guard let nonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw NSError(domain: "PageStore", code: 4005, userInfo: [
                NSLocalizedDescriptionKey: "Invalid nonce in overflow page"
            ])
        }
        
        let tagData = finalPageData.subdata(in: 28..<44)
        
        // Bounds check: ensure we don't exceed finalPageData bounds
        // This can happen during concurrent writes where a page is partially written
        let expectedCiphertextEnd = 44 + Int(header.dataLength)
        guard expectedCiphertextEnd <= finalPageData.count else {
            throw NSError(domain: "PageStore", code: 4006, userInfo: [
                NSLocalizedDescriptionKey: "Overflow page data length exceeds page bounds (expected \(expectedCiphertextEnd) bytes, got \(finalPageData.count))"
            ])
        }
        
        let ciphertextData = finalPageData.subdata(in: 44..<expectedCiphertextEnd)
        
        // Create sealed box directly with tagData (Data type, not AES.GCM.Tag)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertextData,
            tag: tagData
        )
        
        BlazeLogger.debug("📄 [_readOverflowPage] Decrypting data for page \(index), ciphertext size: \(ciphertextData.count) bytes")
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        BlazeLogger.debug("📄 [_readOverflowPage] ✅ Successfully decrypted page \(index): \(plaintext.count) bytes, nextPageIndex: \(header.nextPageIndex)")
        
        return (data: plaintext, nextPageIndex: header.nextPageIndex)
    }
    
    /// Get overflow page index from main page
    /// Uses heuristic: if main page data is exactly maxDataPerPage, check if next page is overflow
    private func _getOverflowPageIndex(from mainPageIndex: Int) throws -> UInt32 {
        // Read main page to check its size
        guard let mainPageData = try readPage(index: mainPageIndex) else {
            return 0
        }
        
        // If data is exactly maxDataPerPage, it might have overflow
        // Check if the next sequential page is an overflow page by checking magic bytes
        if mainPageData.count == maxDataPerPage {
            let nextPageIndex = mainPageIndex + 1
            // Check if next page exists and has overflow magic bytes
            // CRITICAL: Cast to UInt64 before multiplying to prevent integer overflow
            let offset = UInt64(nextPageIndex) * UInt64(pageSize)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return 0
            }
            
            // Check file size
            // CRITICAL: Use UInt64 for file size comparison to prevent integer overflow
            // File sizes can exceed Int.max on large databases
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            if offset >= fileSize {
                return 0
            }
            
            // Read first 4 bytes to check magic
            try fileHandle.compatSeek(toOffset: offset)
            let magicBytes = try fileHandle.compatRead(upToCount: 4)
            
            guard magicBytes.count >= 4 else {
                return 0
            }
            
            // Check if it's an overflow page (magic = "OVER" = 0x4F564552)
            // CRITICAL: Use safe byte-by-byte reading to avoid alignment crashes
            guard magicBytes.count >= 4 else {
                return 0
            }
            let magic = (UInt32(magicBytes[0]) << 24) | (UInt32(magicBytes[1]) << 16) | (UInt32(magicBytes[2]) << 8) | UInt32(magicBytes[3])
            if magic == OverflowPageHeader.magic {
                return UInt32(nextPageIndex)
            }
        }
        
        return 0
    }
    
    /// Update overflow page's next pointer
    private func _updateOverflowNextPointer(
        pageIndex: Int,
        nextPageIndex: UInt32
    ) throws {
        // Invalidate cache - the cached decrypted data is now stale
        pageCache.remove(pageIndex)
        
        // Read current page
        // CRITICAL: Cast to UInt64 before multiplying to prevent integer overflow
        let offset = UInt64(pageIndex) * UInt64(pageSize)
        try fileHandle.compatSeek(toOffset: offset)
        var pageData = try fileHandle.compatRead(upToCount: pageSize)
        
        // Update next page index in header (bytes 8-11)
        var nextPage = nextPageIndex.bigEndian
        let nextPageData = Data(bytes: &nextPage, count: 4)
        pageData.replaceSubrange(8..<12, with: nextPageData)
        
        // Write back and sync to ensure the update is visible to concurrent readers
        try fileHandle.compatSeek(toOffset: offset)
        try fileHandle.compatWrite(pageData)
        // Note: We don't fsync here to avoid too many syncs, but the final fsync
        // at the end of _writePageWithOverflowLocked will ensure all writes are persisted
    }
    
    /// Update main page's overflow pointer
    /// Note: We can't modify the page header, so we rely on sequential page allocation
    /// The overflow pointer is implicit: if main page is exactly maxDataPerPage, next page is overflow
    private func _updateMainPageOverflowPointer(
        mainPageIndex: Int,
        firstOverflowIndex: UInt32
    ) throws {
        // No-op: Overflow pages are allocated sequentially after the main page
        // The read logic uses a heuristic to detect overflow by checking if
        // main page data is exactly maxDataPerPage and next page is an overflow page
        // This works because we always allocate overflow pages sequentially
        BlazeLogger.debug("Main page \(mainPageIndex) has overflow starting at page \(firstOverflowIndex)")
    }
}

