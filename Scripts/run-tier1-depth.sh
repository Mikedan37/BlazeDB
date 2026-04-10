#!/bin/bash
# Depth lane: Tier2/Tier3 heavy with transitional companions.
# See Docs/Testing/CI_AND_TEST_TIERS.md
set -e
echo "=== Depth lane (Tier2/Tier3 companions) ==="
RUN_ID="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR=".artifacts/depth/${RUN_ID}"
mkdir -p "$ARTIFACT_DIR"
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier2 --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier2_Extended --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier3_Heavy --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier3_Heavy_Perf --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
echo "Depth lane artifacts: $ARTIFACT_DIR"
echo "=== Depth lane complete ==="
