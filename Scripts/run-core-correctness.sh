#!/bin/bash
# Run Tier 0: Core Correctness Tests
# These MUST pass after every V1.5 refactor step.
set -euo pipefail

echo "=== BlazeDB Core Correctness Suite (Tier 0) ==="
echo "These tests validate fundamental database invariants."
echo ""

swift test --filter BlazeDBCoreCorrectnessTests 2>&1

echo ""
echo "=== Core Correctness Suite Complete ==="
