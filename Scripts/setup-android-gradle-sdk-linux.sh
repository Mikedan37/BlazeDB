#!/usr/bin/env bash
# Install Android SDK command-line tools for Gradle on Linux (CI).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=android-swift-config.sh
source "$ROOT/Scripts/android-swift-config.sh"

ANDROID_HOME="${ANDROID_HOME:-$ROOT/.artifacts/android-gradle-sdk-linux}"
CMDLINE="$ANDROID_HOME/cmdline-tools/latest"
SDKMANAGER="$CMDLINE/bin/sdkmanager"

mkdir -p "$ANDROID_HOME"

if [[ ! -x "$SDKMANAGER" ]]; then
  echo ">>> Downloading Android command-line tools (Linux)"
  tmp="$(mktemp -d)"
  curl -fSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o "$tmp/cmdline-tools.zip"
  unzip -qo "$tmp/cmdline-tools.zip" -d "$tmp"
  rm -rf "$ANDROID_HOME/cmdline-tools"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  mv "$tmp/cmdline-tools" "$CMDLINE"
  rm -rf "$tmp"
fi

export ANDROID_HOME
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$CMDLINE/bin:$PATH"

yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true

PACKAGES=(
  "platform-tools"
  "platforms;android-34"
  "build-tools;34.0.0"
)
if [[ "${BLAZEDB_ANDROID_SDK_INSTALL_EMULATOR:-0}" == "1" ]]; then
  PACKAGES+=(
    "emulator"
    "system-images;android-34;google_apis;x86_64"
  )
fi
"$SDKMANAGER" "${PACKAGES[@]}"

echo ">>> Android Gradle SDK (Linux) ready at $ANDROID_HOME"
