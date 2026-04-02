#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/blazedb-clean-XXXXXX")"
LOG_DIR="$ROOT_DIR/.logs/clean-checkout"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_LOG_DIR="$LOG_DIR/$STAMP"
mkdir -p "$RUN_LOG_DIR"

cleanup() {
  git -C "$ROOT_DIR" worktree remove --force "$TMP_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== BlazeDB clean-checkout verification ==="
echo "Creating detached worktree at: $TMP_DIR"
git -C "$ROOT_DIR" worktree add --detach "$TMP_DIR" HEAD >/dev/null

echo "Syncing local working-tree changes into clean worktree snapshot"
while IFS= read -r relpath; do
  [ -z "$relpath" ] && continue
  src="$ROOT_DIR/$relpath"
  dst="$TMP_DIR/$relpath"
  mkdir -p "$(dirname "$dst")"
  if [ -d "$src" ]; then
    rm -rf "$dst"
    cp -R "$src" "$dst"
  elif [ -f "$src" ]; then
    cp "$src" "$dst"
  fi
done < <(
  {
    git -C "$ROOT_DIR" diff --name-only
    git -C "$ROOT_DIR" diff --cached --name-only
    git -C "$ROOT_DIR" ls-files --others --exclude-standard
  } | sort -u
)

echo "Step 1/3: release build from clean worktree"
BUILD_LOG="$RUN_LOG_DIR/step1_release_build.log"
if (
  cd "$TMP_DIR"
  env -i PATH="$PATH" HOME="$HOME" TERM="${TERM:-dumb}" \
    swift build -c release
) >"$BUILD_LOG" 2>&1; then
  WARNINGS=$(rg -n "warning:" "$BUILD_LOG" | wc -l | tr -d ' ' || true)
  echo "  PASS (warnings: $WARNINGS, log: $BUILD_LOG)"
else
  echo "  FAIL (log: $BUILD_LOG)"
  rg -n "error:|fatal error|FAILED|Assertion|XCTAssert|not equal|threw error|Permission denied" "$BUILD_LOG" --max-count 40 || true
  exit 1
fi

echo "Step 2/3: clean-worktree validation checks"
step_test() {
  local name="$1"
  local logfile="$2"
  shift 2
  if "$@" >"$logfile" 2>&1; then
    local warnings=0
    warnings=$(rg -n "warning:" "$logfile" | wc -l | tr -d ' ' || true)
    echo "  PASS $name (warnings: $warnings, log: $logfile)"
  else
    echo "  FAIL $name (log: $logfile)"
    rg -n "error:|fatal error|FAILED|Assertion|XCTAssert|not equal|threw error|Permission denied" "$logfile" --max-count 40 || true
    exit 1
  fi
}

(
  cd "$TMP_DIR"
  step_test \
    "Tier0 GoldenPath" \
    "$RUN_LOG_DIR/step2_tier0_golden.log" \
    env -i PATH="$PATH" HOME="$HOME" TERM="${TERM:-dumb}" \
    swift test --filter BlazeDB_Tier0.GoldenPathIntegrationTests
  step_test \
    "Tier1 GoldenPath" \
    "$RUN_LOG_DIR/step2_tier1_golden.log" \
    env -i PATH="$PATH" HOME="$HOME" TERM="${TERM:-dumb}" \
    swift test --skip-build --filter BlazeDB_Tier1.GoldenPathIntegrationTests
  step_test \
    "Combined GoldenPath filter" \
    "$RUN_LOG_DIR/step2_combined_golden.log" \
    env -i PATH="$PATH" HOME="$HOME" TERM="${TERM:-dumb}" \
    swift test --skip-build --filter GoldenPathIntegrationTests
  step_test \
    "Tier2 CrossVersion harness" \
    "$RUN_LOG_DIR/step2_tier2_crossversion.log" \
    env -i PATH="$PATH" HOME="$HOME" TERM="${TERM:-dumb}" \
    bash -c 'cd BlazeDBExtraTests && swift test --filter BlazeDB_Tier2.CrossVersionExportRestoreHarnessTests'
)

echo "Step 3/3: report"
echo "Clean-checkout verification succeeded for current working tree snapshot."
echo "Run logs: $RUN_LOG_DIR"
echo "=== Clean-checkout verification complete ==="
