#!/usr/bin/env bash
# Cross-compile BlazeDBCore + BlazeDBAndroidBridge for Android inside Linux Docker (macOS hosts).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=android-swift-config.sh
source "$ROOT/Scripts/android-swift-config.sh"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker required" >&2
  exit 1
fi

docker info >/dev/null 2>&1 || {
  echo "error: Docker daemon not running — start Docker Desktop" >&2
  exit 1
}

INSTALL_DIR="${BLAZEDB_ANDROID_SWIFT_INSTALL_DIR:-$ROOT/.swift-host}"
BUNDLE="swift-${BLAZEDB_ANDROID_SWIFT_RELEASE_TAG}-ubuntu22.04"
TARBALL="${BUNDLE}.tar.gz"
URL="https://download.swift.org/swift-${BLAZEDB_ANDROID_HOST_SWIFT_VERSION}-release/ubuntu2204/${BLAZEDB_ANDROID_SWIFT_RELEASE_TAG}/${TARBALL}"

mkdir -p "$INSTALL_DIR"
if [[ ! -x "$INSTALL_DIR/$BUNDLE/usr/bin/swift" ]]; then
  echo ">>> Downloading OSS Swift ${BLAZEDB_ANDROID_HOST_SWIFT_VERSION} for ubuntu22.04 (linux/amd64, ~1GB)"
  curl -fSL "$URL" -o "$INSTALL_DIR/$TARBALL"
  tar -xzf "$INSTALL_DIR/$TARBALL" -C "$INSTALL_DIR"
  rm -f "$INSTALL_DIR/$TARBALL"
fi

echo ">>> Docker cross-compile (ubuntu:22.04 linux/amd64)"
docker run --rm \
  --platform linux/amd64 \
  -v "$ROOT:/work" \
  -w /work \
  -e DEBIAN_FRONTEND=noninteractive \
  -e PATH="/work/.swift-host/$BUNDLE/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  ubuntu:22.04 \
  bash -lc '
    set -euo pipefail
    apt-get update -qq
    apt-get install -y -qq curl git unzip ca-certificates libatomic1 libstdc++6 libcurl4 libxml2 binutils clang
    chmod +x Scripts/*.sh
    swift --version
    ./Scripts/fetch-android-sdk-artifact.sh
    ./Scripts/ci-android-cross-compile.sh
  '

echo ">>> Docker cross-compile: ok (.build/aarch64-unknown-linux-android28/debug)"
