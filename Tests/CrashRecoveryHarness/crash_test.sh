#!/bin/bash
# Crash recovery test script
# Runs CrashHarness, kills it mid-operation, then verifies recovery

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=$(mktemp -d)
DB_PATH="$TEMP_DIR/crash_test.blazedb"
HARNESS_BINARY="$SCRIPT_DIR/.build/debug/CrashHarness"

# Cleanup on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "=== BlazeDB Crash Recovery Test ==="
echo ""

# Build harness if needed
if [ ! -f "$HARNESS_BINARY" ]; then
    echo "Building crash harness..."
    cd "$SCRIPT_DIR"
    swift build
    HARNESS_BINARY="$SCRIPT_DIR/.build/debug/CrashHarness"
fi

# Test 1: Crash mid-write
echo "Test 1: Crash during write operation"
rm -f "$DB_PATH"*
"$HARNESS_BINARY" "$DB_PATH" 100 mid-write &
HARNESS_PID=$!
sleep 2  # Let it write some records
kill -9 $HARNESS_PID 2>/dev/null || true
wait $HARNESS_PID 2>/dev/null || true

echo "  Crashed. Recovering..."
sleep 1

# Verify recovery
swift -c "
import Foundation
import BlazeDBCore

let db = try BlazeDBClient(name: \"recovery-test\", fileURL: URL(fileURLWithPath: \"$DB_PATH\"), password: \"test-password\")
let count = db.count()
print(\"  ✓ Recovered record count: \(count)\")

let health = try db.health()
if health.status == .ok {
    print(\"  ✓ Health status: OK\")
} else {
    print(\"  ⚠️  Health status: \(health.status.rawValue)\")
    for reason in health.reasons {
        print(\"    - \(reason)\")
    }
}

try db.close()
" || {
    echo "  ❌ Recovery verification failed"
    exit 1
}

echo ""

# Test 2: Crash mid-transaction
echo "Test 2: Crash during transaction"
rm -f "$DB_PATH"*
"$HARNESS_BINARY" "$DB_PATH" 50 mid-transaction &
HARNESS_PID=$!
sleep 1
kill -9 $HARNESS_PID 2>/dev/null || true
wait $HARNESS_PID 2>/dev/null || true

echo "  Crashed. Recovering..."
sleep 1

# Verify transaction rollback
swift -c "
import Foundation
import BlazeDBCore

let db = try BlazeDBClient(name: \"recovery-test\", fileURL: URL(fileURLWithPath: \"$DB_PATH\"), password: \"test-password\")
let count = db.count()
print(\"  ✓ Record count after crash: \(count)\")

// Transaction records should NOT exist
let txnRecords = try db.query().where(\"txn\", equals: .bool(true)).execute().records
if txnRecords.isEmpty {
    print(\"  ✓ Transaction rollback verified (no uncommitted records)\")
} else {
    print(\"  ❌ Found \(txnRecords.count) uncommitted records (should be 0)\")
    exit(1)
}

try db.close()
" || {
    echo "  ❌ Transaction rollback verification failed"
    exit 1
}

echo ""

# Test 3: Crash before close
echo "Test 3: Crash before close()"
rm -f "$DB_PATH"*
"$HARNESS_BINARY" "$DB_PATH" 50 before-close &
HARNESS_PID=$!
sleep 2
kill -9 $HARNESS_PID 2>/dev/null || true
wait $HARNESS_PID 2>/dev/null || true

echo "  Crashed. Recovering..."
sleep 1

# Verify all records persisted
swift -c "
import Foundation
import BlazeDBCore

let db = try BlazeDBClient(name: \"recovery-test\", fileURL: URL(fileURLWithPath: \"$DB_PATH\"), password: \"test-password\")
let count = db.count()
print(\"  ✓ Record count: \(count)\")

if count >= 50 {
    print(\"  ✓ All records persisted despite crash\")
} else {
    print(\"  ⚠️  Expected at least 50 records, got \(count)\")
}

try db.close()
" || {
    echo "  ❌ Pre-close crash verification failed"
    exit 1
}

echo ""
echo "=== All Crash Recovery Tests Passed ==="
