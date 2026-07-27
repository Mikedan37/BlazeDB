//
//  WriteProfileCollectorTests.swift
//  BlazeDB_Tier0
//
//  Opt-in write-path profiler must stay silent when disabled and record
//  explicit stages + counters when BLAZEDB_WRITE_PROFILE=1.
//

import XCTest
@testable import BlazeDBCore

final class WriteProfileCollectorTests: XCTestCase {
    override func tearDown() {
        unsetenv("BLAZEDB_WRITE_PROFILE")
        WriteProfileCollector.reset()
        super.tearDown()
    }

    func testDisabledCollectorRecordsNothing() throws {
        unsetenv("BLAZEDB_WRITE_PROFILE")
        WriteProfileCollector.reset()
        WriteProfileCollector.measure("encode") {
            // no-op
        }
        WriteProfileCollector.addBytes(1024)
        WriteProfileCollector.addSyscall(kind: .fsync)
        XCTAssertTrue(WriteProfileCollector.snapshot().spans.isEmpty)
        XCTAssertEqual(WriteProfileCollector.snapshot().bytesWritten, 0)
        XCTAssertEqual(WriteProfileCollector.snapshot().syscallCounts[.fsync] ?? 0, 0)
    }

    func testEnabledCollectorRecordsStagesBytesAndSyscalls() throws {
        setenv("BLAZEDB_WRITE_PROFILE", "1", 1)
        WriteProfileCollector.reset()
        WriteProfileCollector.beginOperation(
            WriteProfileOperation(
                path: .singleInsert,
                batchSize: 1,
                durabilityMode: "default_wal",
                recordBytes: 64,
                steadyState: false
            )
        )
        WriteProfileCollector.measure("encode") {
            Thread.sleep(forTimeInterval: 0.001)
        }
        WriteProfileCollector.addBytes(128)
        WriteProfileCollector.addSyscall(kind: .write)
        WriteProfileCollector.addSyscall(kind: .fsync)
        WriteProfileCollector.endOperation()

        let snap = WriteProfileCollector.snapshot()
        XCTAssertEqual(snap.operations.count, 1)
        XCTAssertEqual(snap.operations[0].path, .singleInsert)
        XCTAssertEqual(snap.operations[0].batchSize, 1)
        XCTAssertFalse(snap.operations[0].steadyState)
        XCTAssertFalse(snap.spans.isEmpty)
        XCTAssertEqual(snap.spans.first?.name, "encode")
        XCTAssertGreaterThan(snap.spans.first?.milliseconds ?? 0, 0)
        XCTAssertEqual(snap.bytesWritten, 128)
        XCTAssertEqual(snap.syscallCounts[.write], 1)
        XCTAssertEqual(snap.syscallCounts[.fsync], 1)
    }

    func testNestedBeginKeepsOuterOperation() throws {
        setenv("BLAZEDB_WRITE_PROFILE", "1", 1)
        WriteProfileCollector.reset()
        WriteProfileCollector.beginOperation(
            WriteProfileOperation(
                path: .transactionPuts,
                batchSize: 3,
                durabilityMode: "client_transaction",
                recordBytes: 8,
                steadyState: false
            )
        )
        WriteProfileCollector.beginOperation(
            WriteProfileOperation(
                path: .singleInsert,
                batchSize: 1,
                durabilityMode: "nested",
                recordBytes: 8,
                steadyState: false
            )
        )
        WriteProfileCollector.measure("encode") {}
        WriteProfileCollector.endOperation()
        let snap = WriteProfileCollector.snapshot()
        XCTAssertEqual(snap.operations.count, 1)
        XCTAssertEqual(snap.operations[0].path, .transactionPuts)
        XCTAssertEqual(snap.operations[0].batchSize, 3)
    }
}
