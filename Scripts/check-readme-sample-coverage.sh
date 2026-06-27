#!/bin/bash
# Validates Examples/ReadmeSamples/README.md coverage table ↔ harness sync.
# Parses the checklist only — does not extract Swift from README.md.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COVERAGE_DOC="$ROOT_DIR/Examples/ReadmeSamples/README.md"
MAIN_SWIFT="$ROOT_DIR/Examples/ReadmeSamples/main.swift"
PACKAGE_SWIFT="$ROOT_DIR/Package.swift"

if [[ ! -f "$COVERAGE_DOC" ]]; then
  echo "FAILED: missing $COVERAGE_DOC"
  exit 1
fi

TABLE=$(
  awk '
    /^## Coverage table$/ { in_table=1; next }
    in_table && /^## / { exit }
    in_table && /^\|/ && !/^\|[-| ]+\|/ && !/README anchor/ { print }
  ' "$COVERAGE_DOC"
)

if [[ -z "$TABLE" ]]; then
  echo "FAILED: could not parse coverage table in $COVERAGE_DOC"
  exit 1
fi

failures=0

check_verify_function() {
  local fn="$1"
  if ! grep -q "func ${fn}()" "$MAIN_SWIFT"; then
    echo "FAILED: coverage table references ${fn}() but it is not defined in main.swift"
    failures=$((failures + 1))
    return
  fi
  if ! grep -q "try ${fn}()" "$MAIN_SWIFT"; then
    echo "FAILED: ${fn}() is defined but not called from main()"
    failures=$((failures + 1))
    return
  fi
  echo "OK: ${fn}()"
}

check_hello_blazedb() {
  if ! grep -q 'name: "HelloBlazeDB"' "$PACKAGE_SWIFT"; then
    echo "FAILED: coverage table references HelloBlazeDB but Package.swift has no HelloBlazeDB target"
    failures=$((failures + 1))
    return
  fi
  echo "OK: HelloBlazeDB executable"
}

echo "=== README sample coverage checklist enforcement ==="

while IFS= read -r row; do
  status="$(echo "$row" | awk -F'|' '{gsub(/^ +| +$/, "", $3); print $3}')"
  verified_by="$(echo "$row" | awk -F'|' '{gsub(/^ +| +$/, "", $4); print $4}')"

  if [[ "$status" != "Verified" ]]; then
    continue
  fi

  if echo "$verified_by" | grep -q 'HelloBlazeDB'; then
    check_hello_blazedb
    continue
  fi

  fn="$(echo "$verified_by" | sed -n 's/.*`\([a-zA-Z0-9_]*\)()`*.*/\1/p')"
  if [[ -z "$fn" ]]; then
    echo "FAILED: Verified row has no parseable verify function: $row"
    failures=$((failures + 1))
    continue
  fi

  check_verify_function "$fn"
done <<< "$TABLE"

if [[ "$failures" -gt 0 ]]; then
  echo "FAILED: $failures coverage checklist issue(s)"
  exit 1
fi

echo "PASS: coverage checklist matches ReadmeSamples harness"
echo "=== Coverage checklist enforcement complete ==="
