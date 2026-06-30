#!/usr/bin/env bash
# Run secure baseline + engine-only (no encryption) benchmarks and emit a side-by-side report.
#
# Usage:
#   ./Scripts/run_comparison_benchmarks.sh
#   ./Scripts/run_comparison_benchmarks.sh --release   # recommended (600k PBKDF2 outside XCTest)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RELEASE=0
for arg in "$@"; do
  case "$arg" in
    --release) RELEASE=1 ;;
    *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
  esac
done

OUT_DIR="benchmark_results/comparison"
mkdir -p "$OUT_DIR"

run_condition() {
  local condition_id="$1"
  local encryption_flag="$2"
  local md_path="$OUT_DIR/${condition_id}.md"
  local json_path="$OUT_DIR/${condition_id}.json"
  local swift_flags=""

  if [[ "$encryption_flag" == "off" ]]; then
    swift_flags="-Xswiftc -DBLAZEDB_BENCHMARK_NO_ENCRYPTION"
  fi

  echo ">>> Running condition: ${condition_id} (encryption=${encryption_flag})"
  local config="-c debug"
  [[ "$RELEASE" -eq 1 ]] && config="-c release"

  # shellcheck disable=SC2086
  BLAZEDB_BENCH_CONDITION="$condition_id" \
  BLAZEDB_BENCH_ENCRYPTION="$encryption_flag" \
  BLAZEDB_BENCH_RESULTS_MD="$md_path" \
  BLAZEDB_BENCH_RESULTS_JSON="$json_path" \
    swift run $config $swift_flags BlazeDBBenchmarks 2>&1 | tee "$OUT_DIR/${condition_id}.log"
}

run_condition baseline on
run_condition engine_only off

python3 "$ROOT/Scripts/generate_comparison_report.py" \
  --baseline "$OUT_DIR/baseline.json" \
  --engine-only "$OUT_DIR/engine_only.json" \
  --out "$OUT_DIR/COMPARISON.md"

python3 "$ROOT/Scripts/publish_benchmark_results.py" \
  --baseline "$OUT_DIR/baseline.json" \
  --comparison-md "$OUT_DIR/COMPARISON.md"

echo ""
echo ">>> Comparison report: $OUT_DIR/COMPARISON.md"
echo ">>> Published docs:   Docs/Benchmarks/RESULTS.md, COMPARISON.md, results.json"
