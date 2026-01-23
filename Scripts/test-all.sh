#!/bin/bash
# Run all tests (Tier 1, Tier 2, Tier 3)
# Use this for comprehensive testing, not for CI

set -e

echo "=== Running All BlazeDB Tests ==="
echo ""

echo "Tier 1 (Gate) Tests..."
swift test --target BlazeDBCoreGateTests || {
    echo "❌ Tier 1 tests failed (this is blocking)"
    exit 1
}

echo ""
echo "Tier 2 (Core) Tests..."
swift test --target BlazeDBCoreTests || {
    echo "⚠️  Tier 2 tests failed (non-blocking)"
}

echo ""
echo "Tier 3 (Legacy) Tests..."
swift test --target BlazeDBLegacyTests || {
    echo "⚠️  Tier 3 tests failed (expected, non-blocking)"
}

echo ""
echo "Integration Tests..."
swift test --target BlazeDBIntegrationTests || {
    echo "⚠️  Integration tests failed (non-blocking)"
}

echo ""
echo "=== All Tests Complete ==="
