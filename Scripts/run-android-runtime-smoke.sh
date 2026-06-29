#!/usr/bin/env bash
# Build the Android sample and optionally install + capture JNI smoke output.
# Requires: OSS Swift (see install-android-swift.sh), Android SDK, adb, arm64 emulator/device.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/Examples/android"
SWIFT_BUILD="${BLAZEDB_SWIFT_BUILD:-$ROOT/.build}"
INSTALL=1
GRADLE_EXTRA=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

  --swift-build PATH   SwiftPM .build dir (default: $ROOT/.build)
  --no-install         assembleDebug only; skip install + logcat capture
  -h, --help           Show this help

Prerequisites:
  - ./Scripts/install-android-swift.sh && ./Scripts/ci-android-cross-compile.sh
  - ANDROID_HOME or ~/Library/Android/sdk with platform-tools/adb on PATH
  - arm64-v8a emulator or device (API 28+)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --swift-build)
      SWIFT_BUILD="$2"
      shift 2
      ;;
    --no-install)
      INSTALL=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      GRADLE_EXTRA+=("$1")
      shift
      ;;
  esac
done

if ! command -v adb >/dev/null 2>&1; then
  echo "error: adb not found — install Android SDK platform-tools and ensure adb is on PATH" >&2
  exit 1
fi

if [[ ! -d "$SWIFT_BUILD/aarch64-unknown-linux-android28/debug" ]]; then
  echo ">>> Swift Android artifacts missing — running cross-compile"
  cd "$ROOT"
  ./Scripts/ci-android-cross-compile.sh
fi

cd "$ANDROID_DIR"
GRADLE=(./gradlew :app:assembleDebug "-PBLAZEDB_SWIFT_BUILD=$SWIFT_BUILD" "${GRADLE_EXTRA[@]}")
echo ">>> ${GRADLE[*]}"
"${GRADLE[@]}"

if [[ "$INSTALL" -eq 0 ]]; then
  echo ">>> assembleDebug ok (skipped install)"
  exit 0
fi

if ! adb devices | awk 'NR>1 && $2=="device" { found=1 } END { exit !found }'; then
  echo "error: no adb device/emulator in 'device' state" >&2
  adb devices
  exit 1
fi

./gradlew :app:installDebug "-PBLAZEDB_SWIFT_BUILD=$SWIFT_BUILD" "${GRADLE_EXTRA[@]}"

PKG=com.blazedb.example
adb logcat -c || true
adb shell am start -n "$PKG/.MainActivity" >/dev/null

echo ">>> Waiting for JNI smoke UI (10s)..."
sleep 10

if adb logcat -d | grep -E "JNI smoke|BlazeDB|AndroidRuntime" | tail -30; then
  true
fi

echo
echo ">>> Check the app UI for 'JNI smoke result:' — positive = runtime CRUD ok, negative = error code"
echo ">>> Success criteria: smoke result >= 1"
