#!/usr/bin/env bash
# Install Android SDK command-line tools for Gradle (platform-tools, platforms, build-tools, NDK).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=android-swift-config.sh
source "$ROOT/Scripts/android-swift-config.sh"

ANDROID_HOME="${ANDROID_HOME:-$ROOT/.artifacts/android-gradle-sdk}"
CMDLINE="$ANDROID_HOME/cmdline-tools/latest"
SDKMANAGER="$CMDLINE/bin/sdkmanager"

mkdir -p "$ANDROID_HOME"

if [[ ! -x "$SDKMANAGER" ]]; then
  echo ">>> Downloading Android command-line tools"
  tmp="$(mktemp -d)"
  curl -fSL "https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip" -o "$tmp/cmdline-tools.zip"
  unzip -qo "$tmp/cmdline-tools.zip" -d "$tmp"
  rm -rf "$ANDROID_HOME/cmdline-tools"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  mv "$tmp/cmdline-tools" "$CMDLINE"
  rm -rf "$tmp"
fi

export ANDROID_HOME
export PATH="$CMDLINE/bin:$ANDROID_HOME/platform-tools:$PATH"

yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
"$SDKMANAGER" \
  "platform-tools" \
  "platforms;android-34" \
  "build-tools;34.0.0" \
  "ndk;27.0.12077973" \
  "system-images;android-34;google_apis;arm64-v8a" \
  "emulator"

echo ">>> Android Gradle SDK ready at $ANDROID_HOME"
echo ">>> adb: $(command -v adb)"
