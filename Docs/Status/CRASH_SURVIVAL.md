# BlazeDB Crash Survival Validation

**Date:** 2025-01-22  
**Status:** Phase 1 Complete

---

## Overview

BlazeDB is designed to survive crashes, power loss, and unclean shutdowns without data corruption. This document validates crash survival mechanisms and provides instructions for reproducing crash scenarios.

---

## Crash Survival Mechanisms

### 1. Write-Ahead Logging (WAL)

**Purpose:** Ensures committed writes survive crashes.

**How it works:**
- All writes go to WAL first (fast, sequential)
- WAL is flushed to disk before acknowledging writes
- On recovery, WAL is replayed to restore committed state

**Code:** `BlazeDB/Storage/WriteAheadLog.swift`, `BlazeDB/Exports/BlazeDBClient.swift:replayTransactionLogIfNeeded()`

### 2. Transaction Log Replay

**Purpose:** Replays uncommitted operations after crash.

**How it works:**
- Transaction log records all operations
- On startup, log is replayed
- Uncommitted transactions are rolled back

**Code:** `BlazeDB/Transactions/TransactionLog.swift`

### 3. Metadata Rebuild

**Purpose:** Recovers from metadata corruption.

**How it works:**
- If metadata file is corrupted, rebuild from data pages
- Scan all pages to reconstruct index map
- Verify integrity checksums

**Code:** `BlazeDB/Storage/StorageLayout.swift:rebuild(from:)`

---

## Crash Scenarios Tested

### 1. Power Loss During Writes

**Scenario:** Process is killed mid-write operation.

**Test:** `CrashSurvivalTests.testPowerLoss_AllCommittedDataSurvives()`

**Expected Behavior:**
- All committed writes survive
- No partial records
- Database opens successfully
- Health status is OK

**How to Reproduce:**
```bash
cd Tests/CrashRecoveryHarness
./crash_test.sh
```

### 2. Crash During Transaction

**Scenario:** Process crashes before transaction commit.

**Test:** `CrashSurvivalTests.testCrashDuringTransaction_UncommittedDataRolledBack()`

**Expected Behavior:**
- Committed data survives
- Uncommitted data is rolled back
- No partial transaction state

### 3. Crash Before Close

**Scenario:** Process terminates without calling `close()`.

**Test:** `CrashSurvivalTests.testCrashRecovery_HealthStatusValid()`

**Expected Behavior:**
- All persisted data survives
- Database opens cleanly
- Health status is valid (OK or WARN, never ERROR)

### 4. WAL Replay Correctness

**Scenario:** Verify WAL replay doesn't create duplicates.

**Test:** `CrashSurvivalTests.testWALReplay_NoDuplicateRecords()`

**Expected Behavior:**
- No duplicate records after replay
- All original records present
- No corruption

---

## Crash Harness

### Manual Testing

**Build harness:**
```bash
cd Tests/CrashRecoveryHarness
swift build
```

**Run crash test:**
```bash
./crash_test.sh
```

**Run specific crash scenario:**
```bash
.build/debug/CrashHarness <db-path> <operation-count> <crash-point>
```

Where `crash-point` is:
- `none` - Run to completion
- `mid-write` - Crash during write operation
- `mid-transaction` - Crash during transaction
- `before-close` - Crash before close()

### Automated Testing

**Run crash survival tests:**
```bash
swift test --filter CrashSurvivalTests
```

---

## Invariant Validation

After every crash recovery, the following invariants are validated:

1. **Health Status:** `db.health().status` must not be `.error`
2. **Record Count:** Must be non-negative and match expected count
3. **No Corruption:** All records must have expected fields
4. **No Duplicates:** WAL replay must not create duplicate records
5. **Transaction Integrity:** Uncommitted transactions must be rolled back

---

## Known Limitations

1. **Concurrent Writers:** BlazeDB is single-writer. Multiple processes writing to the same database will cause corruption.

2. **Network Filesystems:** NFS, SMB, and other network filesystems may not provide the same durability guarantees as local filesystems.

3. **Hardware Failures:** While BlazeDB survives process crashes, it cannot protect against hardware failures (disk corruption, RAM errors, etc.).

---

## Recovery Performance

**Typical recovery times:**
- Small databases (< 1MB): < 100ms
- Medium databases (1-100MB): 100-500ms
- Large databases (> 100MB): 500ms-2s

Recovery time scales with:
- Number of records
- WAL size
- Disk I/O speed

---

## Verification Commands

**Check database health after crash:**
```swift
let db = try BlazeDBClient(name: "test", fileURL: dbURL, password: "password")
let health = try db.health()
print("Status: \(health.status)")
for reason in health.reasons {
    print("  - \(reason)")
}
```

**Verify record integrity:**
```swift
let count = db.count()
let allRecords = try db.fetchAll()
print("Record count: \(count)")
print("Records fetched: \(allRecords.count)")
```

---

## References

- `BlazeDB/Storage/WriteAheadLog.swift` - WAL implementation
- `BlazeDB/Transactions/TransactionLog.swift` - Transaction logging
- `BlazeDB/Storage/StorageLayout.swift` - Metadata recovery
- `BlazeDBTests/Core/CrashSurvivalTests.swift` - Test suite
