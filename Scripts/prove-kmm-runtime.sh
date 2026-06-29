#!/usr/bin/env bash
# End-to-end KMM runtime proof: iOS simulator test + Android emulator app smoke.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== KMM iOS runtime (simulator test) ==="
"$ROOT/Scripts/prove-kmm-ios-runtime.sh"

echo ""
echo "=== KMM Android runtime (emulator app) ==="
"$ROOT/Scripts/prove-kmm-android-runtime.sh"

echo ""
echo ">>> KMM RUNTIME PROOF PASSED (iOS + Android)"
