//
//  PageStore+Overflow.swift
//  BlazeDB
//
//  Overflow page support for large records (>4KB)
//  Implements page chains for records that don't fit in a single page
//
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
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

/// Explicit overflow reference trailer embedded in main-page plaintext.
/// This replaces heuristic overflow detection for new writes.
private struct OverflowReferenceV2 {
    static let magic: UInt32 = 0x4F565232 // "OVR2"
    static let version: UInt8 = 0x01
    static let committedFlag: UInt8 = 0x01
    static let encodedSize: Int = 32

    let flags: UInt8
    let firstOverflowPageIndex: UInt32
    let logicalPayloadLength: UInt64
    let payloadChecksum: UInt64
    let chainPageCount: UInt32

    func encode() -> Data {
        var data = Data()
        var magicBE = Self.magic.bigEndian
        data.append(Data(bytes: &magicBE, count: 4))
        data.append(Self.version)
        data.append(flags)
        data.append(contentsOf: [0, 0]) // reserved

        var firstBE = firstOverflowPageIndex.bigEndian
        data.append(Data(bytes: &firstBE, count: 4))

        var lengthBE = logicalPayloadLength.bigEndian
        data.append(Data(bytes: &lengthBE, count: 8))

        var checksumBE = payloadChecksum.bigEndian
        data.append(Data(bytes: &checksumBE, count: 8))

        var pagesBE = chainPageCount.bigEndian
        data.append(Data(bytes: &pagesBE, count: 4))
        return data
    }

    static func decodeIfPresent(from plaintextPageData: Data, maxDataPerPage: Int) -> OverflowReferenceV2? {
        guard plaintextPageData.count == maxDataPerPage, plaintextPageData.count >= encodedSize else {
            return nil
        }
        let start = plaintextPageData.count - encodedSize
        let trailer = plaintextPageData.subdata(in: start..<plaintextPageData.count)
        guard trailer.count == encodedSize else { return nil }

        let magic = (UInt32(trailer[0]) << 24)
            | (UInt32(trailer[1]) << 16)
            | (UInt32(trailer[2]) << 8)
            | UInt32(trailer[3])
        guard magic == Self.magic else { return nil }
        guard trailer[4] == Self.version else { return nil }

        let flags = trailer[5]

        let firstOverflowPageIndex = (UInt32(trailer[8]) << 24)
            | (UInt32(trailer[9]) << 16)
            | (UInt32(trailer[10]) << 8)
            | UInt32(trailer[11])

        var length: UInt64 = 0
        for i in 12..<20 {
            length = (length << 8) | UInt64(trailer[i])
        }

        var checksum: UInt64 = 0
        for i in 20..<28 {
            checksum = (checksum << 8) | UInt64(trailer[i])
        }

        let chainPageCount = (UInt32(trailer[28]) << 24)
            | (UInt32(trailer[29]) << 16)
            | (UInt32(trailer[30]) << 8)
            | UInt32(trailer[31])

        return OverflowReferenceV2(
            flags: flags,
            firstOverflowPageIndex: firstOverflowPageIndex,
            logicalPayloadLength: length,
            payloadChecksum: checksum,
            chainPageCount: chainPageCount
        )
    }
}

public enum OverflowValidationResult: Equatable {
    case valid
    case missingPage(Int)
    case truncatedChain(expectedBytes: Int, actualBytes: Int)
    case cycleDetected(Int)
    case orphanPage(Int)
}

private enum OverflowCrashHook: String {
    case afterBasePageWrite
    case afterFirstOverflowPageWrite
    case afterLastOverflowPageWrite
    case afterOverflowMetadataUpdate
    case afterWALAppendBeforeCommitMark
}

// MARK: - PageStore Overflow Extension

extension PageStore {
    private static func activeOverflowCrashHook() -> OverflowCrashHook? {
        guard let raw = ProcessInfo.processInfo.environment["BLAZEDB_OVERFLOW_CRASH_HOOK"] else {
            return nil
        }
        return OverflowCrashHook(rawValue: raw)
    }

