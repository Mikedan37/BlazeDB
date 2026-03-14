#!/bin/bash
# Tier 1: CI gate. Tier 0 + Tier 1 deterministic lanes.
# See Docs/Testing/TEST_EXECUTION_MODEL.md
set -e
echo "=== Tier 1: CI gate (Tier 0 + Tier 1) ==="
RUN_ID="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR=".artifacts/core/${RUN_ID}"
mkdir -p "$ARTIFACT_DIR"
# Fail fast if Tier-2-only env is set (Tier 1 CI must stay bounded)
if [ -n "${RUN_HEAVY_STRESS}" ] && [ "${RUN_HEAVY_STRESS}" != "0" ]; then
  echo "ERROR: RUN_HEAVY_STRESS must not be set for Tier 1. Unset it or use run-tier2.sh for heavy stress."
  exit 1
fi
if [ -n "${TEST_SLOW_CONCURRENCY}" ] && [ "${TEST_SLOW_CONCURRENCY}" != "0" ]; then
  echo "ERROR: TEST_SLOW_CONCURRENCY must not be set for Tier 1. Unset it or use run-tier2.sh."
  exit 1
fi
./Scripts/check-durability-lane-integrity.sh
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier0 --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 1 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier1 --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
echo "Tier1 artifacts: $ARTIFACT_DIR"
echo "=== Tier 1 complete ==="
