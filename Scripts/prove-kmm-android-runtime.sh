#!/usr/bin/env bash
# Android emulator runtime proof for KMM BlazeDB (instrumentation test via commonMain API).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CI_ALLOW_DOCKER_CROSS_COMPILE=1
exec "$ROOT/Scripts/ci-kmm-android-emulator-smoke.sh"
