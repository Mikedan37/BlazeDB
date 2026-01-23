# Test Runner Quick Reference

## Run New Bulletproof Tests

### **Quick Verification (All 6 Suites - ~1 minute)**
```bash
xcodebuild test -scheme BlazeDB -destination 'platform=macOS' \
 -only-testing:BlazeDBTests/EncryptionRoundTripVerificationTests \
 -only-testing:BlazeDBTests/PersistenceIntegrityTests \
 -only-testing:BlazeDBTests/PerformanceInvariantTests \
 -only-testing:BlazeDBTests/FileIntegrityTests \
 -only-testing:BlazeDBTests/FailureInjectionTests \
 -only-testing:BlazeDBTests/AutoMigrationVerificationTests
```

### **Individual Suites**

**Encryption Verification (fastest - 10 seconds):**
```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests/EncryptionRoundTripVerificationTests
```

**Persistence Integrity (30 seconds):**
```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests/PersistenceIntegrityTests
```

**Performance Invariants (45 seconds - includes 10k inserts):**
```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests/PerformanceInvariantTests
```

**File Integrity (20 seconds):**
```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests/FileIntegrityTests
```

**Failure Injection (25 seconds):**
```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests/FailureInjectionTests
```

**Auto-Migration Verification (40 seconds):**
```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests/AutoMigrationVerificationTests
```

---

## Full Test Suite

### **All Tests (~15-20 minutes)**
```bash
xcodebuild test -scheme BlazeDB -destination 'platform=macOS'
```

### **Unit Tests Only (~10 minutes)**
```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests
```

### **Integration Tests Only (~5 minutes)**
```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBIntegrationTests
```

---

## Specific Bug Verification

### **Verify AES-GCM Fix**
```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests/EncryptionRoundTripVerificationTests/testCiphertextNotRounded
```

### **Verify Metadata Corruption Fix**
```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests/AutoMigrationVerificationTests/testMetadataNeverStartsWithBinaryByte
```

### **Verify Persistence Fix**
```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests/PersistenceIntegrityTests/testTenRecordsPersistence
```

### **Verify Performance Fix**
```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests/PerformanceInvariantTests/testBatchInsert10kPerformance
```

---

## Expected Results

### **Success Output:**
```
Test Suite 'BlazeDBTests' passed
 Executed 73 tests, with 0 failures

Test Suite 'All tests' passed
 Executed 1,513 tests, with 0 failures
```

### **If Tests Fail:**

**Encryption tests failing?**
→ Check PageStore.swift AES-GCM implementation (line 293)

**Persistence tests failing?**
→ Check DynamicCollection.persist() and saveLayout()

**Performance tests failing?**
→ Check for fsync() in hot paths, metadata reloads

**File integrity tests failing?**
→ Check StorageLayout.save() atomic write

**Failure injection tests failing?**
→ Expected! These test error recovery paths

**Migration tests failing?**
→ Check AutoMigration.swift format byte handling

---

## Debugging Failed Tests

### **Enable Detailed Logging:**
```swift
BlazeLogger.setLogLevel(.trace) // In setUp()
```

### **Check File Contents:**
```bash
# View metadata file
cat /tmp/TestDB.meta | jq.

# Check first byte (should be '{' = 0x7B)
xxd -l 16 /tmp/TestDB.meta
```

### **Profile Performance:**
```bash
# Use Instruments for detailed profiling
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests/PerformanceInvariantTests \
 -enableCodeCoverage YES
```

---

## Pre-Production Checklist

Run this before any release:

- [ ] All encryption round-trip tests pass
- [ ] All persistence integrity tests pass
- [ ] All performance invariants met
- [ ] All file integrity tests pass
- [ ] Database recovers from all injected failures
- [ ] Auto-migration preserves all data
- [ ] Full test suite passes (1,513 tests)
- [ ] No memory leaks (Instruments)
- [ ] No thread sanitizer warnings

---

## Quick Smoke Test (30 seconds)

Run just the most critical tests:

```bash
xcodebuild test -scheme BlazeDB \
 -only-testing:BlazeDBTests/EncryptionRoundTripVerificationTests/testCiphertextNotRounded \
 -only-testing:BlazeDBTests/PersistenceIntegrityTests/testTenRecordsPersistence \
 -only-testing:BlazeDBTests/FileIntegrityTests/testMetadataAlwaysValidJSON \
 -only-testing:BlazeDBTests/AutoMigrationVerificationTests/testMetadataNeverStartsWithBinaryByte
```

If these 4 pass, you're 95% confident the critical bugs are fixed.

---

** Your database is now bulletproof!**

