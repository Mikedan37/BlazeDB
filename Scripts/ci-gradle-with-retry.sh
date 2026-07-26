#!/usr/bin/env bash
# Run Examples/android/gradlew with retries for transient DNS/network flakes.
#
# Usage (from repo root or anywhere):
#   ./Scripts/ci-gradle-with-retry.sh :shared:iosSimulatorArm64Test
#   ./Scripts/ci-gradle-with-retry.sh --no-daemon :shared:compileDebugKotlinAndroid
#
# Env:
#   BLAZEDB_GRADLE_MAX_ATTEMPTS — default 3
#   BLAZEDB_GRADLE_RETRY_BASE_SECONDS — base sleep between attempts (default 15); sleep = base * attempt
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/Examples/android"
MAX_ATTEMPTS="${BLAZEDB_GRADLE_MAX_ATTEMPTS:-3}"
RETRY_BASE="${BLAZEDB_GRADLE_RETRY_BASE_SECONDS:-15}"

if [[ ! -x "$ANDROID_DIR/gradlew" ]]; then
  chmod +x "$ANDROID_DIR/gradlew"
fi

cd "$ANDROID_DIR"

attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  echo ">>> Gradle (attempt ${attempt}/${MAX_ATTEMPTS}): ./gradlew $*"
  if ./gradlew "$@"; then
    exit 0
  fi
  status=$?
  if (( attempt == MAX_ATTEMPTS )); then
    echo "error: Gradle failed after ${MAX_ATTEMPTS} attempts (exit ${status})" >&2
    exit "$status"
  fi
  sleep_for=$((RETRY_BASE * attempt))
  echo ">>> Gradle failed (exit ${status}); retrying in ${sleep_for}s..."
  sleep "$sleep_for"
  attempt=$((attempt + 1))
done
