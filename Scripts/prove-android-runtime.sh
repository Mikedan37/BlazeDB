#!/usr/bin/env bash
# End-to-end proof: Docker cross-compile → Gradle APK → emulator JNI smoke (macOS/Linux host).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/Examples/android"
SWIFT_BUILD="${BLAZEDB_SWIFT_BUILD:-$ROOT/.build}"
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export JAVA_HOME

chmod +x "$ROOT"/Scripts/*.sh "$ANDROID_DIR"/scripts/*.sh 2>/dev/null || true

echo "=== 1/4 Docker OSS Swift cross-compile ==="
"$ROOT/Scripts/prove-android-runtime-docker-crosscompile.sh"

echo "=== 2/4 Android Gradle SDK (host) ==="
"$ROOT/Scripts/setup-android-gradle-sdk.sh"
export ANDROID_HOME="${ANDROID_HOME:-$ROOT/.artifacts/android-gradle-sdk}"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

echo "=== 3/4 Gradle assembleDebug ==="
cd "$ANDROID_DIR"
if [[ ! -x ./gradlew ]]; then
  if [[ ! -x /tmp/gradle-8.7/bin/gradle ]]; then
    curl -fsSL https://services.gradle.org/distributions/gradle-8.7-bin.zip -o /tmp/gradle-8.7-bin.zip
    unzip -qo /tmp/gradle-8.7-bin.zip -d /tmp
  fi
  /tmp/gradle-8.7/bin/gradle wrapper --gradle-version 8.7
fi
./gradlew :app:assembleDebug "-PBLAZEDB_SWIFT_BUILD=$SWIFT_BUILD" --stacktrace

echo "=== 4/4 Emulator runtime smoke ==="
AVD_NAME="blazedb_arm64_api34"
if ! avdmanager list avd 2>/dev/null | grep -q "$AVD_NAME"; then
  echo "no" | avdmanager create avd -n "$AVD_NAME" -k "system-images;android-34;google_apis;arm64-v8a" -d pixel_6 || true
fi

adb kill-server 2>/dev/null || true
adb start-server

if ! adb devices | awk 'NR>1 && $2=="device" { found=1 } END { exit !found }'; then
  echo ">>> Starting emulator ($AVD_NAME)"
  nohup emulator -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect >/tmp/blazedb-emulator.log 2>&1 &
  adb wait-for-device
  for _ in $(seq 1 90); do
    boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    [[ "$boot" == "1" ]] && break
    sleep 2
  done
fi

./gradlew :app:installDebug "-PBLAZEDB_SWIFT_BUILD=$SWIFT_BUILD"
adb shell am force-stop com.blazedb.example || true
adb shell am start -n com.blazedb.example/.MainActivity
sleep 10

adb shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
adb pull /sdcard/window_dump.xml /tmp/blazedb-window.xml >/dev/null 2>&1 || true

if grep -qE 'JNI smoke result: [1-9][0-9]*' /tmp/blazedb-window.xml 2>/dev/null \
   && grep -q 'android-bridge-smoke' /tmp/blazedb-window.xml 2>/dev/null; then
  echo ">>> RUNTIME SMOKE PASSED (JNI CRUD + KMM live query UI)"
  grep -oE 'JNI smoke result: [^<]+' /tmp/blazedb-window.xml || true
  grep -oE 'Open todos \([^)]+\)' /tmp/blazedb-window.xml || true
  grep -o 'android-bridge-smoke' /tmp/blazedb-window.xml | head -1 || true
  exit 0
fi

if grep -qE 'JNI smoke result: [1-9][0-9]*' /tmp/blazedb-window.xml 2>/dev/null; then
  echo ">>> PARTIAL: JNI smoke OK but live-query UI missing (expected android-bridge-smoke in list)"
  grep -i smoke /tmp/blazedb-window.xml 2>/dev/null || true
  exit 1
fi

echo ">>> RUNTIME SMOKE FAILED — logcat + UI dump:"
grep -i smoke /tmp/blazedb-window.xml 2>/dev/null || true
adb logcat -d | grep -E "BlazeDB|blazedb|AndroidRuntime|FATAL|JNI" | tail -50 || true
exit 1
