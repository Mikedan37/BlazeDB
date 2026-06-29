#!/usr/bin/env bash
# Place Linux-built Android native libs where :app Gradle copySwiftJniLibs expects them.
#
# Usage:
#   ./Scripts/stage-kmm-android-native-for-gradle.sh <staging-dir>
#
# Staging layout (from CI artifact):
#   <staging-dir>/lib/libBlazeDBAndroidBridge.so
#   <staging-dir>/swift-runtime/*.so
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="${1:?staging directory required}"

# shellcheck source=android-swift-config.sh
source "$ROOT/Scripts/android-swift-config.sh"

BRIDGE_SRC="$STAGE/lib/libBlazeDBAndroidBridge.so"
RUNTIME_SRC="$STAGE/swift-runtime"
BRIDGE_DEST="$ROOT/.build/aarch64-unknown-linux-android28/debug/libBlazeDBAndroidBridge.so"
RUNTIME_DEST="$ROOT/.artifacts/android-sdk/${BLAZEDB_ANDROID_SDK_ARTIFACT%.tar.gz}/swift-android/swift-resources/usr/lib/swift-aarch64/android"

[[ -f "$BRIDGE_SRC" ]] || { echo "error: missing $BRIDGE_SRC" >&2; exit 1; }
[[ -d "$RUNTIME_SRC" ]] || { echo "error: missing $RUNTIME_SRC" >&2; exit 1; }

mkdir -p "$(dirname "$BRIDGE_DEST")" "$RUNTIME_DEST"
cp "$BRIDGE_SRC" "$BRIDGE_DEST"
cp "$RUNTIME_SRC"/*.so "$RUNTIME_DEST/"

echo ">>> Staged Android native libs for Gradle"
echo "    bridge: $BRIDGE_DEST"
echo "    swift runtime: $RUNTIME_DEST"
