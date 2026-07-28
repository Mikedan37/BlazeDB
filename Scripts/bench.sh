#!/usr/bin/env bash
# Front door for BlazeDB benchmark tooling (not product CI / XCTest).
#
# Usage:
#   ./Scripts/bench.sh honesty
#   ./Scripts/bench.sh smoke
#   ./Scripts/bench.sh payload
#   ./Scripts/bench.sh db-size
#   ./Scripts/bench.sh write-profile
#   ./Scripts/bench.sh comparison
#   ./Scripts/bench.sh full
#   ./Scripts/bench.sh publish
#
# Prefer the repo-root wrapper: ./bench <command>
# Also available as: ./dev bench <command>   (see `./dev help`)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: ./bench <command> [--release]

Commands:
  honesty         Lint docs + result shape (fast; no stopwatch suite)
  smoke           Honesty + short db-size + reduced payload sizes (debug by default)
  payload         Full payload-size sweep (release recommended)
  db-size         Write latency vs DB size (release recommended)
  write-profile   Opt-in stage attribution (release recommended)
  comparison      Secure vs engine-only vs SQLite (long; release)
  full            Honesty + release db-size + all payload paths (long)
  publish         full, then publish payload/db-size markdown into Docs/Benchmarks

Flags:
  --release       Force -c release for Swift harness runners (default for full/publish/comparison/payload/db-size/write-profile)
  --debug         Force -c debug (smoke default)

Environment passthrough:
  BLAZEDB_PAYLOAD_SWEEP_PATH, BLAZEDB_PAYLOAD_SWEEP_SIZES,
  BLAZEDB_DB_SIZE_SWEEP_SEEDS, BLAZEDB_WRITE_PROFILE_RECORDS, ...

See Docs/Benchmarks/HONEST_PERFORMANCE.md and PAYLOAD_SIZE.md.
EOF
}

RELEASE_FLAG=()
DEBUG=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --release) RELEASE_FLAG=(--release) ;;
    --debug) DEBUG=1; RELEASE_FLAG=() ;;
    -h|--help) usage; exit 0 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

CMD="${POSITIONAL[0]:-}"
if [[ -z "$CMD" ]]; then
  usage
  exit 1
fi

