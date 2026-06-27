#!/usr/bin/env bash
# Download and verify the Swift Android SDK tarball for CI caching/artifact handoff.
# swift.org CDN edges on GitHub ubuntu-22.04 often 404 this artifact; macos-15 can fetch it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=android-swift-config.sh
source "$ROOT/Scripts/android-swift-config.sh"

cache_dir="${BLAZEDB_ANDROID_SDK_CACHE_DIR:-$ROOT/.artifacts/android-sdk}"
tarball_path="$cache_dir/$BLAZEDB_ANDROID_SDK_ARTIFACT"
mkdir -p "$cache_dir"

if [[ -f "$tarball_path" ]] && verify_android_sdk_artifact "$tarball_path"; then
  echo ">>> Reusing verified Android Swift SDK artifact at $tarball_path"
  exit 0
fi

download_android_sdk_artifact "$tarball_path"
echo ">>> Android Swift SDK artifact ready at $tarball_path"
