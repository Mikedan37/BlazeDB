#!/bin/bash
# Tier2/Tier3 heavy depth lane.
# See Docs/Testing/CI_AND_TEST_TIERS.md
set -e
echo "=== Tier2/Tier3 heavy depth ==="
RUN_ID="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR=".artifacts/tier1-depth/${RUN_ID}"
mkdir -p "$ARTIFACT_DIR"
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier2 --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier2_Extended --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier3_Heavy --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier3_Heavy_Perf --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
echo "Tier2/Tier3 heavy artifacts: $ARTIFACT_DIR"
echo "=== Tier2/Tier3 heavy depth complete ==="
