#!/bin/bash
set -euo pipefail

echo "=== Validate testing policy ==="

# Authoritative governance check (Xcode-first; SPM best-effort in non-strict lanes).
./Scripts/testgov_ci.sh nightly
./Scripts/check-durability-lane-integrity.sh

required_plans=(
  "BlazeDB/BlazeDB_Quick.xctestplan"
  "BlazeDB/BlazeDB_Core.xctestplan"
  "BlazeDB/BlazeDB_Integration.xctestplan"
  "BlazeDB/BlazeDB_Core_Integration.xctestplan"
  "BlazeDB/BlazeDB_Nightly.xctestplan"
  "BlazeDB/BlazeDB_Destructive.xctestplan"
)

for p in "${required_plans[@]}"; do
  if [[ ! -f "$p" ]]; then
    echo "ERROR: missing required test plan: $p"
    exit 1
  fi
done

# Quick must be Tier0-only.
if ! rg -n "\"identifier\"\\s*:\\s*\"BlazeDBTests\"" "BlazeDB/BlazeDB_Quick.xctestplan" >/dev/null; then
  echo "ERROR: Quick plan missing BlazeDBTests target"
  exit 1
fi
if rg -n "\"identifier\"\\s*:\\s*\"BlazeDBTier1Tests\"" "BlazeDB/BlazeDB_Quick.xctestplan" >/dev/null; then
  echo "ERROR: Quick plan contains Tier1 target"
  exit 1
fi

# Core must include both Tier0 and Tier1 bundles.
if ! rg -n "\"identifier\"\\s*:\\s*\"BlazeDBTests\"" "BlazeDB/BlazeDB_Core.xctestplan" >/dev/null; then
  echo "ERROR: Core plan missing BlazeDBTests target"
  exit 1
fi
if ! rg -n "\"identifier\"\\s*:\\s*\"BlazeDBTier1Tests\"" "BlazeDB/BlazeDB_Core.xctestplan" >/dev/null; then
  echo "ERROR: Core plan missing BlazeDBTier1Tests target"
  exit 1
fi

echo "=== Testing policy validation passed ==="
