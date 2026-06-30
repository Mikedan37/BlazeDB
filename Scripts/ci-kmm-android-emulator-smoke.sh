#!/usr/bin/env bash
# CI/local: run KMM Android runtime smoke via instrumentation test on a running emulator/device.
#
# Env:
#   BLAZEDB_SWIFT_BUILD  — SwiftPM .build with libBlazeDBAndroidBridge.so (required unless CI runs docker fallback)
#   ANDROID_HOME         — optional; mac setup script sets default
#   CI_EMULATOR_MANAGED  — set to 1 when reactivecircus/android-emulator-runner already booted the AVD
#   CI_ALLOW_DOCKER_CROSS_COMPILE — set to 1 to allow Docker cross-compile when .so is missing (local prove path)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/Examples/android"
SWIFT_BUILD="${BLAZEDB_SWIFT_BUILD:-$ROOT/.build}"
JAVA_HOME="${JAVA_HOME:-${JAVA_HOME_17:-}}"
if [[ -z "$JAVA_HOME" ]] && [[ -d "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ]]; then
  JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
fi
if [[ -n "$JAVA_HOME" ]]; then
  export JAVA_HOME
fi

SO="$SWIFT_BUILD/aarch64-unknown-linux-android28/debug/libBlazeDBAndroidBridge.so"
if [[ ! -f "$SO" ]]; then
  if [[ "${CI_ALLOW_DOCKER_CROSS_COMPILE:-0}" == "1" ]]; then
    echo ">>> Missing $SO — Docker cross-compile"
    "$ROOT/Scripts/prove-android-runtime-docker-crosscompile.sh"
  else
    echo "error: missing Swift Android bridge: $SO" >&2
    echo "       Set BLAZEDB_SWIFT_BUILD or run ./Scripts/ci-android-cross-compile.sh first." >&2
    exit 1
  fi
fi

chmod +x "$ROOT"/Scripts/*.sh "$ANDROID_DIR"/scripts/*.sh 2>/dev/null || true

if [[ -z "${ANDROID_HOME:-}" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    "$ROOT/Scripts/setup-android-gradle-sdk.sh"
    export ANDROID_HOME="${ANDROID_HOME:-$ROOT/.artifacts/android-gradle-sdk}"
  else
    echo "error: ANDROID_HOME must be set on non-macOS hosts" >&2
    exit 1
  fi
fi

export ANDROID_HOME
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

cd "$ANDROID_DIR"
if [[ ! -x ./gradlew ]]; then
  echo "error: missing Examples/android/gradlew — run gradle wrapper locally first" >&2
  exit 1
fi

if [[ "${CI_EMULATOR_MANAGED:-0}" != "1" ]]; then
  adb kill-server 2>/dev/null || true
  adb start-server
else
  adb wait-for-device
  for _ in $(seq 1 90); do
    boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    [[ "$boot" == "1" ]] && break
    sleep 2
  done
  adb devices -l
fi

if [[ "${CI_EMULATOR_MANAGED:-0}" != "1" ]]; then
  AVD_NAME="${BLAZEDB_AVD_NAME:-blazedb_arm64_api34}"
  if ! avdmanager list avd 2>/dev/null | grep -q "$AVD_NAME"; then
    echo "no" | avdmanager create avd -n "$AVD_NAME" -k "system-images;android-34;google_apis;arm64-v8a" -d pixel_6 || true
  fi
  if ! adb devices | awk 'NR>1 && $2=="device" { found=1 } END { exit !found }'; then
    echo ">>> Starting emulator ($AVD_NAME)"
    nohup emulator -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect -accel off >/tmp/blazedb-emulator.log 2>&1 &
    adb wait-for-device
    for _ in $(seq 1 90); do
      boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
      [[ "$boot" == "1" ]] && break
      sleep 2
    done
  fi
fi

echo ">>> Gradle connectedDebugAndroidTest (KMM BlazeDB runtime)"
./gradlew :app:connectedDebugAndroidTest "-PBLAZEDB_SWIFT_BUILD=$SWIFT_BUILD"

echo ">>> KMM Android RUNTIME OK (instrumentation test)"
