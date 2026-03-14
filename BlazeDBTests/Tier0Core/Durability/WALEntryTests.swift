import XCTest
@testable import BlazeDBCore

final class WALEntryTests: XCTestCase {

    func testWriteEntryRoundTrip() throws {
        let entry = WALEntry(
            lsn: 42,
            transactionID: UUID(),
            operation: .write,
            pageIndex: 7,
            payload: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        let data = entry.serialize()
        let decoded = try WALEntry.deserialize(from: data)

        XCTAssertEqual(decoded.lsn, entry.lsn)
        XCTAssertEqual(decoded.transactionID, entry.transactionID)
        XCTAssertEqual(decoded.operation, entry.operation)
        XCTAssertEqual(decoded.pageIndex, entry.pageIndex)
        XCTAssertEqual(decoded.payload, entry.payload)
    }

    func testBeginCommitAbortCheckpointRoundTrip() throws {
        for op in [WALOperation.begin, .commit, .abort, .checkpoint, .delete] {
            let entry = WALEntry(
                lsn: 1,
                transactionID: UUID(),
                operation: op,
                pageIndex: 0,
                payload: Data()
            )
            let data = entry.serialize()
            let decoded = try WALEntry.deserialize(from: data)
            XCTAssertEqual(decoded.operation, op, "Failed for operation: \(op)")
        }
    }

    func testCRC32Validation() throws {
        let entry = WALEntry(
            lsn: 1,
            transactionID: UUID(),
            operation: .write,
            pageIndex: 0,
            payload: Data([0x01, 0x02])
        )
        var data = entry.serialize()
        // Corrupt one byte in the payload region
        let payloadStart = WALEntry.headerSize
        data[payloadStart] ^= 0xFF

        XCTAssertThrowsError(try WALEntry.deserialize(from: data)) { error in
            guard case WALError.crcMismatch = error else {
                XCTFail("Expected crcMismatch, got: \(error)")
                return
            }
        }
    }

    func testTruncatedDataFails() {
        let entry = WALEntry(
            lsn: 1,
            transactionID: UUID(),
            operation: .write,
            pageIndex: 0,
            payload: Data([0x01])
        )
        let data = entry.serialize()
        let truncated = data.prefix(data.count - 5)

        XCTAssertThrowsError(try WALEntry.deserialize(from: Data(truncated)))
    }

    func testReadNextSequential() throws {
        let e1 = WALEntry(lsn: 1, transactionID: UUID(), operation: .write, pageIndex: 0, payload: Data([0xAA]))
        let e2 = WALEntry(lsn: 2, transactionID: UUID(), operation: .commit, pageIndex: 0, payload: Data())
        var log = e1.serialize()
        log.append(e2.serialize())

        let (decoded1, next1) = try WALEntry.readNext(from: log, at: log.startIndex)
        XCTAssertEqual(decoded1.lsn, 1)
        let (decoded2, next2) = try WALEntry.readNext(from: log, at: next1)
        XCTAssertEqual(decoded2.lsn, 2)
        XCTAssertEqual(next2, log.endIndex)
    }

    func testZeroLSNRoundTrip() throws {
        let entry = WALEntry(lsn: 0, transactionID: UUID(), operation: .begin, pageIndex: 0, payload: Data())
        let data = entry.serialize()
        let decoded = try WALEntry.deserialize(from: data)
        XCTAssertEqual(decoded.lsn, 0)
    }
}
