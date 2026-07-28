#!/usr/bin/env bash
# Run BlazeDB write-latency vs DB-size sweep.
#
# Usage:
#   ./Scripts/run_db_size_sweep.sh
#   ./Scripts/run_db_size_sweep.sh --release
#   BLAZEDB_DB_SIZE_SWEEP_SEEDS=0,1000,10000 ./Scripts/run_db_size_sweep.sh --release
#   BLAZEDB_DB_SIZE_SWEEP_PUBLISH=1 ./Scripts/run_db_size_sweep.sh --release
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

config="-c debug"
[[ "$RELEASE" -eq 1 ]] && config="-c release"

OUT_DIR="${BLAZEDB_DB_SIZE_SWEEP_OUT:-benchmark_results/db_size}"
mkdir -p "$OUT_DIR"

echo ">>> DB size sweep (BLAZEDB_BENCH_MODE=db_size_sweep)"
echo "    Honest label: read-optimized; expensive durable write path"
echo "    See Docs/Benchmarks/HONEST_PERFORMANCE.md"
echo "    out=$OUT_DIR"

BLAZEDB_BENCH_MODE=db_size_sweep \
BLAZEDB_DB_SIZE_SWEEP_OUT="$OUT_DIR" \
  swift run $config BlazeDBBenchmarks 2>&1 | tee "$OUT_DIR/db_size_sweep.log"

echo ""
echo ">>> Report: $OUT_DIR/db_size_sweep.md"
echo ">>> JSON:   $OUT_DIR/db_size_sweep.json"
echo ">>> Docs:   Docs/Benchmarks/HONEST_PERFORMANCE.md"

if [[ "${BLAZEDB_DB_SIZE_SWEEP_PUBLISH:-}" == "1" ]]; then
  mkdir -p Docs/Benchmarks
  cp "$OUT_DIR/db_size_sweep.md" Docs/Benchmarks/db_size_sweep.md
  cp "$OUT_DIR/db_size_sweep.json" Docs/Benchmarks/db_size_sweep.json
  echo ">>> Published: Docs/Benchmarks/db_size_sweep.{md,json}"
fi

