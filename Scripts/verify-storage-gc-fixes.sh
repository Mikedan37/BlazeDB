#!/usr/bin/env bash
# Run storage/GC regression tests one fix at a time (fail fast).
# Requires Swift/Xcode (macOS CI or local dev). See Docs/Testing/CI_AND_TEST_TIERS.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v swift >/dev/null 2>&1; then
  echo "ERROR: swift not found. Run on macOS or install Swift 6+."
  exit 127
fi

run_step() {
  local title="$1"
  shift
  echo ""
  echo "========================================"
  echo "$title"
  echo "========================================"
  if ! "$@"; then
    echo "FAILED: $title (exit $?)"
    exit 1
  fi
  echo "OK: $title"
}

swift build --target BlazeDBCore >/dev/null

run_step "Fix 1 — WAL checkpoint / persist visibility (Tier 0)" \
  swift test --skip-build --filter 'WALCommitBoundaryTests'

run_step "Fix 1 — storage growth after persist (Tier 2 integration)" \
  swift test --skip-build --filter 'BlazeDB_Tier2.BlazeFileSystemErrorTests/testStorageGrowthMonitoring'

run_step "Fix 2 — MVCC version GC frees overflow chains (Tier 1)" \
  swift test --skip-build --filter 'MVCCFoundationTests/testGarbageCollectionFreesFullOverflowChain'

run_step "Fix 2 — version GC + pageGC integration (Tier 2 extended)" \
  swift test --skip-build --filter 'BlazeDB_Tier2_Extended.PageGCTests/testVersionGC_FreesPages'

run_step "Fix 2 — heavy MVCC update file growth (Tier 2 extended)" \
  swift test --skip-build --filter 'BlazeDB_Tier2_Extended.PageGCTests/testPageGC_HeavyUpdateWorkload'

run_step "Fix 2 — file size boundary under churn (Tier 2 extended)" \
  swift test --skip-build --filter 'BlazeDB_Tier2_Extended.CompleteGCValidationTests/testGC_FileSizeBoundary'

echo ""
echo "All targeted storage/GC fix checks passed."
