#!/bin/bash
# Tier 2: integration and recovery workflows.
# This lane is pre-release/nightly and remains non-blocking by default.
# See Docs/Testing/TEST_EXECUTION_MODEL.md
set -e
echo "=== Tier 2: integration/recovery (non-blocking) ==="
RUN_ID="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR=".artifacts/integration/${RUN_ID}"
mkdir -p "$ARTIFACT_DIR"
set +e
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier2 --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "  >> Tier 2 failed with exit code $rc (non-blocking lane)"
fi
echo "Tier2 artifacts: $ARTIFACT_DIR"
echo "=== Tier 2 complete ==="
