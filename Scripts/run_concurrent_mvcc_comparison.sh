#!/usr/bin/env bash
# Run concurrent read-while-write benchmark (#12) with MVCC on vs off vs SQLite.
#
# Usage:
#   ./Scripts/run_concurrent_mvcc_comparison.sh
#   ./Scripts/run_concurrent_mvcc_comparison.sh --release
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

OUT_DIR="benchmark_results/concurrent"
mkdir -p "$OUT_DIR"

run_mvcc() {
  local condition_id="$1"
  local mvcc_flag="$2"
  local json_path="$OUT_DIR/${condition_id}.json"
  local md_path="$OUT_DIR/${condition_id}.md"

  echo ">>> Concurrent benchmark: ${condition_id} (mvcc=${mvcc_flag})"
  local config="-c debug"
  [[ "$RELEASE" -eq 1 ]] && config="-c release"

  BLAZEDB_BENCH_ONLY=concurrent \
  BLAZEDB_BENCH_CONDITION="$condition_id" \
  BLAZEDB_BENCH_MVCC="$mvcc_flag" \
  BLAZEDB_BENCH_ENCRYPTION=on \
  BLAZEDB_BENCH_RESULTS_JSON="$json_path" \
  BLAZEDB_BENCH_RESULTS_MD="$md_path" \
    swift run $config BlazeDBBenchmarks 2>&1 | tee "$OUT_DIR/${condition_id}.log"
}

run_mvcc baseline on
run_mvcc mvcc_off off

python3 "$ROOT/Scripts/generate_comparison_report.py" \
  --concurrent-mvcc-on "$OUT_DIR/baseline.json" \
  --concurrent-mvcc-off "$OUT_DIR/mvcc_off.json" \
  --out "$OUT_DIR/CONCURRENT_MVCC.md"

cp "$OUT_DIR/CONCURRENT_MVCC.md" "$ROOT/Docs/Benchmarks/CONCURRENT_MVCC.md"

echo ""
echo ">>> Report: $OUT_DIR/CONCURRENT_MVCC.md"
