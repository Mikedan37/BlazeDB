#!/usr/bin/env bash
# End-to-end KMM runtime proof: iOS simulator test + Android instrumentation smoke.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== KMM iOS runtime (simulator test) ==="
"$ROOT/Scripts/prove-kmm-ios-runtime.sh"

echo ""
echo "=== KMM Android runtime (instrumentation test) ==="
export CI_ALLOW_DOCKER_CROSS_COMPILE=1
"$ROOT/Scripts/ci-kmm-android-emulator-smoke.sh"

echo ""
echo ">>> KMM RUNTIME PROOF PASSED (iOS + Android)"
