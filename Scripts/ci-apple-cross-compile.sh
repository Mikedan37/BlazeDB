#!/usr/bin/env bash
# Cross-compile BlazeDBCore for Apple platforms (macOS, iOS, watchOS, tvOS, visionOS).
# Requires Xcode Swift — not OSS Swift. Compile-only; no simulator runtime or XCTest.
# See Docs/Testing/CI_AND_TEST_TIERS.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SUMMARY_LINES=()

record_status() {
  SUMMARY_LINES+=("$1")
}

print_summary() {
  echo ""
  echo "Apple Cross-Compile"
  local line
  for line in "${SUMMARY_LINES[@]}"; do
    echo "$line"
  done
  echo ""
}

echo ">>> Swift host toolchain"
xcodebuild -version
swift --version

if ! swift --version 2>&1 | grep -q "Apple Swift"; then
  echo "error: Apple cross-compilation requires Xcode's Swift toolchain, not OSS Swift." >&2
  echo "       Use the macOS runner's default swift (see .github/workflows/ci.yml)." >&2
  exit 1
fi

build_native_macos() {
  echo ">>> Build BlazeDBCore for macOS (native)"
  rm -rf .build
  swift build --target BlazeDBCore
  record_status "✅ macOS"
}

cross_compile_blazedb_core() {
  local label="$1"
  local sdk="$2"
  local triple="$3"

  echo ">>> Cross-compile BlazeDBCore for ${label}"
  echo "    sdk=${sdk} triple=${triple}"

  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

  rm -rf .build
  swift build \
    --target BlazeDBCore \
    --triple "$triple" \
    --sdk "$sdk_path"
}

# label:sdk:triple — minimum OS versions match Package.swift platforms.
APPLE_CROSS_COMPILE_TARGETS=(
  "iOS Simulator:iphonesimulator:arm64-apple-ios15.0-simulator"
  "iOS Device:iphoneos:arm64-apple-ios15.0"
  "watchOS Simulator:watchsimulator:arm64-apple-watchos8.0-simulator"
  "watchOS Device:watchos:arm64_32-apple-watchos8.0"
  "tvOS Simulator:appletvsimulator:arm64-apple-tvos15.0-simulator"
  "tvOS Device:appletvos:arm64-apple-tvos15.0"
)

visionos_ok=0

build_native_macos

for entry in "${APPLE_CROSS_COMPILE_TARGETS[@]}"; do
  IFS=: read -r label sdk triple <<< "$entry"
  cross_compile_blazedb_core "$label" "$sdk" "$triple"
  record_status "✅ ${label}"
done

# visionOS: attempt both simulator and device. SwiftPM historically fails dependency
# resolution for xros triples on some toolchains; allow opt-in strictness via env.
VISIONOS_TARGETS=(
  "visionOS Simulator:xrsimulator:arm64-apple-xros1.0-simulator"
  "visionOS Device:xros:arm64-apple-xros1.0"
)

for entry in "${VISIONOS_TARGETS[@]}"; do
  IFS=: read -r label sdk triple <<< "$entry"
  if cross_compile_blazedb_core "$label" "$sdk" "$triple"; then
    record_status "✅ ${label}"
    visionos_ok=1
  else
    echo "warning: ${label} cross-compile failed (SwiftPM may not recognize xros triples yet)." >&2
  fi
done

if [[ "$visionos_ok" -eq 0 ]]; then
  if [[ "${BLAZEDB_APPLE_REQUIRE_VISIONOS:-0}" == "1" ]]; then
    echo "error: visionOS cross-compile required but failed." >&2
    print_summary
    exit 1
  fi
  record_status "⚠️ visionOS skipped"
fi

print_summary
echo ">>> Apple cross-compile: ok"
