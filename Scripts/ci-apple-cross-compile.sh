#!/usr/bin/env bash
# Cross-compile BlazeDBCore for Apple platforms declared in Package.swift.
#
# COMPILE-ONLY — do not add XCTest, simulator boot, or xcodebuild test here.
# Runtime validation stays in the macOS Tier0/Tier1 job (and future Phase 2
# iOS Simulator nightly if we add it). This job answers one question only:
# "Does BlazeDBCore still build for every Apple OS we claim to support?"
#
# Requires Xcode Swift — not OSS Swift. See Docs/Testing/CI_AND_TEST_TIERS.md.
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

fail_with_summary() {
  print_summary
  exit 1
}

# ─── Platform registry ───────────────────────────────────────────────────────
# When Package.swift `platforms:` gains a new Apple OS, add cross-compile
# targets below and update Docs/Testing/CI_AND_TEST_TIERS.md.
# assert_package_platforms_covered() fails CI until this list is updated.
COVERED_APPLE_PLATFORMS=(
  macOS
  iOS
  watchOS
  tvOS
  visionOS
)

assert_package_platforms_covered() {
  local package_file="$ROOT/Package.swift"
  local -a declared=()
  local -a uncovered=()
  local platform covered

  while IFS= read -r platform; do
    [[ -n "$platform" ]] && declared+=("$platform")
  done < <(
    grep -oE '\.(macOS|iOS|watchOS|tvOS|visionOS)\(' "$package_file" \
      | sed 's/^\.//;s/(//' \
      | sort -u
  )

  if [[ ${#declared[@]} -eq 0 ]]; then
    echo "error: could not read Apple platforms from ${package_file}" >&2
    exit 1
  fi

  for platform in "${declared[@]}"; do
    covered=0
    for known in "${COVERED_APPLE_PLATFORMS[@]}"; do
      if [[ "$platform" == "$known" ]]; then
        covered=1
        break
      fi
    done
    if [[ "$covered" -eq 0 ]]; then
      uncovered+=("$platform")
    fi
  done

  if [[ ${#uncovered[@]} -gt 0 ]]; then
    echo "error: Package.swift declares Apple platform(s) not covered by this script: ${uncovered[*]}" >&2
    echo "       Add cross-compile targets to Scripts/ci-apple-cross-compile.sh" >&2
    echo "       and document the lane in Docs/Testing/CI_AND_TEST_TIERS.md." >&2
    exit 1
  fi
}

is_known_visionos_toolchain_skip() {
  local log_file="$1"
  # SwiftPM cannot resolve/build for xros triples on some toolchains yet.
  grep -qE 'unknown os|Cannot create dynamic libraries|Triple\+Basics' "$log_file"
}

echo ">>> Swift host toolchain"
xcodebuild -version
swift --version

if ! swift --version 2>&1 | grep -q "Apple Swift"; then
  echo "error: Apple cross-compilation requires Xcode's Swift toolchain, not OSS Swift." >&2
  echo "       Use the macOS runner's default swift (see .github/workflows/ci.yml)." >&2
  exit 1
fi

assert_package_platforms_covered

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
  local log_file="$4"

  echo ">>> Cross-compile BlazeDBCore for ${label}"
  echo "    sdk=${sdk} triple=${triple}"

  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

  rm -rf .build
  swift build \
    --target BlazeDBCore \
    --triple "$triple" \
    --sdk "$sdk_path" \
    2>&1 | tee "$log_file"
}

build_required_platform() {
  local label="$1"
  local sdk="$2"
  local triple="$3"
  local log_file
  log_file="$(mktemp "${TMPDIR:-/tmp}/blazedb-apple-cross.XXXXXX")"

  if cross_compile_blazedb_core "$label" "$sdk" "$triple" "$log_file"; then
    record_status "✅ ${label}"
    rm -f "$log_file"
    return 0
  fi

  echo "error: ${label} cross-compile FAILED (unexpected — blocking platform)." >&2
  echo "       This is not a visionOS-style toolchain skip. Last 40 log lines:" >&2
  tail -40 "$log_file" >&2
  record_status "❌ ${label} failed (unexpected)"
  rm -f "$log_file"
  fail_with_summary
}

# label:sdk:triple — minimum OS versions match Package.swift platforms.
# Add new required (non-visionOS) targets here when Package.swift grows.
APPLE_CROSS_COMPILE_TARGETS=(
  "iOS Simulator:iphonesimulator:arm64-apple-ios15.0-simulator"
  "iOS Device:iphoneos:arm64-apple-ios15.0"
  "watchOS Simulator:watchsimulator:arm64-apple-watchos8.0-simulator"
  "watchOS Device:watchos:arm64_32-apple-watchos8.0"
  "tvOS Simulator:appletvsimulator:arm64-apple-tvos15.0-simulator"
  "tvOS Device:appletvos:arm64-apple-tvos15.0"
)

# visionOS is optional until SwiftPM supports xros triples everywhere.
# Set BLAZEDB_APPLE_REQUIRE_VISIONOS=1 to treat success as mandatory.
VISIONOS_TARGETS=(
  "visionOS Simulator:xrsimulator:arm64-apple-xros1.0-simulator"
  "visionOS Device:xros:arm64-apple-xros1.0"
)

visionos_ok=0
visionos_toolchain_skip=0
visionos_unexpected_fail=0

build_native_macos

for entry in "${APPLE_CROSS_COMPILE_TARGETS[@]}"; do
  IFS=: read -r label sdk triple <<< "$entry"
  build_required_platform "$label" "$sdk" "$triple"
done

for entry in "${VISIONOS_TARGETS[@]}"; do
  IFS=: read -r label sdk triple <<< "$entry"
  log_file="$(mktemp "${TMPDIR:-/tmp}/blazedb-apple-visionos.XXXXXX")"

  if cross_compile_blazedb_core "$label" "$sdk" "$triple" "$log_file"; then
    record_status "✅ ${label}"
    visionos_ok=1
  elif is_known_visionos_toolchain_skip "$log_file"; then
    echo "note: ${label} skipped — SwiftPM/toolchain does not support xros triples on this runner." >&2
    visionos_toolchain_skip=1
  else
    echo "error: ${label} FAILED (unexpected compile error — not a toolchain skip)." >&2
    echo "       Last 40 log lines:" >&2
    tail -40 "$log_file" >&2
    record_status "❌ ${label} failed (unexpected)"
    visionos_unexpected_fail=1
  fi

  rm -f "$log_file"
done

if [[ "$visionos_unexpected_fail" -eq 1 ]]; then
  echo "error: visionOS produced unexpected compile failures." >&2
  fail_with_summary
fi

if [[ "$visionos_ok" -eq 0 ]]; then
  if [[ "${BLAZEDB_APPLE_REQUIRE_VISIONOS:-0}" == "1" ]]; then
    echo "error: visionOS cross-compile required (BLAZEDB_APPLE_REQUIRE_VISIONOS=1) but did not succeed." >&2
    fail_with_summary
  fi
  if [[ "$visionos_toolchain_skip" -eq 1 ]]; then
    record_status "⚠️ visionOS skipped (SwiftPM/toolchain — not a compile failure)"
  else
    record_status "⚠️ visionOS skipped (no targets attempted)"
  fi
fi

print_summary
echo ">>> Apple cross-compile: ok"