    private static func triggerOverflowCrashIfNeeded(_ hook: OverflowCrashHook) {
        guard activeOverflowCrashHook() == hook else { return }
        let code = Int32(ProcessInfo.processInfo.environment["BLAZEDB_OVERFLOW_CRASH_EXIT_CODE"] ?? "86") ?? 86
        _exit(code)
    }
    
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

    /// Number of overflow corruption incidents before we degrade reads.
    private var overflowCorruptionDegradeThreshold: Int { 16 }

    private func isKnownCorruptedOverflowMainPage(_ index: Int) -> Bool {
        overflowCorruptionLock.lock()
        defer { overflowCorruptionLock.unlock() }
        return knownCorruptedOverflowMainPages.contains(index)
    }

    private func clearKnownCorruptedOverflowMainPage(_ index: Int) {
        overflowCorruptionLock.lock()
        knownCorruptedOverflowMainPages.remove(index)
        overflowCorruptionLock.unlock()
    }

    private func isOverflowReadDegradedModeEnabled() -> Bool {
        overflowCorruptionLock.lock()
        defer { overflowCorruptionLock.unlock() }
        return overflowReadDegradedMode
    }

    private func registerOverflowCorruptionIncident(mainPageIndex: Int, reason: String) {
        overflowCorruptionLock.lock()
        knownCorruptedOverflowMainPages.insert(mainPageIndex)
        overflowCorruptionIncidentCount += 1
        let incidents = overflowCorruptionIncidentCount
        if incidents >= overflowCorruptionDegradeThreshold {
            overflowReadDegradedMode = true
        }
        let degraded = overflowReadDegradedMode
        overflowCorruptionLock.unlock()

        BlazeLogger.error("📖 [readPageWithOverflow] ❌ Overflow corruption on main page \(mainPageIndex): \(reason)")
        if degraded {
            BlazeLogger.warn("📖 [readPageWithOverflow] ⚠️ Overflow read degraded mode active after \(incidents) corruption incidents; skipping overflow traversal for subsequent reads.")
        }
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
        clearKnownCorruptedOverflowMainPage(index)
        
        // Single-page payload: no overflow trailer needed.
        if plaintext.count <= maxDataPerPage {
            try _writePageLocked(index: index, plaintext: plaintext)
            return pageIndices
        }
        
        // Data doesn't fit - need overflow pages
        BlazeLogger.debug("Writing large record (\(plaintext.count) bytes) with overflow pages")
        
        // Reserve explicit v2 trailer space at end of main page.
        let mainPageDataSize = maxDataPerPage - OverflowReferenceV2.encodedSize
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
            if i == 0 {
                Self.triggerOverflowCrashIfNeeded(.afterFirstOverflowPageWrite)
            }
            if isLastPage {
                Self.triggerOverflowCrashIfNeeded(.afterLastOverflowPageWrite)
            }
        }
        BlazeLogger.debug("📝 [writePageWithOverflow] ✅ Completed writing overflow chain: main page \(index) -> first overflow \(firstOverflowIndex)")
        
        // Append explicit overflow reference trailer to main page payload.
        // Chain is considered published only once this main page write succeeds.
        let firstPageDataCopy = Data(firstPageData)
        var mainPageDataWithPointer = firstPageDataCopy
        let payloadChecksum = overflowChecksum64(plaintext)
        guard let chainPageCount = UInt32(exactly: overflowPages.count) else {
            throw NSError(domain: "PageStore", code: 4015, userInfo: [
                NSLocalizedDescriptionKey: "Overflow chain page count exceeds UInt32"
            ])
        }
        let ref = OverflowReferenceV2(
            flags: OverflowReferenceV2.committedFlag,
            firstOverflowPageIndex: firstOverflowIndex,
            logicalPayloadLength: UInt64(plaintext.count),
            payloadChecksum: payloadChecksum,
            chainPageCount: chainPageCount
        )
        mainPageDataWithPointer.append(ref.encode())
        Self.triggerOverflowCrashIfNeeded(.afterOverflowMetadataUpdate)
        
