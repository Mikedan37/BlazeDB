#!/bin/bash
# Strict deterministic run for Tier 0 + Tier 1 only.
# With tiered targets, strict mode now maps to target-level execution.
set -e
echo "=== Tier 1 (strict): Tier 0 + Tier 1 deterministic ==="
# Fail fast if Tier-2-only env is set
if [ -n "${RUN_HEAVY_STRESS}" ] && [ "${RUN_HEAVY_STRESS}" != "0" ]; then
  echo "ERROR: RUN_HEAVY_STRESS must not be set for Tier 1. Unset it or use run-tier2.sh."
  exit 1
fi
if [ -n "${TEST_SLOW_CONCURRENCY}" ] && [ "${TEST_SLOW_CONCURRENCY}" != "0" ]; then
  echo "ERROR: TEST_SLOW_CONCURRENCY must not be set for Tier 1. Unset it or use run-tier2.sh."
  exit 1
fi

swift test --filter BlazeDB_Tier0 || exit 1
swift test --filter BlazeDB_Tier1 || exit 1
echo "=== Tier 1 (strict) complete ==="
