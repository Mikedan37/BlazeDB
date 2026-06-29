#!/usr/bin/env bash
# Build and verify KMM consumer artifacts: Android AAR + native libs, iOS XCFramework.
#
# Usage:
#   ./Scripts/package-kmm-artifacts.sh [--verify-only]
#
# Env:
#   BLAZEDB_SWIFT_BUILD — path to SwiftPM .build with Android libBlazeDBAndroidBridge.so
#   DIST_DIR            — output root (default: dist/kmm)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/Examples/android"
SWIFT_BUILD="${BLAZEDB_SWIFT_BUILD:-$ROOT/.build}"
DIST="${DIST_DIR:-$ROOT/dist/kmm}"
VERIFY_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --verify-only) VERIFY_ONLY=1 ;;
    *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
  esac
done

android_swift_runtime_dir() {
  # shellcheck source=android-swift-config.sh
  source "$ROOT/Scripts/android-swift-config.sh"
  local cache_dir="${BLAZEDB_ANDROID_SDK_CACHE_DIR:-$ROOT/.artifacts/android-sdk}"
  echo "$cache_dir/${BLAZEDB_ANDROID_SDK_ARTIFACT%.tar.gz}/swift-android/swift-resources/usr/lib/swift-aarch64/android"
}

if [[ "$VERIFY_ONLY" == "0" ]]; then
  SO="$SWIFT_BUILD/aarch64-unknown-linux-android28/debug/libBlazeDBAndroidBridge.so"
  if [[ ! -f "$SO" ]]; then
    echo "error: missing $SO — run ./Scripts/ci-android-cross-compile.sh first" >&2
    exit 1
  fi

  echo "=== iOS static bridge + release frameworks ==="
  "$ROOT/Scripts/build-kmm-ios-bridge.sh"
  cd "$ANDROID_DIR"
  chmod +x gradlew
  ./gradlew \
    :shared:linkReleaseFrameworkIosArm64 \
    :shared:linkReleaseFrameworkIosSimulatorArm64

  IOS_DEVICE_FW="$ANDROID_DIR/shared/build/bin/iosArm64/releaseFramework/BlazeDBKMM.framework"
  IOS_SIM_FW="$ANDROID_DIR/shared/build/bin/iosSimulatorArm64/releaseFramework/BlazeDBKMM.framework"
  mkdir -p "$DIST/ios"
  rm -rf "$DIST/ios/BlazeDBKMM.xcframework"
  xcodebuild -create-xcframework \
    -framework "$IOS_DEVICE_FW" \
    -framework "$IOS_SIM_FW" \
    -output "$DIST/ios/BlazeDBKMM.xcframework"

  echo "=== Android release AAR + native libs + Maven local repo ==="
  ./gradlew \
    :shared:assembleRelease \
    :shared:publishReleasePublicationToBlazeDBLocalRepository \
    :app:assembleRelease \
    "-PBLAZEDB_SWIFT_BUILD=$SWIFT_BUILD"

  NATIVE_MERGED="$ANDROID_DIR/app/build/intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/lib/arm64-v8a"
  if [[ ! -d "$NATIVE_MERGED" ]]; then
    echo "error: expected native libs at $NATIVE_MERGED" >&2
    exit 1
  fi

  mkdir -p "$DIST/android/jni/arm64-v8a"
  cp "$ANDROID_DIR/shared/build/outputs/aar/shared-release.aar" "$DIST/android/BlazeDBKMM-release.aar"
  cp "$NATIVE_MERGED"/*.so "$DIST/android/jni/arm64-v8a/"

  cat > "$DIST/android/README.txt" <<EOF
BlazeDB KMM Android bundle (integration scaffolding)

Files:
  BlazeDBKMM-release.aar     — Kotlin Multiplatform shared module
  jni/arm64-v8a/*.so         — JNI shim + Swift bridge + Swift runtime (arm64-v8a)

Requires minSdk 28. Link the AAR in Gradle and copy jni/arm64-v8a into your app's jniLibs.
See Examples/android/ and Docs/GettingStarted/KMM_GETTING_STARTED.md.
EOF

  cp "$ANDROID_DIR/shared/BlazeDBKMM.podspec" "$DIST/ios/BlazeDBKMM.podspec"

  echo ">>> Maven local repo: $ROOT/dist/maven/com/blazedb/blazedb-kmm/0.1.0/"

  echo ">>> Packaged KMM artifacts under $DIST"
fi

echo "=== Verify packaging ==="
"$ROOT/Scripts/verify-kmm-packaging.sh" "$DIST"
