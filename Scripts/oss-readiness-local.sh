#!/bin/bash
set -euo pipefail

LOG_DIR="${TMPDIR:-/tmp}/blazedb-oss-readiness-$(date +%s)"
mkdir -p "$LOG_DIR"

run_step() {
  local step="$1"
  shift
  local safe_step
  safe_step="$(echo "$step" | tr -c '[:alnum:]_.-' '_')"
  local log="$LOG_DIR/${safe_step}.log"
  echo "$step"
  if "$@" >"$log" 2>&1; then
    local warnings=0
    warnings=$(rg -n "warning:" "$log" | wc -l | tr -d ' ' || true)
    echo "  PASS (warnings: $warnings, log: $log)"
  else
    echo "  FAIL (log: $log)"
    echo "  Key failure lines:"
    rg -n "error:|fatal error|FAILED|Assertion|XCTAssert|not equal|threw error|Permission denied" "$log" --max-count 40 || true
    exit 1
  fi
}

echo "=== BlazeDB OSS readiness local check ==="
run_step "Step 1/4: swift build" swift build

run_step "Step 2/4: Tier 0 gate" env BLAZEDB_TEST_SCOPE=tier0 swift test --filter BlazeDB_Tier0

run_step "Step 3/4: Tier 1 gate" swift test --skip-build --filter BlazeDB_Tier1

run_step "Step 4/4: Golden path verification" swift test --skip-build --filter GoldenPathIntegrationTests

echo "=== OSS readiness local check complete ==="
