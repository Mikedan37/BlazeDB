#!/usr/bin/env bash
# Cold/warm open breakdown — run before optimizing startup latency.
#
# Usage:
#   ./Scripts/run_open_profile.sh
#   BLAZEDB_OPEN_PROFILE_RECORDS=10000 ./Scripts/run_open_profile.sh
#
# Release build recommended (PBKDF2 uses 600k iterations outside XCTest).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p benchmark_results/open_profile

echo ">>> Building BlazeDBOpenProfiler (release)..."
BLAZEDB_BENCH_MODE=open_profile \
BLAZEDB_OPEN_PROFILE_OUT=benchmark_results/open_profile \
BLAZEDB_OPEN_PROFILE_RECORDS="${BLAZEDB_OPEN_PROFILE_RECORDS:-1000}" \
  swift run -c release BlazeDBBenchmarks 2>&1 | tee benchmark_results/open_profile/run.log

echo ""
echo ">>> Done. See benchmark_results/open_profile/open_profile.md"
