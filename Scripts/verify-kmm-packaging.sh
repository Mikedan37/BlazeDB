#!/usr/bin/env bash
# Verify KMM packaging layout produced by package-kmm-artifacts.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${1:-$ROOT/dist/kmm}"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -d "$DIST/ios/BlazeDBKMM.xcframework" ]] || fail "missing XCFramework at $DIST/ios/BlazeDBKMM.xcframework"
[[ -f "$DIST/ios/BlazeDBKMM.xcframework/Info.plist" ]] || fail "XCFramework Info.plist missing"

if ! /usr/libexec/PlistBuddy -c "Print :AvailableLibraries" "$DIST/ios/BlazeDBKMM.xcframework/Info.plist" 2>/dev/null | grep -q ios-arm64; then
  fail "XCFramework missing ios-arm64 slice"
fi
if ! /usr/libexec/PlistBuddy -c "Print :AvailableLibraries" "$DIST/ios/BlazeDBKMM.xcframework/Info.plist" 2>/dev/null | grep -q ios-arm64-simulator; then
  fail "XCFramework missing ios-arm64-simulator slice"
fi

[[ -f "$DIST/android/BlazeDBKMM-release.aar" ]] || fail "missing AAR at $DIST/android/BlazeDBKMM-release.aar"
[[ -f "$DIST/android/jni/arm64-v8a/libblazedb_android_bridge.so" ]] || fail "missing libblazedb_android_bridge.so"
[[ -f "$DIST/android/jni/arm64-v8a/libBlazeDBAndroidBridge.so" ]] || fail "missing libBlazeDBAndroidBridge.so"

echo ">>> KMM packaging verify OK ($DIST)"
