#!/bin/bash
# Run core tests only (excludes distributed modules)
# This script filters tests to avoid distributed module build failures

set -eu

echo "Checking frozen core..."
./Scripts/check-freeze.sh HEAD^ || {
    echo "ERROR: Frozen core files modified. Aborting tests."
    exit 1
}

echo "Building core modules..."
swift build --target BlazeDB

echo "Running core tests..."

# Aggregate failures instead of masking them. Each filter is piped to grep to hide
# distributed-module noise, but that pipe (and the old `|| true`) previously discarded
# swift test's real exit status, so the script always exited 0 = false green (#368).
# Fix: read swift test's status via PIPESTATUS[0], collect failures, exit non-zero if any.
set +e   # run every filter; aggregate rather than stop at the first failure
FILTER_NOISE="Distributed\|Telemetry\|InMemoryRelay\|BlazeTopology\|TCPRelay"
FAILED=()

run_filter() {
    local name="$1"
    swift test --filter "$name" 2>&1 | grep -v "$FILTER_NOISE"
    local status=${PIPESTATUS[0]}   # swift test's exit code, NOT grep's
    if [ "$status" -ne 0 ]; then
        echo "❌ FAILED: $name (exit $status)"
        FAILED+=("$name")
    fi
}

# Run tests individually to avoid distributed module issues
run_filter QueryErgonomicsTests
run_filter SchemaMigrationTests
run_filter ImportExportTests
run_filter OperationalConfidenceTests
run_filter LinuxCompatibilityTests
run_filter CrashRecoveryTests
run_filter ErrorSurfaceTests
run_filter LifecycleTests
run_filter LockingTests
run_filter ResourceLimitsTests
run_filter CompatibilityTests
run_filter GoldenPathIntegrationTests
run_filter CLISmokeTests

if [ "${#FAILED[@]}" -ne 0 ]; then
    echo "Core tests FAILED (${#FAILED[@]}): ${FAILED[*]}"
    exit 1
fi
echo "Core tests completed"