        // Write main page with overflow pointer embedded
        try _writePageLocked(index: index, plaintext: mainPageDataWithPointer)
        Self.triggerOverflowCrashIfNeeded(.afterBasePageWrite)
        
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
        if isOverflowReadDegradedModeEnabled() {
            // Degraded mode avoids expensive overflow-chain traversal on poisoned stores.
            return try readPage(index: index)
        }
        if isKnownCorruptedOverflowMainPage(index) {
            return nil
        }
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
                let currentFileSize = try self.fileSize()
                guard offset < currentFileSize else {
                    return nil as Data?
                }
                // pread: atomic seek+read, safe for concurrent readers (no shared file offset)
                let pageData = try atomicRead(offset: off_t(offset), count: pageSize)
                
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
            // Prefer explicit v2 reference trailer; only fall back to legacy pointer heuristic.
            var completeData = mainPageData
            var currentOverflowIndex: UInt32 = 0
            var expectedTotalBytes: Int?
            var expectedChecksum: UInt64?
            var expectedChainPages: Int?
            var mainPayloadBytes = mainPageData.count
            var usingLegacyOverflowReference = false

            if let ref = OverflowReferenceV2.decodeIfPresent(from: mainPageData, maxDataPerPage: maxDataPerPage) {
                guard (ref.flags & OverflowReferenceV2.committedFlag) != 0 else {
                    registerOverflowCorruptionIncident(
                        mainPageIndex: index,
                        reason: "v2 overflow reference not committed"
                    )
                    throw BlazeDBError.corruptedData(
                        location: "overflow-chain/main:\(index)",
                        reason: "overflowRefV2 not committed"
                    )
                }

                guard ref.logicalPayloadLength <= UInt64(Int.max) else {
                    registerOverflowCorruptionIncident(
                        mainPageIndex: index,
                        reason: "v2 logical payload length exceeds Int.max: \(ref.logicalPayloadLength)"
                    )
                    throw BlazeDBError.corruptedData(
                        location: "overflow-chain/main:\(index)",
                        reason: "overflowRefV2 logical length out of bounds"
                    )
                }

                mainPayloadBytes = maxDataPerPage - OverflowReferenceV2.encodedSize
                completeData = Data(mainPageData.prefix(mainPayloadBytes))
                currentOverflowIndex = ref.firstOverflowPageIndex
                expectedTotalBytes = Int(ref.logicalPayloadLength)
                expectedChecksum = ref.payloadChecksum
                expectedChainPages = Int(ref.chainPageCount)
            }
            
