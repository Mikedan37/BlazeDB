#!/usr/bin/env bash
# iOS simulator runtime proof for KMM BlazeDB (put + query via commonMain API).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/Examples/android"

echo "=== 1/2 Build iOS Swift bridge static libs ==="
chmod +x "$ROOT/Scripts/build-kmm-ios-bridge.sh"
"$ROOT/Scripts/build-kmm-ios-bridge.sh"

echo "=== 2/2 Run iosSimulatorArm64Test on simulator ==="
cd "$ANDROID_DIR"
chmod +x gradlew
./gradlew :shared:iosSimulatorArm64Test --info 2>&1 | tee /tmp/blazedb-kmm-ios-test.log

if grep -q "BUILD SUCCESSFUL" /tmp/blazedb-kmm-ios-test.log; then
  echo ">>> KMM iOS RUNTIME OK (iosSimulatorArm64Test passed)"
  exit 0
fi

echo ">>> KMM iOS RUNTIME FAILED"
exit 1
