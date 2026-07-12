#!/usr/bin/env bash
# Shared Android cross-compile toolchain pins.
# Source from install-android-swift.sh and ci-android-cross-compile.sh.
# Bump BLAZEDB_ANDROID_HOST_SWIFT_VERSION when upgrading the Android SDK bundle.

readonly BLAZEDB_ANDROID_HOST_SWIFT_VERSION="6.3.2"
readonly BLAZEDB_ANDROID_SWIFT_RELEASE_TAG="${BLAZEDB_ANDROID_HOST_SWIFT_VERSION}-RELEASE"
readonly BLAZEDB_ANDROID_SDK_ARTIFACT="swift-${BLAZEDB_ANDROID_SWIFT_RELEASE_TAG}_android.artifactbundle.tar.gz"
readonly BLAZEDB_ANDROID_SDK_NAME="swift-${BLAZEDB_ANDROID_SWIFT_RELEASE_TAG}_android"
readonly BLAZEDB_ANDROID_SDK_URL="https://download.swift.org/swift-${BLAZEDB_ANDROID_HOST_SWIFT_VERSION}-release/android-sdk/swift-${BLAZEDB_ANDROID_SWIFT_RELEASE_TAG}/${BLAZEDB_ANDROID_SDK_ARTIFACT}"
# swift.org CDN often 404s from GitHub Actions; mirror is the official tarball re-hosted on GitHub Releases.
readonly BLAZEDB_ANDROID_SDK_MIRROR_URL="https://github.com/Mikedan37/BlazeDB/releases/download/ci-android-sdk-${BLAZEDB_ANDROID_HOST_SWIFT_VERSION}/${BLAZEDB_ANDROID_SDK_ARTIFACT}"
readonly BLAZEDB_ANDROID_SDK_CHECKSUM="939e933549d12d28f2e0bf71019d734d309859e9773c572657ce565a81f85d68"
readonly BLAZEDB_ANDROID_SDK_MIN_BYTES=300000000
# Host OSS Swift (ubuntu22.04 x86_64) — required for Android cross-compile; same CDN flake as the SDK.
readonly BLAZEDB_ANDROID_HOST_SWIFT_TARBALL="swift-${BLAZEDB_ANDROID_SWIFT_RELEASE_TAG}-ubuntu22.04.tar.gz"
readonly BLAZEDB_ANDROID_HOST_SWIFT_URL="https://download.swift.org/swift-${BLAZEDB_ANDROID_HOST_SWIFT_VERSION}-release/ubuntu2204/${BLAZEDB_ANDROID_SWIFT_RELEASE_TAG}/${BLAZEDB_ANDROID_HOST_SWIFT_TARBALL}"
readonly BLAZEDB_ANDROID_HOST_SWIFT_MIRROR_URL="https://github.com/Mikedan37/BlazeDB/releases/download/ci-android-sdk-${BLAZEDB_ANDROID_HOST_SWIFT_VERSION}/${BLAZEDB_ANDROID_HOST_SWIFT_TARBALL}"
readonly BLAZEDB_ANDROID_HOST_SWIFT_CHECKSUM="8f75740dc534d3b0a885aecd6a66274b37ba8ed52108b99cdcb0284f53d9eeed"
readonly BLAZEDB_ANDROID_HOST_SWIFT_MIN_BYTES=500000000
readonly BLAZEDB_ANDROID_SWIFT_TRIPLE="aarch64-unknown-linux-android28"
readonly BLAZEDB_ANDROID_SWIFT_TRIPLE_X86_64="x86_64-unknown-linux-android28"
readonly BLAZEDB_ANDROID_NDK_VERSION="r27d"

android_swift_runtime_dir_for_triple() {
  local triple="${1:-$BLAZEDB_ANDROID_SWIFT_TRIPLE}"
  local subdir
  case "$triple" in
    x86_64-*) subdir="swift-x86_64" ;;
    aarch64-*) subdir="swift-aarch64" ;;
    *) echo "error: unknown Android Swift triple: $triple" >&2; return 1 ;;
  esac
  local cache_dir="${BLAZEDB_ANDROID_SDK_CACHE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.artifacts/android-sdk}"
  echo "$cache_dir/${BLAZEDB_ANDROID_SDK_ARTIFACT%.tar.gz}/swift-android/swift-resources/usr/lib/${subdir}/android"
}

android_abi_for_triple() {
  case "${1:-}" in
    x86_64-*) echo "x86_64" ;;
    aarch64-*) echo "arm64-v8a" ;;
    *) echo "error: unknown triple: $1" >&2; return 1 ;;
  esac
}

verify_android_sdk_artifact() {
  local tarball_path="$1"
  if [[ ! -f "$tarball_path" ]]; then
    return 1
  fi

  local size
  size="$(wc -c < "$tarball_path" | tr -d ' ')"
  if [[ "$size" -lt "$BLAZEDB_ANDROID_SDK_MIN_BYTES" ]]; then
    echo "error: Android SDK artifact too small (${size} bytes) — likely a CDN 404 page" >&2
    return 1
  fi

  local actual
  actual="$(shasum -a 256 "$tarball_path" | awk '{print $1}')"
  if [[ "$actual" != "$BLAZEDB_ANDROID_SDK_CHECKSUM" ]]; then
    echo "error: Android SDK artifact checksum mismatch" >&2
    echo "       expected: $BLAZEDB_ANDROID_SDK_CHECKSUM" >&2
    echo "       actual:   $actual" >&2
    return 1
  fi

  return 0
}

download_android_sdk_artifact() {
  local tarball_path="$1"
  local attempt url urls=()

  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    urls=("$BLAZEDB_ANDROID_SDK_MIRROR_URL" "$BLAZEDB_ANDROID_SDK_URL")
  else
    urls=("$BLAZEDB_ANDROID_SDK_URL" "$BLAZEDB_ANDROID_SDK_MIRROR_URL")
  fi

  for attempt in 1 2 3 4 5; do
    for url in "${urls[@]}"; do
      echo ">>> Downloading Android Swift SDK artifact (attempt ${attempt}/5)"
      echo ">>> URL: $url"
      rm -f "$tarball_path"
      if curl -fSL \
        --retry 3 \
        --retry-all-errors \
        --retry-delay 5 \
        --connect-timeout 30 \
        --max-time 1800 \
        "$url" \
        -o "$tarball_path"; then
        if verify_android_sdk_artifact "$tarball_path"; then
          return 0
        fi
      fi
      rm -f "$tarball_path"
    done
    sleep $((attempt * 5))
  done

  echo "error: failed to download a valid Android Swift SDK artifact from swift.org or GitHub mirror" >&2
  return 1
}