            // If main page data is exactly maxDataPerPage, check if last 4 bytes are overflow pointer
            // CRITICAL: Validate bounds before accessing last 4 bytes
            // IMPORTANT: Only check for overflow if the data is exactly maxDataPerPage AND
            // the potential pointer points to a valid overflow page (has "OVER" magic bytes)
            BlazeLogger.debug("📖 [readPageWithOverflow] Main page data size: \(mainPageData.count), maxDataPerPage: \(maxDataPerPage)")
            if currentOverflowIndex == 0
                && legacyOverflowPointerHeuristicCompatibilityMode
                && mainPageData.count == maxDataPerPage
                && mainPageData.count >= 4
            {
                usingLegacyOverflowReference = true
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
                        mainPayloadBytes = maxDataPerPage - 4
                        completeData = Data(mainPageData.prefix(mainPayloadBytes))
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
                            registerOverflowCorruptionIncident(
                                mainPageIndex: index,
                                reason: "missing overflow page \(currentIndex) after chain start \(initialOverflowIndex)"
                            )
                            throw BlazeDBError.corruptedData(
                                location: "overflow-chain/main:\(index)",
                                reason: "truncatedOverflowChain missing page \(currentIndex) after start \(initialOverflowIndex)"
                            )
                        }
                        BlazeLogger.warn("📖 [readPageWithOverflow] ⚠️ Overflow page \(currentIndex) missing or corrupted - stopping chain. Total data so far: \(completeData.count) bytes")
                        break
                    }
                    BlazeLogger.debug("📖 [readPageWithOverflow] ✅ Successfully read overflow page \(currentIndex): \(overflowData.data.count) bytes, nextPageIndex: \(overflowData.nextPageIndex)")
                    
                    completeData.append(overflowData.data)
                    BlazeLogger.debug("📖 [readPageWithOverflow] Total data after page \(currentIndex): \(completeData.count) bytes (main: \(mainPayloadBytes), overflow: \(completeData.count - mainPayloadBytes))")
                    
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
                        registerOverflowCorruptionIncident(
                            mainPageIndex: index,
                            reason: "failed reading overflow page \(currentIndex): \(error.localizedDescription)"
                        )
                        throw BlazeDBError.corruptedData(
                            location: "overflow-chain/main:\(index)",
                            reason: "truncatedOverflowChain failed reading page \(currentIndex): \(error.localizedDescription)"
                        )
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
                registerOverflowCorruptionIncident(
                    mainPageIndex: index,
                    reason: "circular overflow chain starting at \(initialOverflowIndex)"
                )
                throw BlazeDBError.corruptedData(
                    location: "overflow-chain/main:\(index)",
                    reason: "circular overflow chain starting at \(initialOverflowIndex)"
                )
            }
            
            // If chain length limit was hit, also return nil for safety
            if chainLength >= maxChainLength && currentOverflowIndex > 0 {
                registerOverflowCorruptionIncident(
                    mainPageIndex: index,
                    reason: "overflow chain length limit reached (\(maxChainLength))"
                )
                throw BlazeDBError.corruptedData(
                    location: "overflow-chain/main:\(index)",
                    reason: "overflow chain length limit reached (\(maxChainLength))"
                )
            }
            
            let overflowDataSize = completeData.count - mainPayloadBytes
            BlazeLogger.debug("📖 [readPageWithOverflow] ✅ Successfully read complete page \(index) with overflow chain: \(completeData.count) bytes total (main: \(mainPayloadBytes), overflow: \(overflowDataSize) from \(chainLength) pages, initialOverflowIndex: \(initialOverflowIndex))")
            
            // CRITICAL: If we expected an overflow chain but got incomplete data, return nil
            // We should only return completeData if:
            // 1. No overflow chain was expected (initialOverflowIndex == 0), OR
            // 2. Overflow chain was expected and we reached the end (currentOverflowIndex == 0)
            // If we expected a chain but currentOverflowIndex > 0, the chain is incomplete
            if initialOverflowIndex > 0 && currentOverflowIndex > 0 && !detectedCircularReference {
                // We expected an overflow chain but didn't reach the end (currentOverflowIndex > 0 means more pages expected)
                // This indicates an incomplete chain - return nil to allow retry
                registerOverflowCorruptionIncident(
                    mainPageIndex: index,
                    reason: "incomplete chain: stopped with nextPageIndex=\(currentOverflowIndex), start=\(initialOverflowIndex)"
                )
                throw BlazeDBError.corruptedData(
                    location: "overflow-chain/main:\(index)",
                    reason: "truncatedOverflowChain stopped with nextPageIndex=\(currentOverflowIndex), start=\(initialOverflowIndex)"
                )
            }
            
            // CRITICAL: If we expected an overflow chain but got incomplete data, validate the size
            // For a 10KB record, we should have at least main page + overflow pages
            // If we expected an overflow chain but chainLength is 0, we likely didn't read the chain
            if initialOverflowIndex > 0 && currentOverflowIndex == 0 && chainLength == 0 {
                // We expected an overflow chain but didn't read any overflow pages
                // This means the chain read failed - return nil to allow retry
                registerOverflowCorruptionIncident(
                    mainPageIndex: index,
                    reason: "overflow pointer present (\(initialOverflowIndex)) but zero overflow pages read"
                )
                throw BlazeDBError.corruptedData(
                    location: "overflow-chain/main:\(index)",
                    reason: "truncatedOverflowChain pointer \(initialOverflowIndex) but zero pages read"
                )
            }
            
            // CRITICAL: Additional validation - overflow chain must contribute at least one byte.
            // We intentionally DO NOT require a full overflow-page worth of data. Valid records
            // can spill only a few bytes beyond the main page.
            if initialOverflowIndex > 0 && chainLength > 0 {
                let overflowDataSize = completeData.count - mainPayloadBytes
                if overflowDataSize <= 0 {
                    registerOverflowCorruptionIncident(
                        mainPageIndex: index,
                        reason: "incomplete chain: zero overflow payload bytes, chainLength=\(chainLength)"
                    )
                    throw BlazeDBError.corruptedData(
                        location: "overflow-chain/main:\(index)",
                        reason: "truncatedOverflowChain zero overflow payload, chainLength=\(chainLength)"
                    )
                }
            }

            // v2 contract validations: length, checksum, and chain page count.
            if let expectedPages = expectedChainPages, initialOverflowIndex > 0, chainLength != expectedPages {
                registerOverflowCorruptionIncident(
                    mainPageIndex: index,
                    reason: "overflowRefV2 chain page count mismatch expected=\(expectedPages), actual=\(chainLength)"
                )
                throw BlazeDBError.corruptedData(
                    location: "overflow-chain/main:\(index)",
                    reason: "overflowRefV2 chain page count mismatch expected=\(expectedPages), actual=\(chainLength)"
                )
            }
            if let expectedBytes = expectedTotalBytes, completeData.count != expectedBytes {
                registerOverflowCorruptionIncident(
                    mainPageIndex: index,
                    reason: "overflowRefV2 logical length mismatch expected=\(expectedBytes), actual=\(completeData.count)"
                )
                throw BlazeDBError.corruptedData(
                    location: "overflow-chain/main:\(index)",
                    reason: "overflowRefV2 logical length mismatch expected=\(expectedBytes), actual=\(completeData.count)"
                )
            }
            if let checksum = expectedChecksum {
                let actualChecksum = overflowChecksum64(completeData)
                if checksum != actualChecksum {
                    registerOverflowCorruptionIncident(
                        mainPageIndex: index,
                        reason: "overflowRefV2 checksum mismatch expected=\(checksum), actual=\(actualChecksum)"
                    )
                    throw BlazeDBError.corruptedData(
                        location: "overflow-chain/main:\(index)",
                        reason: "overflowRefV2 checksum mismatch expected=\(checksum), actual=\(actualChecksum)"
                    )
                }
            }

            // Legacy heuristic path is compatibility-mode only.
            if usingLegacyOverflowReference {
                BlazeLogger.trace("📖 [readPageWithOverflow] Legacy overflow heuristic path used for page \(index)")
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
        let offset = off_t(index) * off_t(pageSize)
        try atomicWrite(offset: offset, data: buffer)
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
        let offset = off_t(index) * off_t(pageSize)

        // Check file size using fstat (no FileManager, no shared state)
        let currentFileSize = try self.fileSize()
        BlazeLogger.debug("📄 [_readOverflowPage] File size: \(currentFileSize) bytes, offset: \(offset), pageSize: \(pageSize)")
        if offset >= currentFileSize {
            BlazeLogger.error("📄 [_readOverflowPage] ❌ Offset \(offset) >= fileSize \(currentFileSize) for page \(index)")
            return nil
        }

        // pread: atomic seek+read, safe for concurrent readers (no shared file offset)
        let pageData: Data
        do {
            BlazeLogger.debug("📄 [_readOverflowPage] Reading \(pageSize) bytes at offset \(offset) via pread")
            pageData = try atomicRead(offset: offset, count: pageSize)
            BlazeLogger.debug("📄 [_readOverflowPage] Read \(pageData.count) bytes (expected \(pageSize))")
        } catch {
            BlazeLogger.error("📄 [_readOverflowPage] ❌ Failed to read overflow page \(index) at offset \(offset): \(error)")
            throw error
        }

        // Check if we got a short read (hit EOF — not a seek race with pread)
        let finalPageData: Data
        if pageData.count != pageSize {
            BlazeLogger.warn("📄 [_readOverflowPage] ⚠️ Overflow page \(index) short read: expected \(pageSize) bytes, got \(pageData.count) at offset \(offset)")
            // With pread, a short read means we actually hit EOF — no retry will help
            return nil
        } else {
            finalPageData = pageData
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
        
        // Bounds check: remain defensive on UInt32→Int and claims larger than the physical page payload
        let payloadCap = finalPageData.count - 44
        guard payloadCap >= 0 else {
            throw NSError(domain: "PageStore", code: 4006, userInfo: [
                NSLocalizedDescriptionKey: "Overflow page negative payload capacity"
            ])
        }
        guard UInt64(header.dataLength) <= UInt64(payloadCap) else {
            throw NSError(domain: "PageStore", code: 4006, userInfo: [
                NSLocalizedDescriptionKey: "Overflow page dataLength \(header.dataLength) exceeds available ciphertext (\(payloadCap) bytes)"
            ])
        }
        let ciphertextByteCount = Int(header.dataLength)
        let expectedCiphertextEnd = 44 + ciphertextByteCount
        guard expectedCiphertextEnd <= finalPageData.count else {
            throw NSError(domain: "PageStore", code: 4006, userInfo: [
                NSLocalizedDescriptionKey: "Overflow page ciphertext end \(expectedCiphertextEnd) exceeds page size \(finalPageData.count)"
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
        guard legacyOverflowPointerHeuristicCompatibilityMode else {
            return 0
        }
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
            
            // Check file size using fstat
            let currentFileSize = try self.fileSize()
            if offset >= currentFileSize {
                return 0
            }

            // Read first 4 bytes to check magic (pread — no shared seek state)
            let magicBytes = try atomicRead(offset: off_t(offset), count: 4)
            
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
        let offset = off_t(pageIndex) * off_t(pageSize)
        var pageData = try atomicRead(offset: offset, count: pageSize)

        // Update next page index in header (bytes 8-11)
        var nextPage = nextPageIndex.bigEndian
        let nextPageData = Data(bytes: &nextPage, count: 4)
        pageData.replaceSubrange(8..<12, with: nextPageData)

        // Write back using pwrite (no shared seek state)
        try atomicWrite(offset: offset, data: pageData)
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

    /// Deterministic overflow chain validator for corruption harnesses.
    public func validateOverflowChain(rootPageID: Int) -> OverflowValidationResult {
        let mainData: Data
        do {
            guard let data = try readPage(index: rootPageID) else {
                return .missingPage(rootPageID)
            }
            mainData = data
        } catch {
            return .missingPage(rootPageID)
        }

        var pointer: UInt32 = 0
        var bytesRead = mainData.count
        var expectedBytes: Int?
        var expectedChecksum: UInt64?
        var expectedPageCount: Int?

        if let ref = OverflowReferenceV2.decodeIfPresent(from: mainData, maxDataPerPage: maxDataPerPage) {
            guard (ref.flags & OverflowReferenceV2.committedFlag) != 0 else {
                return .truncatedChain(expectedBytes: Int(ref.logicalPayloadLength), actualBytes: 0)
            }
            pointer = ref.firstOverflowPageIndex
            bytesRead = maxDataPerPage - OverflowReferenceV2.encodedSize
            expectedBytes = Int(ref.logicalPayloadLength)
            expectedChecksum = ref.payloadChecksum
            expectedPageCount = Int(ref.chainPageCount)
        } else {
            guard legacyOverflowPointerHeuristicCompatibilityMode else { return .valid }
            let hasPointer = mainData.count == maxDataPerPage && mainData.count >= 4
            guard hasPointer else { return .valid }
            let offset = mainData.count - 4
            pointer = (UInt32(mainData[offset]) << 24)
                | (UInt32(mainData[offset + 1]) << 16)
                | (UInt32(mainData[offset + 2]) << 8)
                | UInt32(mainData[offset + 3])
            guard pointer > 0 else { return .valid }
            bytesRead = maxDataPerPage - 4
        }

        var visited = Set<Int>()
        var current = pointer
        var chainLength = 0
        var completeData = Data(mainData.prefix(bytesRead))
        let maxChainHops = 10_000
        while current > 0 {
            if chainLength >= maxChainHops {
                return .truncatedChain(expectedBytes: bytesRead + 1, actualBytes: bytesRead)
            }
            let index = Int(current)
            if visited.contains(index) {
                return .cycleDetected(index)
            }
            visited.insert(index)
            chainLength += 1
            do {
                guard let next = try _readOverflowPage(index: index) else {
                    return .truncatedChain(expectedBytes: bytesRead + 1, actualBytes: bytesRead)
                }
                bytesRead += next.data.count
                completeData.append(next.data)
                current = next.nextPageIndex
            } catch {
                return .truncatedChain(expectedBytes: bytesRead + 1, actualBytes: bytesRead)
            }
        }

        if let expectedPageCount, chainLength != expectedPageCount {
            return .truncatedChain(expectedBytes: expectedPageCount, actualBytes: chainLength)
        }
        if let expectedBytes, expectedBytes != bytesRead {
            return .truncatedChain(expectedBytes: expectedBytes, actualBytes: bytesRead)
        }
        if let expectedChecksum, overflowChecksum64(completeData) != expectedChecksum {
            return .truncatedChain(expectedBytes: bytesRead, actualBytes: bytesRead - 1)
        }

        return .valid
    }

    /// Scan file for overflow pages unreachable from any main-page root pointer.
    public func scanForOrphanOverflowPages() -> [Int] {
        guard let currentFileSize = try? self.fileSize() else { return [] }
        let totalPages = currentFileSize / pageSize
        guard totalPages > 0 else { return [] }

        var allOverflowPages = Set<Int>()
        for i in 0..<totalPages {
            let offset = off_t(i) * off_t(pageSize)
            do {
                let header = try atomicRead(offset: offset, count: 4)
                if header.count == 4 {
                    let magic = (UInt32(header[0]) << 24)
                        | (UInt32(header[1]) << 16)
                        | (UInt32(header[2]) << 8)
                        | UInt32(header[3])
                    if magic == OverflowPageHeader.magic {
                        allOverflowPages.insert(i)
                    }
                }
            } catch {
                continue
            }
        }

        var reachableOverflowPages = Set<Int>()
        for root in 0..<totalPages {
            guard let main = (try? readPage(index: root)) ?? nil else { continue }

            var pointer: UInt32 = 0
            if let ref = OverflowReferenceV2.decodeIfPresent(from: main, maxDataPerPage: maxDataPerPage) {
                pointer = ref.firstOverflowPageIndex
            } else if legacyOverflowPointerHeuristicCompatibilityMode, main.count == maxDataPerPage, main.count >= 4 {
                let offset = main.count - 4
                pointer = (UInt32(main[offset]) << 24)
                    | (UInt32(main[offset + 1]) << 16)
                    | (UInt32(main[offset + 2]) << 8)
                    | UInt32(main[offset + 3])
            } else {
                continue
            }
            var seen = Set<Int>()
            var hops = 0
            let maxOrphanWalk = 10_000
            while pointer > 0 && hops < maxOrphanWalk {
                hops += 1
                let idx = Int(pointer)
                if seen.contains(idx) { break }
                seen.insert(idx)
                reachableOverflowPages.insert(idx)
                guard let page = (try? _readOverflowPage(index: idx)) ?? nil else { break }
                pointer = page.nextPageIndex
            }
        }

        return allOverflowPages.subtracting(reachableOverflowPages).sorted()
    }

    /// Fast non-cryptographic checksum for overflow payload integrity validation.
    private func overflowChecksum64(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}

