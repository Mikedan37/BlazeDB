#!/bin/bash
# Pre-release confidence lane: Tier 0 + Tier 1 + Tier 2.
set -e
echo "=== Core+Integration (pre-release) ==="
RUN_ID="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR=".artifacts/core-integration/${RUN_ID}"
mkdir -p "$ARTIFACT_DIR"

if [ -n "${RUN_HEAVY_STRESS}" ] && [ "${RUN_HEAVY_STRESS}" != "0" ]; then
  echo "ERROR: RUN_HEAVY_STRESS must not be set for Core+Integration."
  exit 1
fi

python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier0 --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 1 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier1Fast --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier1Extended --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier1Perf --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier2 --package-path BlazeDBExtraTests --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1

echo "Core+Integration artifacts: $ARTIFACT_DIR"
echo "=== Core+Integration complete ==="
