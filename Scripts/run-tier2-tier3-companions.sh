#!/bin/bash
# Local runner: Tier2 + Tier2_Extended + Tier3_Heavy + Tier3_Heavy_Perf (same companion targets as weekly deep-validation).
# See Docs/Testing/CI_AND_TEST_TIERS.md
set -e
. "$(dirname "$0")/lib/temp_lifecycle.sh"
blazedb_temp_setup "tier2-tier3-companions"
echo "=== Tier2/Tier3 companion depth (local) ==="
RUN_ID="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR=".artifacts/tier2-tier3-companions/${RUN_ID}"
mkdir -p "$ARTIFACT_DIR"
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier2 --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier2_Extended --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier3_Heavy --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier3_Heavy_Perf --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2 || exit 1
echo "Tier2/Tier3 companion artifacts: $ARTIFACT_DIR"
echo "=== Tier2/Tier3 companion depth complete ==="