# Default to release for heavy stopwatch work unless --debug.
need_release() {
  [[ "$DEBUG" -eq 1 ]] && return 1
  [[ ${#RELEASE_FLAG[@]} -gt 0 ]] && return 0
  case "$CMD" in
    payload|db-size|write-profile|comparison|full|publish) return 0 ;;
    *) return 1 ;;
  esac
}

run_payload_all_paths() {
  local out_root="${BLAZEDB_PAYLOAD_SWEEP_OUT:-benchmark_results/payload_size}"
  local publish_env=()
  if [[ "${1:-}" == "publish" ]]; then
    publish_env=(BLAZEDB_PAYLOAD_SWEEP_PUBLISH=1)
  fi
  local path
  for path in durable_insert insertMany_batch transaction_puts update; do
    echo ">>> payload path=$path"
    mkdir -p "$out_root/$path"
    env "${publish_env[@]}" \
      BLAZEDB_PAYLOAD_SWEEP_PATH="$path" \
      BLAZEDB_PAYLOAD_SWEEP_OUT="$out_root/$path" \
      ./Scripts/run_payload_size_sweep.sh "${RELEASE_FLAG[@]}"
  done
  # Combined index under Docs when publishing
  if [[ "${1:-}" == "publish" ]]; then
    python3 - <<'PY'
from pathlib import Path
from datetime import datetime, timezone
root = Path("benchmark_results/payload_size")
docs = Path("Docs/Benchmarks")
docs.mkdir(parents=True, exist_ok=True)
lines = [
    "# Payload size sweep (published)",
    "",
    f"_Generated {datetime.now(timezone.utc).replace(microsecond=0).isoformat()}_",
    "",
    "Core durable insert latency was measured using a **standard** record with a median encoded size of approximately **53 bytes**.",
    "Larger payloads incur additional encoding, encryption, page, and I/O work, but latency does **not** necessarily scale linearly with encoded size.",
    "Do not compare growth-profile 1 MB writes to the core ~53 B durable insert as a controlled size curve — use these tables instead.",
    "",
    "See [PAYLOAD_SIZE.md](PAYLOAD_SIZE.md) and [HONEST_PERFORMANCE.md](HONEST_PERFORMANCE.md).",
    "",
]
for path in ("durable_insert", "insertMany_batch", "transaction_puts", "update"):
    md = root / path / "payload_size_sweep.md"
    lines.append(f"## Path: `{path}`")
    lines.append("")
    if md.is_file():
        body = md.read_text(encoding="utf-8").strip()
        # Drop nested H1 if present
        parts = body.splitlines()
        if parts and parts[0].startswith("# "):
            body = "\n".join(parts[1:]).lstrip()
        lines.append(body)
    else:
        lines.append("_Missing — re-run `./bench publish`._")
    lines.append("")
out = docs / "payload_size_sweep.md"
out.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Wrote {out}")
PY
  fi
}

case "$CMD" in
  honesty)
    python3 Scripts/check_benchmark_honesty.py
    ;;
  smoke)
    python3 Scripts/check_benchmark_honesty.py
    local smoke_release=()
    [[ ${#RELEASE_FLAG[@]} -gt 0 ]] && smoke_release=(--release)
    BLAZEDB_DB_SIZE_SWEEP_SEEDS=0,1000 \
      BLAZEDB_DB_SIZE_SWEEP_OUT=benchmark_results/db_size_smoke \
      ./Scripts/run_db_size_sweep.sh "${smoke_release[@]}"
    BLAZEDB_PAYLOAD_SWEEP_SIZES=256,1024,4096 \
      BLAZEDB_PAYLOAD_SWEEP_PATH=durable_insert \
      BLAZEDB_PAYLOAD_SWEEP_OUT=benchmark_results/payload_size_smoke \
      ./Scripts/run_payload_size_sweep.sh "${smoke_release[@]}"
    ;;
  payload)
    if need_release; then RELEASE_FLAG=(--release); fi
    ./Scripts/run_payload_size_sweep.sh "${RELEASE_FLAG[@]}"
    ;;
  db-size)
    if need_release; then RELEASE_FLAG=(--release); fi
    ./Scripts/run_db_size_sweep.sh "${RELEASE_FLAG[@]}"
    ;;
  write-profile)
    if need_release; then RELEASE_FLAG=(--release); fi
    config="-c debug"
    [[ ${#RELEASE_FLAG[@]} -gt 0 ]] && config="-c release"
    OUT="${BLAZEDB_WRITE_PROFILE_OUT:-benchmark_results/write_profile}"
    mkdir -p "$OUT"
    BLAZEDB_BENCH_MODE=write_profile \
      BLAZEDB_WRITE_PROFILE=1 \
      BLAZEDB_WRITE_PROFILE_OUT="$OUT" \
      swift run $config BlazeDBBenchmarks 2>&1 | tee "$OUT/write_profile.log"
    ;;
  comparison)
    if need_release; then RELEASE_FLAG=(--release); fi
    ./Scripts/run_comparison_benchmarks.sh "${RELEASE_FLAG[@]}"
    ;;
  full)
    if need_release; then RELEASE_FLAG=(--release); fi
    python3 Scripts/check_benchmark_honesty.py
    ./Scripts/run_db_size_sweep.sh "${RELEASE_FLAG[@]}"
    run_payload_all_paths
    ;;
  publish)
    if need_release; then RELEASE_FLAG=(--release); fi
    python3 Scripts/check_benchmark_honesty.py
    BLAZEDB_DB_SIZE_SWEEP_PUBLISH=1 ./Scripts/run_db_size_sweep.sh "${RELEASE_FLAG[@]}"
    run_payload_all_paths publish
    python3 Scripts/check_benchmark_honesty.py
    echo ">>> Published under Docs/Benchmarks/ (payload_size_sweep.md, optional db_size_sweep.*)"
    ;;
  *)
    echo "error: unknown command: $CMD" >&2
    usage
    exit 1
    ;;
esac
