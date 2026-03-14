import Foundation
#if canImport(zlib)
import zlib
#endif

// MARK: - WALOperation

/// Operation types for WAL entries.
public enum WALOperation: UInt8, Sendable, Equatable {
    case begin      = 0
    case write      = 1
    case delete     = 2
    case commit     = 3
    case abort      = 4
    case checkpoint = 5
}

// MARK: - WALError

/// Errors that can occur during WAL entry serialization/deserialization.
public enum WALError: Error, Sendable {
    case invalidMagic
    case truncatedEntry
    case unknownOperation(UInt8)
    case crcMismatch(expected: UInt32, actual: UInt32)
    case midLogCorruption
    case recoveryFailed(String)
}

// MARK: - WALEntry

/// A single entry in the write-ahead log.
///
/// Binary format:
/// ```
/// [magic 4B "WALV"] [lsn UInt64 LE] [txID 16B] [op UInt8]
/// [pageIndex UInt32 LE] [payloadLen UInt32 LE] [payload] [crc32 UInt32 LE]
/// ```
public struct WALEntry: Sendable, Equatable {

    /// Size of the fixed header before the variable-length payload.
    /// magic(4) + lsn(8) + txID(16) + op(1) + pageIndex(4) + payloadLen(4) = 37
    public static let headerSize: Int = 37

    /// Size of the CRC32 trailer.
    public static let trailerSize: Int = 4

    /// Magic bytes identifying a WAL entry.
    private static let magic: [UInt8] = [0x57, 0x41, 0x4C, 0x56] // "WALV"

    public let lsn: UInt64
    public let transactionID: UUID
    public let operation: WALOperation
    public let pageIndex: UInt32
    public let payload: Data

    public init(lsn: UInt64, transactionID: UUID, operation: WALOperation, pageIndex: UInt32, payload: Data) {
        self.lsn = lsn
        self.transactionID = transactionID
        self.operation = operation
        self.pageIndex = pageIndex
        self.payload = payload
    }

    /// Total size of this entry when serialized.
    public var serializedSize: Int {
        Self.headerSize + payload.count + Self.trailerSize
    }

    // MARK: - Serialize

    public func serialize() -> Data {
        var data = Data(capacity: serializedSize)

        // Magic
        data.append(contentsOf: Self.magic)

        // LSN (UInt64 LE)
        var lsnLE = lsn.littleEndian
        data.append(Data(bytes: &lsnLE, count: 8))

        // Transaction ID (16 bytes, UUID)
        let uuid = transactionID.uuid
        data.append(contentsOf: [
            uuid.0, uuid.1, uuid.2, uuid.3,
            uuid.4, uuid.5, uuid.6, uuid.7,
            uuid.8, uuid.9, uuid.10, uuid.11,
            uuid.12, uuid.13, uuid.14, uuid.15
        ])

        // Operation (UInt8)
        data.append(operation.rawValue)

        // Page index (UInt32 LE)
        var pageLE = pageIndex.littleEndian
        data.append(Data(bytes: &pageLE, count: 4))

        // Payload length (UInt32 LE)
        var lenLE = UInt32(payload.count).littleEndian
        data.append(Data(bytes: &lenLE, count: 4))

        // Payload
        data.append(payload)

        // CRC32 over everything before the checksum
        let crc = Self.computeCRC32(data)
        var crcLE = crc.littleEndian
        data.append(Data(bytes: &crcLE, count: 4))

        return data
    }

    // MARK: - Deserialize

    public static func deserialize(from data: Data) throws -> WALEntry {
        let (entry, _) = try readNext(from: data, at: data.startIndex)
        return entry
    }

    /// Read the next WAL entry from `data` starting at absolute index `offset`.
    /// Returns the decoded entry and the index immediately after it.
    public static func readNext(from data: Data, at offset: Int) throws -> (WALEntry, Int) {
        // Check minimum size for header
        guard data.endIndex - offset >= headerSize + trailerSize else {
            throw WALError.truncatedEntry
        }

        return try data.withUnsafeBytes { buf in
            let base = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let rel = offset - data.startIndex  // relative offset into the buffer

            // Validate magic
            guard base[rel] == magic[0],
                  base[rel + 1] == magic[1],
                  base[rel + 2] == magic[2],
                  base[rel + 3] == magic[3] else {
                throw WALError.invalidMagic
            }

            // LSN
            let lsn = buf.loadUnaligned(fromByteOffset: rel + 4, as: UInt64.self).littleEndian

            // Transaction ID
            let txBytes = (
                base[rel + 12], base[rel + 13], base[rel + 14], base[rel + 15],
                base[rel + 16], base[rel + 17], base[rel + 18], base[rel + 19],
                base[rel + 20], base[rel + 21], base[rel + 22], base[rel + 23],
                base[rel + 24], base[rel + 25], base[rel + 26], base[rel + 27]
            )
            let transactionID = UUID(uuid: txBytes)

            // Operation
            let opRaw = base[rel + 28]
            guard let operation = WALOperation(rawValue: opRaw) else {
                throw WALError.unknownOperation(opRaw)
            }

            // Page index
            let pageIndex = buf.loadUnaligned(fromByteOffset: rel + 29, as: UInt32.self).littleEndian

            // Payload length
            let payloadLen = buf.loadUnaligned(fromByteOffset: rel + 33, as: UInt32.self).littleEndian
            let totalSize = headerSize + Int(payloadLen) + trailerSize

            guard data.endIndex - offset >= totalSize else {
                throw WALError.truncatedEntry
            }

            // Payload
            let payloadStart = offset + headerSize
            let payload = data[payloadStart ..< payloadStart + Int(payloadLen)]

            // CRC32 validation
            let crcOffset = rel + headerSize + Int(payloadLen)
            let storedCRC = buf.loadUnaligned(fromByteOffset: crcOffset, as: UInt32.self).littleEndian

            // Compute CRC over everything except the trailing 4 CRC bytes
            let messageData = data[offset ..< offset + headerSize + Int(payloadLen)]
            let computedCRC = computeCRC32(messageData)

            guard storedCRC == computedCRC else {
                throw WALError.crcMismatch(expected: storedCRC, actual: computedCRC)
            }

            let entry = WALEntry(
                lsn: lsn,
                transactionID: transactionID,
                operation: operation,
                pageIndex: pageIndex,
                payload: Data(payload)
            )

            return (entry, offset + totalSize)
        }
    }

    // MARK: - CRC32

    private static func computeCRC32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buf in
            let bytes = buf.bindMemory(to: UInt8.self)
            let result = zlib.crc32(0, bytes.baseAddress, UInt32(bytes.count))
            return UInt32(result)
        }
    }
}
