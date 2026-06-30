#!/usr/bin/env bash
# CI/local: run KMM Android runtime smoke via instrumentation test on a running emulator/device.
#
# Env:
#   BLAZEDB_SWIFT_BUILD  — SwiftPM .build with libBlazeDBAndroidBridge.so (required unless CI runs docker fallback)
#   BLAZEDB_ANDROID_ABIS — Gradle ABI filter (default arm64-v8a; CI Linux emulator uses x86_64)
#   ANDROID_HOME         — optional; mac setup script sets default
#   CI_EMULATOR_MANAGED  — set to 1 when reactivecircus/android-emulator-runner already booted the AVD
#   CI_ALLOW_DOCKER_CROSS_COMPILE — set to 1 to allow Docker cross-compile when .so is missing (local prove path)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/Examples/android"
SWIFT_BUILD="${BLAZEDB_SWIFT_BUILD:-$ROOT/.build}"
ANDROID_ABIS="${BLAZEDB_ANDROID_ABIS:-arm64-v8a}"
PRIMARY_ABI="${ANDROID_ABIS%%,*}"
PRIMARY_ABI="${PRIMARY_ABI//[[:space:]]/}"
JAVA_HOME="${JAVA_HOME:-${JAVA_HOME_17:-}}"
if [[ -z "$JAVA_HOME" ]] && [[ -d "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ]]; then
  JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
fi
if [[ -n "$JAVA_HOME" ]]; then
  export JAVA_HOME
fi

case "$PRIMARY_ABI" in
  x86_64) SWIFT_TRIPLE="x86_64-unknown-linux-android28" ;;
  arm64-v8a) SWIFT_TRIPLE="aarch64-unknown-linux-android28" ;;
  *)
    echo "error: unsupported BLAZEDB_ANDROID_ABIS entry: $PRIMARY_ABI" >&2
    exit 1
    ;;
esac

SO="$SWIFT_BUILD/$SWIFT_TRIPLE/debug/libBlazeDBAndroidBridge.so"
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
export ANDROID_SDK_ROOT="$ANDROID_HOME"
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
  case "$PRIMARY_ABI" in
    x86_64)
      AVD_NAME="${BLAZEDB_AVD_NAME:-blazedb_x86_64_api34}"
      SYSIMG="system-images;android-34;google_apis;x86_64"
      EMU_ACCEL=()
      if [[ "$(uname -s)" == "Linux" ]] && [[ -e /dev/kvm ]]; then
        EMU_ACCEL=(-accel on)
      else
        EMU_ACCEL=(-accel off)
      fi
      ;;
    arm64-v8a)
      AVD_NAME="${BLAZEDB_AVD_NAME:-blazedb_arm64_api34}"
      SYSIMG="system-images;android-34;google_apis;arm64-v8a"
      EMU_ACCEL=(-accel off)
      ;;
    *)
      echo "error: unsupported BLAZEDB_ANDROID_ABIS entry: $PRIMARY_ABI" >&2
      exit 1
      ;;
  esac

  if ! avdmanager list avd 2>/dev/null | grep -q "$AVD_NAME"; then
    echo "no" | avdmanager create avd -n "$AVD_NAME" -k "$SYSIMG" -d pixel_6 || true
  fi
  if ! adb devices | awk 'NR>1 && $2=="device" { found=1 } END { exit !found }'; then
    echo ">>> Starting emulator ($AVD_NAME)"
    nohup emulator -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect \
      "${EMU_ACCEL[@]}" >/tmp/blazedb-emulator.log 2>&1 &
    adb wait-for-device
    for _ in $(seq 1 90); do
      boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
      [[ "$boot" == "1" ]] && break
      sleep 2
    done
  fi
fi

echo ">>> Gradle connectedDebugAndroidTest (KMM BlazeDB runtime, ABIs=$ANDROID_ABIS)"
./gradlew :app:connectedDebugAndroidTest \
  "-PBLAZEDB_SWIFT_BUILD=$SWIFT_BUILD" \
  "-PBLAZEDB_ANDROID_ABIS=$ANDROID_ABIS"

echo ">>> KMM Android RUNTIME OK (instrumentation test)"
