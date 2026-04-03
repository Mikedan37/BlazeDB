#!/bin/bash
# Tier 1 depth: extended integration/stress + perf (not the default PR gate).
# See Docs/Testing/CI_AND_TEST_TIERS.md
set -e
echo "=== Tier 1 depth (Tier1Extended + Tier1Perf) ==="
RUN_ID="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR=".artifacts/tier1-depth/${RUN_ID}"
mkdir -p "$ARTIFACT_DIR"
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier1Extended --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier1Perf --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
echo "Tier1 depth artifacts: $ARTIFACT_DIR"
echo "=== Tier 1 depth complete ==="
