#!/usr/bin/env python3
"""Build BlazeDB vs SQLite comparison reports from benchmark JSON runs."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


KEY_BENCHMARKS = [
    "Insert per-row durable (1K records)",
    "InsertMany (10K records, batch 100)",
    "Read (1K records)",
    "Cold open (PBKDF2 each reopen)",
    "Warm reopen (session cache)",
    "InsertMany (max profile, batch 1000)",
]

CONCURRENT_BENCHMARK_PREFIX = "Concurrent read ("


def load_rows(path: Path) -> dict[str, dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"expected JSON array in {path}")
    return {str(row["name"]): row for row in data}


def find_concurrent_row(rows: dict[str, dict[str, Any]]) -> dict[str, Any] | None:
    for name, row in rows.items():
        if name.startswith(CONCURRENT_BENCHMARK_PREFIX):
            return row
    return None


def fmt_ms(value: Any) -> str:
    if value is None:
        return "N/A"
    v = float(value)
    if v > 0 and v < 0.01:
        return f"{v:.4f}"
    return f"{v:.2f}"


def fmt_ops(value: Any) -> str:
    if value is None:
        return "N/A"
    return f"{float(value):,.0f}"


def fmt_slower_factor(blaze: Any, sqlite: Any) -> str:
    if blaze is None or sqlite is None:
        return "N/A"
    b, s = float(blaze), float(sqlite)
    if b <= 0 or s <= 0:
        return "N/A"
    if b > s:
        return f"{b / s:.1f}× slower"
    return f"{s / b:.1f}× faster"


def fmt_throughput_ratio(blaze_ops: Any, other_ops: Any, other_label: str) -> str:
    if blaze_ops is None or other_ops is None:
        return "N/A"
    b, o = float(blaze_ops), float(other_ops)
    if b <= 0 or o <= 0:
        return "N/A"
    if b >= o:
        return f"{b / o:.1f}× faster than {other_label}"
    return f"{o / b:.1f}× slower than {other_label}"


def fmt_faster_factor(mvcc_on_ops: Any, mvcc_off_ops: Any) -> str:
    if mvcc_on_ops is None or mvcc_off_ops is None:
        return "N/A"
    on_v, off_v = float(mvcc_on_ops), float(mvcc_off_ops)
    if off_v <= 0:
        return "N/A"
    if on_v >= off_v:
        return f"{on_v / off_v:.1f}× faster (MVCC on)"
    return f"{off_v / on_v:.1f}× faster (MVCC off)"


def write_headline_comparison(baseline: Path, engine_only: Path, out: Path) -> None:
    baseline_rows = load_rows(baseline)
    engine_rows = load_rows(engine_only)
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()

    lines = [
        "# BlazeDB vs SQLite — Comparison Report",
        "",
        f"_Generated {now}_",
        "",
        "Two BlazeDB conditions vs plain SQLite (WAL + `synchronous=FULL`, no encryption):",
        "",
        "| Condition | Encryption | Purpose |",
        "|-----------|------------|---------|",
        "| `baseline` | on (AES-256-GCM + PBKDF2) | Production-secure path (MVCC on in harness) |",
        "| `engine_only` | off (benchmark compile flag) | Engine overhead without crypto |",
        "| SQLite | n/a | Reference embedded store |",
        "",
        "## Headline metrics",
        "",
        "| Benchmark | BlazeDB secure avg ms | BlazeDB engine-only avg ms | SQLite avg ms | Secure vs SQLite | Engine vs SQLite |",
        "|-----------|----------------------:|---------------------------:|--------------:|-----------------:|-----------------:|",
    ]

    for name in KEY_BENCHMARKS:
        b = baseline_rows.get(name, {})
        e = engine_rows.get(name, {})
        lines.append(
            "| {name} | {bavg} | {eavg} | {savg} | {bratio} | {eratio} |".format(
                name=name,
                bavg=fmt_ms(b.get("blazedbAvgMs")),
                eavg=fmt_ms(e.get("blazedbAvgMs")),
                savg=fmt_ms(b.get("sqliteAvgMs")),
                bratio=fmt_slower_factor(b.get("blazedbAvgMs"), b.get("sqliteAvgMs")),
                eratio=fmt_slower_factor(e.get("blazedbAvgMs"), e.get("sqliteAvgMs")),
            )
        )

    concurrent = find_concurrent_row(baseline_rows)
    if concurrent:
        lines += [
            "",
            "## Concurrent read (from full baseline run)",
            "",
            f"| {concurrent['name']} | BlazeDB {fmt_ops(concurrent.get('blazedbOpsPerSec'))} reads/s | SQLite {fmt_ops(concurrent.get('sqliteOpsPerSec'))} reads/s | {fmt_slower_factor(concurrent.get('blazedbAvgMs'), concurrent.get('sqliteAvgMs'))} |",
            "",
        ]

    lines += [
        "## How to read this",
        "",
        "- **Honest label:** BlazeDB is **read-optimized** with an **expensive durability path** — see `Docs/Benchmarks/HONEST_PERFORMANCE.md`. Do not treat this table as “BlazeDB is slow” or “BlazeDB is fast.”",
        "- **Secure vs SQLite** / **Engine vs SQLite** show latency ratio (e.g. `3.6× slower` = BlazeDB took 3.6× longer than SQLite).",
        "- **Insert per-row durable** compares BlazeDB `insert()` to SQLite `BEGIN IMMEDIATE` + `INSERT` + `COMMIT` per row (one fsync each). ~2.5 ms on 1K (~274 ops/s) is a real write-path weakness; 10K degrading toward ~24 ms/op needs size-scaling investigation (`./Scripts/run_db_size_sweep.sh`).",
        "- **InsertMany** compares BlazeDB `insertMany(batch)` to SQLite one transaction per batch (fair bulk throughput).",
        "- **Warm reopen** has no SQLite column (SQLite has no in-process session cache).",
        "- SQLite here is **plaintext**. A crypto-fair peer (SQLCipher / encrypted SQLite) is still a **gap** — do not claim encryption is free or that the gap is only crypto.",
        "- Prefer **p50/p95/p99** from RESULTS / LATENCY over averages alone. Core row size is `encodedPayloadBytes` (~53 B standard), not the 1 MB growth profile.",
        "- Do not use `engine_only` with real data — compile-time benchmark flag only.",
        "- Stage attribution for durable inserts: `BLAZEDB_BENCH_MODE=write_profile` / issue #425.",
        "- For MVCC on vs off under contention, run `./Scripts/run_concurrent_mvcc_comparison.sh --release`.",
        "",
        "## Source files",
        "",
        f"- `{baseline}`",
        f"- `{engine_only}`",
        "",
    ]

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {out}")


def write_concurrent_mvcc_comparison(mvcc_on: Path, mvcc_off: Path, out: Path) -> None:
    on_rows = load_rows(mvcc_on)
    off_rows = load_rows(mvcc_off)
    on = find_concurrent_row(on_rows)
    off = find_concurrent_row(off_rows)
    if on is None or off is None:
        raise SystemExit("error: concurrent benchmark row not found in one or both JSON files")

    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    bench_name = str(on["name"])

    lines = [
        "# BlazeDB MVCC — Concurrent Read Comparison",
        "",
        f"_Generated {now}_",
        "",
        "Benchmark workload: **8 concurrent readers + 1 writer**, 5 seconds, 1000 seeded records, encrypted release build.",
        "",
        f"**Benchmark:** `{bench_name}`",
        "",
        "| Engine | MVCC | Read throughput | Implied avg read latency | vs SQLite reads | MVCC on vs off |",
        "|--------|------|----------------:|-------------------------:|----------------:|---------------:|",
        "| BlazeDB | on | {on_ops} ops/s | {on_ms} ms | {on_vs_sqlite} | {on_vs_off} |",
        "| BlazeDB | off (prod default) | {off_ops} ops/s | {off_ms} ms | {off_vs_sqlite} | baseline |",
        "| SQLite | n/a | {sql_ops} ops/s | {sql_ms} ms | — | — |",
        "",
        "## Notes",
        "",
        "- This is the workload MVCC is designed for: readers should not block on an active writer.",
        "- Single-threaded sequential benchmarks (#3) are **not** representative of MVCC value.",
        "- Production BlazeDB defaults to **MVCC off** unless `setMVCCEnabled(true)` is called.",
        "",
        "## Source files",
        "",
        f"- `{mvcc_on}`",
        f"- `{mvcc_off}`",
        "",
    ]

    content = "\n".join(lines).format(
        on_ops=fmt_ops(on.get("blazedbOpsPerSec")),
        on_ms=fmt_ms(on.get("blazedbAvgMs")),
        on_vs_sqlite=fmt_throughput_ratio(on.get("blazedbOpsPerSec"), on.get("sqliteOpsPerSec"), "SQLite"),
        on_vs_off=fmt_faster_factor(on.get("blazedbOpsPerSec"), off.get("blazedbOpsPerSec")),
        off_ops=fmt_ops(off.get("blazedbOpsPerSec")),
        off_ms=fmt_ms(off.get("blazedbAvgMs")),
        off_vs_sqlite=fmt_throughput_ratio(off.get("blazedbOpsPerSec"), off.get("sqliteOpsPerSec"), "SQLite"),
        sql_ops=fmt_ops(on.get("sqliteOpsPerSec")),
        sql_ms=fmt_ms(on.get("sqliteAvgMs")),
    )

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(content, encoding="utf-8")
    print(f"Wrote {out}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--engine-only", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--concurrent-mvcc-on", type=Path)
    parser.add_argument("--concurrent-mvcc-off", type=Path)
    args = parser.parse_args()

    if args.concurrent_mvcc_on and args.concurrent_mvcc_off and args.out:
        write_concurrent_mvcc_comparison(args.concurrent_mvcc_on, args.concurrent_mvcc_off, args.out)
        return 0

    if args.baseline and args.engine_only and args.out:
        write_headline_comparison(args.baseline, args.engine_only, args.out)
        return 0

    parser.error("provide --baseline + --engine-only + --out, or --concurrent-mvcc-on + --concurrent-mvcc-off + --out")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
