#!/usr/bin/env python3
"""Publish comparison benchmark JSON into Docs/Benchmarks canonical artifacts."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

# Reuse table formatting from the matrix runner.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_core_benchmark_matrix import format_matrix_md  # noqa: E402


def iso_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


METHODOLOGY_PREAMBLE = """\
## Methodology (June 2026 refresh)

- **Harness:** `BlazeDBBenchmarks` via `./Scripts/run_comparison_benchmarks.sh --release`
- **Encryption:** AES-256-GCM + PBKDF2-HMAC-SHA256 at **600,000** iterations (release)
- **Cold open:** session cleared before each of 10 open cycles (true KDF cost)
- **Warm reopen:** 10 close/reopen cycles **without** `clearSessionKeys()` (in-process session cache)
- **SQLite reference:** WAL + `synchronous=FULL`, no encryption (not apples-to-apples with secure BlazeDB)
- **Full matrix** (`mvcc_off`, `encryption_off_requested`, …): run `python3 Scripts/run_core_benchmark_matrix.py` separately

### What changed since March 2026

| Era | Cold open | Why |
|-----|-----------|-----|
| Mar 14 AM (`18f0ceb5`) | ~55 ms | 10k PBKDF2; benchmark averaged warm-ish reopens |
| Mar 14 PM (`7b198dea`) | ~1.1 s | 600k PBKDF2 + per-DB salt (security hardening) |
| Jun 29 (`5dd4da82`) | ~1.1 s cold / **~26 ms warm** | Session keys survive `close()` within process |

Older docs (`Docs/Performance/PERFORMANCE.md` pre-refresh) listed design targets (1,200+ ops/sec inserts, “10% faster than SQLite”) that were **not** from this harness.

See also: `Docs/Benchmarks/COMPARISON.md`, `Docs/Security/DATABASE_SESSION_KEY_LIFECYCLE.md`

---
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Publish baseline benchmark JSON to Docs/Benchmarks/")
    parser.add_argument(
        "--baseline",
        type=Path,
        default=Path("benchmark_results/comparison/baseline.json"),
        help="Baseline condition JSON from run_comparison_benchmarks.sh",
    )
    parser.add_argument(
        "--comparison-md",
        type=Path,
        default=Path("benchmark_results/comparison/COMPARISON.md"),
        help="Side-by-side comparison markdown to copy",
    )
    parser.add_argument("--markdown-out", default="Docs/Benchmarks/RESULTS.md")
    parser.add_argument("--json-out", default="Docs/Benchmarks/results.json")
    parser.add_argument("--comparison-out", default="Docs/Benchmarks/COMPARISON.md")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    baseline_path = repo_root / args.baseline
    if not baseline_path.is_file():
        print(f"error: baseline JSON not found: {baseline_path}", file=sys.stderr)
        return 1

    rows = json.loads(baseline_path.read_text(encoding="utf-8"))
    if not isinstance(rows, list):
        print("error: expected JSON array", file=sys.stderr)
        return 1

    now = iso_now()
    table = format_matrix_md(rows, now)
    # Replace generator attribution and insert methodology after the title block.
    table = table.replace(
        "`Scripts/run_core_benchmark_matrix.py`",
        "`Scripts/publish_benchmark_results.py` (from comparison baseline)",
        1,
    )
    intro_end = table.find("\n\n| Condition |")
    if intro_end == -1:
        markdown = table + "\n\n" + METHODOLOGY_PREAMBLE
    else:
        markdown = table[:intro_end] + "\n\n" + METHODOLOGY_PREAMBLE.rstrip() + "\n\n" + table[intro_end + 2 :]

    markdown_path = repo_root / args.markdown_out
    json_path = repo_root / args.json_out
    comparison_out = repo_root / args.comparison_out
    markdown_path.parent.mkdir(parents=True, exist_ok=True)

    markdown_path.write_text(markdown, encoding="utf-8")
    json_path.write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")

    comparison_src = repo_root / args.comparison_md
    if comparison_src.is_file():
        shutil.copy2(comparison_src, comparison_out)

    print(f"Published {markdown_path}")
    print(f"Published {json_path}")
    if comparison_src.is_file():
        print(f"Published {comparison_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
