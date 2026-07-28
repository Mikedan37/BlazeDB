#!/usr/bin/env bash
# Run BlazeDB payload-size sweep (latency vs payload bytes).
#
# Usage:
#   ./Scripts/run_payload_size_sweep.sh
#   ./Scripts/run_payload_size_sweep.sh --release
#   BLAZEDB_PAYLOAD_SWEEP_PATH=insertMany_batch ./Scripts/run_payload_size_sweep.sh --release
#   BLAZEDB_PAYLOAD_SWEEP_PATH=update ./Scripts/run_payload_size_sweep.sh --release
#   BLAZEDB_PAYLOAD_SWEEP_SIZES=256,1024,4096 ./Scripts/run_payload_size_sweep.sh --release
#   BLAZEDB_PAYLOAD_SWEEP_PUBLISH=1 ./Scripts/run_payload_size_sweep.sh --release
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

OUT_DIR="${BLAZEDB_PAYLOAD_SWEEP_OUT:-benchmark_results/payload_size}"
mkdir -p "$OUT_DIR"

echo ">>> Payload size sweep (BLAZEDB_BENCH_MODE=payload_size_sweep)"
echo "    Honest label: read-optimized; expensive durable write path"
echo "    See Docs/Benchmarks/HONEST_PERFORMANCE.md + PAYLOAD_SIZE.md"
echo "    path=${BLAZEDB_PAYLOAD_SWEEP_PATH:-durable_insert}"
echo "    out=$OUT_DIR"

BLAZEDB_BENCH_MODE=payload_size_sweep \
BLAZEDB_PAYLOAD_SWEEP_OUT="$OUT_DIR" \
  swift run $config BlazeDBBenchmarks 2>&1 | tee "$OUT_DIR/payload_size_sweep.log"

echo ""
echo ">>> Report: $OUT_DIR/payload_size_sweep.md"
echo ">>> JSON:   $OUT_DIR/payload_size_sweep.json"
echo ">>> Docs:   Docs/Benchmarks/PAYLOAD_SIZE.md"
