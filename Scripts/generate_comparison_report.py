#!/usr/bin/env python3
"""Build a side-by-side BlazeDB vs SQLite comparison from two benchmark JSON runs."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


KEY_BENCHMARKS = [
    "Insert (1K records)",
    "Read (1K records)",
    "Cold open (PBKDF2 each reopen)",
    "Warm reopen (session cache)",
    "InsertMany (max profile, batch 1000)",
]


def load_rows(path: Path) -> dict[str, dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"expected JSON array in {path}")
    return {str(row["name"]): row for row in data}


def fmt_ms(value: Any) -> str:
    if value is None:
        return "N/A"
    v = float(value)
    if v > 0 and v < 0.01:
        return f"{v:.4f}"
    return f"{v:.2f}"


def fmt_slower_factor(blaze: Any, sqlite: Any) -> str:
    if blaze is None or sqlite is None:
        return "N/A"
    b, s = float(blaze), float(sqlite)
    if b == 0:
        return "N/A"
    if s == 0:
        return "∞"
    return f"{b / s:.1f}× slower"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--engine-only", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    baseline = load_rows(args.baseline)
    engine = load_rows(args.engine_only)
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
        "| `baseline` | on (AES-256-GCM + PBKDF2) | Production-secure path |",
        "| `engine_only` | off (benchmark compile flag) | Engine overhead without crypto |",
        "| SQLite | n/a | Reference embedded store |",
        "",
        "## Headline metrics",
        "",
        "| Benchmark | BlazeDB secure avg ms | BlazeDB engine-only avg ms | SQLite avg ms | Secure vs SQLite | Engine vs SQLite |",
        "|-----------|----------------------:|---------------------------:|--------------:|-----------------:|-----------------:|",
    ]

    for name in KEY_BENCHMARKS:
        b = baseline.get(name, {})
        e = engine.get(name, {})
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

    lines += [
        "",
        "## How to read this",
        "",
        "- **Secure vs SQLite** / **Engine vs SQLite** show latency ratio (e.g. `3.6× slower` = BlazeDB took 3.6× longer than SQLite).",
        "- **Warm reopen** has no SQLite column (SQLite has no in-process session cache).",
        "- Do not use `engine_only` with real data — compile-time benchmark flag only.",
        "",
        "## Source files",
        "",
        f"- `{args.baseline}`",
        f"- `{args.engine_only}`",
        "",
    ]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
