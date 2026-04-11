#!/bin/bash
# Tier 3: Manual / stress-only. Destructive and fault-injection tests.
# NEVER run in CI or on PR. Require explicit invocation.
# See Docs/Testing/TEST_EXECUTION_MODEL.md and TEST_EXECUTION_TIERS.md §4.
set -euo pipefail
. "$(dirname "$0")/lib/temp_lifecycle.sh"
blazedb_temp_setup "tier3"
echo "=== Tier 3: Manual only (destructive / I/O fault injection) ==="
echo "These tests must be run explicitly. They are excluded from all automation."
echo "  >> BlazeDB_Tier3_Destructive (root package)"
swift test --filter BlazeDB_Tier3_Destructive
echo "=== Tier 3 complete ==="
