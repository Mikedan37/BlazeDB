#!/bin/bash
# Fail-loud durability lane integrity checks.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TIER0_DIR="$ROOT_DIR/BlazeDBTests/Tier0Core"
TIER1_DIR="$ROOT_DIR/BlazeDBTests/Tier1Core"
TIER3_DESTRUCTIVE_DIR="$ROOT_DIR/BlazeDBTests/Tier3Destructive"

echo "=== Durability lane integrity check ==="

required_tier0=(
  "Durability/TransactionDurabilityTests.swift"
  "Durability/TransactionRecoveryTests.swift"
  "Durability/BlazeDBRecoveryTests.swift"
)

for rel in "${required_tier0[@]}"; do
  if [[ ! -f "$TIER0_DIR/$rel" ]]; then
    echo "ERROR: Missing required Tier0 durability test: $rel"
    exit 1
  fi
done

# No destructive/fault-injection test files allowed in Tier0/Tier1.
if rg --files "$TIER0_DIR" "$TIER1_DIR" | rg "(IOFault|FailureInjection|Destructive).*Tests\\.swift" >/dev/null; then
  echo "ERROR: Destructive/fault-injection tests leaked into Tier0/Tier1."
  exit 1
fi

# Destructive lane must contain at least one destructive test.
if ! rg --files "$TIER3_DESTRUCTIVE_DIR" | rg "(IOFault|FailureInjection|Destructive).*Tests\\.swift" >/dev/null; then
  echo "ERROR: Tier3 destructive lane missing destructive test classes."
  exit 1
fi

echo "=== Durability lane integrity check passed ==="
