#!/bin/bash
# Tier 0: Always-on (local + PR). Fast, deterministic, must pass.
# See Docs/Testing/TEST_EXECUTION_MODEL.md
set -e
echo "=== Tier 0: Always-on deterministic gate ==="
RUN_ID="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR=".artifacts/quick/${RUN_ID}"
TMP_BASE=".artifacts/tmp/${RUN_ID}"
mkdir -p "$ARTIFACT_DIR" "$TMP_BASE"
export TMPDIR="$(pwd)/$TMP_BASE"
# Fail fast if Tier-2-only env is set (would change test behavior; Tier 0 must stay light)
if [ -n "${RUN_HEAVY_STRESS}" ] && [ "${RUN_HEAVY_STRESS}" != "0" ]; then
  echo "ERROR: RUN_HEAVY_STRESS must not be set for Tier 0. Unset it or use run-tier2.sh for heavy stress."
  exit 1
fi
if [ -n "${TEST_SLOW_CONCURRENCY}" ] && [ "${TEST_SLOW_CONCURRENCY}" != "0" ]; then
  echo "ERROR: TEST_SLOW_CONCURRENCY must not be set for Tier 0. Unset it or use run-tier2.sh."
  exit 1
fi
./Scripts/check-durability-lane-integrity.sh
set +e
python3 ./Scripts/verify_execution_coverage.py \
  --target BlazeDB_Tier0 \
  --artifact-dir "$ARTIFACT_DIR" \
  --allowed-missing 0 \
  --num-workers 1
rc=$?
set -e
echo "Tier0 artifacts: $ARTIFACT_DIR"
if [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi
echo "=== Tier 0 complete ==="
