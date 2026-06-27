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

install_linux_ubuntu2204() {
  local install_dir="${BLAZEDB_ANDROID_SWIFT_INSTALL_DIR:-$ROOT/.swift-host}"
  local bundle="swift-${BLAZEDB_ANDROID_SWIFT_RELEASE_TAG}-ubuntu22.04"
  local tarball="${bundle}.tar.gz"
  local url="https://download.swift.org/swift-${BLAZEDB_ANDROID_HOST_SWIFT_VERSION}-release/ubuntu2204/${BLAZEDB_ANDROID_SWIFT_RELEASE_TAG}/${tarball}"

  mkdir -p "$install_dir"
  if [[ -x "$install_dir/$bundle/usr/bin/swift" ]]; then
    echo ">>> Reusing cached OSS Swift at $install_dir/$bundle"
  else
    echo ">>> Downloading OSS Swift ${BLAZEDB_ANDROID_HOST_SWIFT_VERSION} for ubuntu22.04"
    curl -fSL "$url" -o "$install_dir/$tarball"
    tar -xzf "$install_dir/$tarball" -C "$install_dir"
    rm -f "$install_dir/$tarball"
  fi

  export PATH="$install_dir/$bundle/usr/bin:$PATH"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$install_dir/$bundle/usr/bin" >> "$GITHUB_PATH"
  fi
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
  *)
    echo "error: automatic OSS Swift install is supported on Linux x86_64 (CI ubuntu-22.04)." >&2
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
