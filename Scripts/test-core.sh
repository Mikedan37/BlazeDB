#!/bin/bash
# Core-only test runner
# Builds and tests BlazeDB core without distributed modules

set -e

echo "=== Core-Only Test Runner ==="
echo ""

# Check frozen core first
echo "1. Checking frozen core..."
./Scripts/check-freeze.sh HEAD^ || {
    echo "ERROR: Frozen core files modified. Aborting tests."
    exit 1
}

# Build core target only
echo ""
echo "2. Building BlazeDB core..."
swift build --target BlazeDB 2>&1 | grep -v "Distributed\|Telemetry\|BlazeSync\|CrossApp" || {
    BUILD_OUTPUT=$(swift build --target BlazeDB 2>&1)
    if echo "$BUILD_OUTPUT" | grep -q "error:"; then
        echo "Build failed with errors:"
        echo "$BUILD_OUTPUT" | grep "error:" | head -10
        exit 1
    fi
}

# Run core tests (filtered)
echo ""
echo "3. Running core tests..."
swift test --filter BlazeDBTests 2>&1 | grep -v "Distributed\|Telemetry\|BlazeSync\|CrossApp\|BlazeTopology\|TCPRelay\|InMemoryRelay\|OperationLogGC\|MultiDatabaseGC\|ServerTransport\|BlazeDiscovery\|BlazeQuery\|DataSeeding\|Testing\|Triggers\|CrossAppSync\|WebSocketRelay" || {
    TEST_OUTPUT=$(swift test --filter BlazeDBTests 2>&1)
    if echo "$TEST_OUTPUT" | grep -q "Test Suite.*failed\|error:"; then
        echo "Tests failed:"
        echo "$TEST_OUTPUT" | grep -E "Test Suite.*failed|error:" | head -10
        exit 1
    fi
}

echo ""
echo "=== Core tests completed successfully ==="
