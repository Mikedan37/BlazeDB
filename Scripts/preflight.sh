#!/bin/bash
set -euo pipefail

echo "=== BlazeDB preflight ==="
echo "Step 1/2: swift build"
swift build

echo "Step 2/2: Tier 0 gate"
./Scripts/run-tier0.sh

echo "=== Preflight complete ==="
