#!/bin/bash
# Run Tier 1 (Gate) tests only
# These tests MUST pass for any release

set -e

echo "=== Running BlazeDB Tier 1 (Gate) Tests ==="
echo "These tests validate core production safety guarantees."
echo ""

swift test --filter BlazeDBCoreGateTests

echo ""
echo "=== Tier 1 Tests Complete ==="
echo "All production gate tests passed."
