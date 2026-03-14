#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

LANE="${1:-pr}"
PLAN="${TESTGOV_PLAN:-BlazeDB_Quick}"
DESTINATION="platform=macOS"
MANIFEST="Docs/Testing/TEST_INVENTORY_MANIFEST.json"
ART_ROOT=".artifacts/testgov"
CACHED_MANIFEST="$ART_ROOT/latest_manifest.json"
STRICT_LANE="false"
if [[ "$LANE" == "nightly" || "$LANE" == "release" ]]; then
  STRICT_LANE="true"
fi

mkdir -p "$ART_ROOT"
if [[ ! -f "$CACHED_MANIFEST" && -f "$MANIFEST" ]]; then
  cp "$MANIFEST" "$CACHED_MANIFEST"
fi

MIN_DISCOVERED_QUICK="${MIN_DISCOVERED_QUICK:-84}"
MIN_DISCOVERED_CORE="${MIN_DISCOVERED_CORE:-1275}"
MIN_DISCOVERED_INTEGRATION="${MIN_DISCOVERED_INTEGRATION:-189}"
MIN_DISCOVERED="$MIN_DISCOVERED_QUICK"
if [[ "$PLAN" == "BlazeDB_Core" ]]; then
  MIN_DISCOVERED="$MIN_DISCOVERED_CORE"
fi
if [[ "$PLAN" == "BlazeDB_Integration" || "$PLAN" == "BlazeDB_Core_Integration" ]]; then
  MIN_DISCOVERED="$MIN_DISCOVERED_INTEGRATION"
fi

./Scripts/check-shared-scheme.sh
XCODE_SMOKE_STATUS="PASSED"
if [[ "$STRICT_LANE" == "true" ]]; then
  if ! ./Scripts/xcode-build-for-testing-smoke.sh BlazeDB.xcodeproj BlazeDB "$DESTINATION"; then
    echo "XCODE_SMOKE_FAILED" >&2
    exit 28
  fi
else
  if ! ./Scripts/xcode-build-for-testing-smoke.sh BlazeDB.xcodeproj BlazeDB "$DESTINATION"; then
    XCODE_SMOKE_STATUS="FAILED"
    echo "WARN: build-for-testing smoke failed in non-strict lane; relying on fallback discovery."
  fi
fi

XCODE_DISCOVERED=$(swift Tools/TestGovernance/testgov.swift discover \
  --source xcode \
  --project BlazeDB.xcodeproj \
  --scheme BlazeDB \
  --plan "$PLAN" \
  --destination "$DESTINATION" \
  --lane "$LANE" \
  --cached-manifest "$CACHED_MANIFEST" \
  --artifacts-root "$ART_ROOT")

SPM_DISCOVERED=""
if [[ "$STRICT_LANE" != "true" ]]; then
  if SPM_DISCOVERED=$(swift Tools/TestGovernance/testgov.swift discover \
    --source spm \
    --plan spm \
    --artifacts-root "$ART_ROOT"); then
    :
  else
    echo "WARN: SPM discovery failed in non-strict lane; continuing with Xcode discovery."
  fi
fi

if [[ -n "$SPM_DISCOVERED" ]]; then
  swift Tools/TestGovernance/testgov.swift diff \
    --discovered "$XCODE_DISCOVERED" \
    --discovered "$SPM_DISCOVERED" \
    --manifest "$MANIFEST" \
    --plan "$PLAN" \
    --min-discovered "$MIN_DISCOVERED" \
    --lane "$LANE" \
    --xcode-smoke-status "$XCODE_SMOKE_STATUS" \
    --artifacts-root "$ART_ROOT"
else
  swift Tools/TestGovernance/testgov.swift diff \
    --discovered "$XCODE_DISCOVERED" \
    --manifest "$MANIFEST" \
    --plan "$PLAN" \
    --min-discovered "$MIN_DISCOVERED" \
    --lane "$LANE" \
    --xcode-smoke-status "$XCODE_SMOKE_STATUS" \
    --artifacts-root "$ART_ROOT"
fi

if [[ "$STRICT_LANE" == "true" ]]; then
  swift Tools/TestGovernance/testgov.swift verify-plans \
    --manifest "$MANIFEST" \
    --project BlazeDB.xcodeproj \
    --scheme BlazeDB \
    --destination "$DESTINATION" \
    --quick-plan BlazeDB_Quick \
    --core-plan BlazeDB_Core \
    --artifacts-root "$ART_ROOT"
fi

if [[ "$STRICT_LANE" == "true" ]]; then
  cp "$MANIFEST" "$CACHED_MANIFEST"
  shasum -a 256 "$CACHED_MANIFEST" | awk '{print $1}' > "$ART_ROOT/latest_manifest.sha256"
fi

echo "testgov_ci: PASS (lane=$LANE)"
