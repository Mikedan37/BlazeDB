#!/usr/bin/env bash
# Install the OSS Swift host toolchain required for Android cross-compilation.
# CI calls this before ci-android-cross-compile.sh; local contributors can run it too.
# Version pins live in android-swift-config.sh — update there when Swift/Android SDK bumps.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=android-swift-config.sh
source "$ROOT/Scripts/android-swift-config.sh"

host_swift_is_usable() {
  command -v swift >/dev/null 2>&1 \
    && swift --version 2>&1 | grep -q "Swift version ${BLAZEDB_ANDROID_HOST_SWIFT_VERSION}" \
    && ! swift --version 2>&1 | grep -q "Apple Swift"
}

verify_host_swift_tarball() {
  local tarball_path="$1"
  if [[ ! -f "$tarball_path" ]]; then
    return 1
  fi

  local size
  size="$(wc -c < "$tarball_path" | tr -d ' ')"
  if [[ "$size" -lt "$BLAZEDB_ANDROID_HOST_SWIFT_MIN_BYTES" ]]; then
    echo "error: host Swift tarball too small (${size} bytes) — likely a CDN 404 page" >&2
    return 1
  fi

  local actual
  actual="$(shasum -a 256 "$tarball_path" | awk '{print $1}')"
  if [[ "$actual" != "$BLAZEDB_ANDROID_HOST_SWIFT_CHECKSUM" ]]; then
    echo "error: host Swift tarball checksum mismatch" >&2
    echo "       expected: $BLAZEDB_ANDROID_HOST_SWIFT_CHECKSUM" >&2
    echo "       actual:   $actual" >&2
    return 1
  fi

  return 0
}

download_host_swift_tarball() {
  local tarball_path="$1"
  local attempt url urls=()

  # Same CDN flake as the Android SDK: prefer GitHub mirror on Actions.
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    urls=("$BLAZEDB_ANDROID_HOST_SWIFT_MIRROR_URL" "$BLAZEDB_ANDROID_HOST_SWIFT_URL")
  else
    urls=("$BLAZEDB_ANDROID_HOST_SWIFT_URL" "$BLAZEDB_ANDROID_HOST_SWIFT_MIRROR_URL")
  fi

  for attempt in 1 2 3 4 5; do
    for url in "${urls[@]}"; do
      echo ">>> Downloading OSS Swift ${BLAZEDB_ANDROID_HOST_SWIFT_VERSION} for ubuntu22.04 (attempt ${attempt}/5)"
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
        if verify_host_swift_tarball "$tarball_path"; then
          return 0
        fi
      fi
      rm -f "$tarball_path"
    done
    sleep $((attempt * 5))
  done

  echo "error: failed to download a valid OSS Swift host toolchain from GitHub mirror or swift.org" >&2
  return 1
}

install_linux_ubuntu2204() {
  local install_dir="${BLAZEDB_ANDROID_SWIFT_INSTALL_DIR:-$ROOT/.swift-host}"
  local bundle="swift-${BLAZEDB_ANDROID_SWIFT_RELEASE_TAG}-ubuntu22.04"
  local tarball="${BLAZEDB_ANDROID_HOST_SWIFT_TARBALL}"

  mkdir -p "$install_dir"
  if [[ -x "$install_dir/$bundle/usr/bin/swift" ]]; then
    echo ">>> Reusing cached OSS Swift at $install_dir/$bundle"
  else
    download_host_swift_tarball "$install_dir/$tarball"
    tar -xzf "$install_dir/$tarball" -C "$install_dir"
    rm -f "$install_dir/$tarball"
  fi

  export PATH="$install_dir/$bundle/usr/bin:$PATH"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$install_dir/$bundle/usr/bin" >> "$GITHUB_PATH"
  fi
}

install_macos_aarch64() {
  echo "error: OSS Swift ${BLAZEDB_ANDROID_HOST_SWIFT_VERSION} macOS tarballs are not published on swift.org." >&2
  echo "       On macOS, cross-compile via Docker:" >&2
  echo "         ./Scripts/prove-android-runtime-docker-crosscompile.sh" >&2
  echo "       Or install the Swift ${BLAZEDB_ANDROID_HOST_SWIFT_VERSION} .pkg from https://www.swift.org/install/ and ensure" >&2
  echo "       \`swift --version\` shows OSS Swift (not Apple Swift) before running ci-android-cross-compile.sh." >&2
  exit 1
}

echo ">>> Android host Swift toolchain (target ${BLAZEDB_ANDROID_HOST_SWIFT_VERSION})"

if host_swift_is_usable; then
  echo ">>> OSS Swift ${BLAZEDB_ANDROID_HOST_SWIFT_VERSION} already on PATH"
  swift --version
  exit 0
fi

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    install_linux_ubuntu2204
    ;;
  Darwin-arm64)
    install_macos_aarch64
    ;;
  *)
    echo "error: automatic OSS Swift install is supported on Linux x86_64 and macOS arm64." >&2
    echo "       On other hosts, install Swift ${BLAZEDB_ANDROID_HOST_SWIFT_VERSION}+ from https://www.swift.org/install/" >&2
    echo "       then run ./Scripts/ci-android-cross-compile.sh" >&2
    exit 1
    ;;
esac

if ! host_swift_is_usable; then
  echo "error: OSS Swift ${BLAZEDB_ANDROID_HOST_SWIFT_VERSION} is not available after install." >&2
  exit 1
fi

swift --version
echo ">>> Android host Swift toolchain: ok"
