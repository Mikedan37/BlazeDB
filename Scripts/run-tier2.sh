#!/bin/bash
# Tier 2: integration and recovery workflows.
# This lane is pre-release/nightly. Default behavior remains non-blocking for local/manual use.
# Use --strict (or BLAZEDB_TIER2_STRICT=1) to make failures fail the caller workflow.
# See Docs/Testing/TEST_EXECUTION_MODEL.md
set -e
STRICT_MODE="${BLAZEDB_TIER2_STRICT:-0}"
case "${1:-}" in
  --strict)
    STRICT_MODE=1
    ;;
  "")
    ;;
  *)
    echo "ERROR: unknown argument '$1'"
    echo "Usage: ./Scripts/run-tier2.sh [--strict]"
    exit 2
    ;;
esac

if [[ "$STRICT_MODE" == "1" ]]; then
  echo "=== Tier 2: integration/recovery (strict) ==="
else
  echo "=== Tier 2: integration/recovery (non-blocking) ==="
fi
RUN_ID="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR=".artifacts/integration/${RUN_ID}"
mkdir -p "$ARTIFACT_DIR"
set +e
python3 ./Scripts/verify_execution_coverage.py --target BlazeDB_Tier2 --package-path BlazeDBExtraTests --artifact-dir "$ARTIFACT_DIR" --allowed-missing 0 --num-workers 2
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  if [[ "$STRICT_MODE" == "1" ]]; then
    echo "  >> Tier 2 failed with exit code $rc (strict mode: failing lane)"
    exit "$rc"
  fi
  echo "  >> Tier 2 failed with exit code $rc (non-blocking lane)"
fi
echo "Tier2 artifacts: $ARTIFACT_DIR"
echo "=== Tier 2 complete ==="
