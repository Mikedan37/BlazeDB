#!/usr/bin/env bash
# Cross-compile BlazeDBCore + BlazeDBAndroidBridge for Android, then print Gradle hint.
set -euo pipefail

ANDROID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ANDROID_DIR/../.." && pwd)"

cd "$REPO_ROOT"
./Scripts/ci-android-cross-compile.sh

SWIFT_BUILD="$REPO_ROOT/.build"
echo
echo "Swift Android artifacts (if build succeeded):"
echo "  $SWIFT_BUILD/aarch64-unknown-linux-android28/debug"
echo
echo "Build the sample app with:"
echo "  cd Examples/android"
echo "  ./gradlew :app:assembleDebug -PBLAZEDB_SWIFT_BUILD=$SWIFT_BUILD"
echo
echo "Runtime smoke (device/emulator with adb):"
echo "  ./Scripts/run-android-runtime-smoke.sh -PBLAZEDB_SWIFT_BUILD=$SWIFT_BUILD"
