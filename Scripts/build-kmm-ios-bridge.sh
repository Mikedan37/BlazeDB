#!/usr/bin/env bash
# Build BlazeDBKMMBridgeStatic for KMM iOS targets (device + simulator).
#
# Output layout (linker search paths for :shared/build.gradle.kts):
#   .build/kmm-ios-bridge/iosArm64/libBlazeDBAndroidBridge.a
#   .build/kmm-ios-bridge/iosSimulatorArm64/libBlazeDBAndroidBridge.a
#
# Requires Xcode Swift on macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT_ROOT="$ROOT/.build/kmm-ios-bridge"
mkdir -p "$OUT_ROOT"

build_for() {
  local sdk="$1"
  local triple="$2"
  local out_name="$3"
  local dest="$OUT_ROOT/$out_name"
  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  local build_path="$ROOT/.build/kmm-ios-bridge/swift-build-$out_name"

  echo ">>> Building BlazeDBKMMBridgeStatic for $sdk ($triple) → $dest"
  rm -rf "$dest" "$build_path"
  mkdir -p "$dest"

  SWIFT_DETERMINISTIC_HASHING=1 swift build \
    -c release \
    --product BlazeDBKMMBridgeStatic \
    --build-path "$build_path" \
    --sdk "$sdk_path" \
    --triple "$triple"

  local lib
  lib="$(find "$build_path" -name 'libBlazeDBKMMBridgeStatic.a' -print -quit)"
  if [[ -z "$lib" ]]; then
    lib="$(find "$build_path" -name 'libBlazeDBAndroidBridge.a' -print -quit)"
  fi
  if [[ -z "$lib" ]]; then
    echo "error: static BlazeDB bridge library not found under $build_path" >&2
    find "$build_path" -name '*.a' | head -20 >&2 || true
    exit 1
  fi

  cp "$lib" "$dest/libBlazeDBAndroidBridge.a"
  echo ">>> Installed libBlazeDBAndroidBridge.a in $dest"
}

build_for iphoneos arm64-apple-ios15.0 iosArm64
build_for iphonesimulator arm64-apple-ios15.0-simulator iosSimulatorArm64

echo ">>> KMM iOS bridge libraries ready under $OUT_ROOT"
