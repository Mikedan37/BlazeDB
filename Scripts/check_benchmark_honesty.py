#!/usr/bin/env python3
"""Validate benchmark honesty docs + published result shape.

Exits non-zero if required framing or fields are missing.
Does not require a full suite re-run.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "Docs" / "Benchmarks"


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def require_file(path: Path) -> str:
    if not path.is_file():
        fail(f"missing {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def main() -> int:
    honest = require_file(DOCS / "HONEST_PERFORMANCE.md")
    label = "durable writes are expensive and currently scale poorly with database size"
    for needle in (
        label,
        "encodedPayloadBytes",
        "batch-operations",
        "performance",
        "encrypted",
        "payload-size",
        "p50",
        "483",
    ):
        if needle not in honest and needle.lower() not in honest.lower():
            fail(f"HONEST_PERFORMANCE.md missing `{needle}`")

    if label not in honest:
        fail("HONEST_PERFORMANCE.md missing canonical size-scaling label")
    if "/issues/" in honest and "label%3A" not in honest and "label=" not in honest:
        # Prefer label-filter links over hard-coded issue numbers in long-lived docs.
        import re
        if re.search(r"issues/\d+", honest):
            fail("HONEST_PERFORMANCE.md hard-codes issue numbers; use label filter links instead")

    root_readme = require_file(ROOT / "README.md")
    if "./bench" not in root_readme:
        fail("README.md must mention ./bench front door")
    if "dev bench" not in root_readme and "./dev bench" not in root_readme:
        fail("README.md must mention ./dev bench")

    readme = require_file(DOCS / "README.md")
    if "HONEST_PERFORMANCE.md" not in readme:
        fail("Docs/Benchmarks/README.md must link HONEST_PERFORMANCE.md")
    if "scale poorly" not in readme.lower() and "scale poorly" not in honest:
        fail("Docs/Benchmarks/README.md should reflect size-scaling framing")

    payload = require_file(DOCS / "PAYLOAD_SIZE.md")
    if "encodedPayloadBytes" not in payload:
        fail("PAYLOAD_SIZE.md missing encodedPayloadBytes")

    tools = require_file(ROOT / "Docs" / "Tools" / "README.md")
    if "./bench" not in tools:
        fail("Docs/Tools/README.md must mention ./bench")

    results_path = DOCS / "results.json"
    if results_path.is_file():
        rows = json.loads(results_path.read_text(encoding="utf-8"))
        if not isinstance(rows, list) or not rows:
            fail("results.json must be a non-empty array")
        sample = rows[0]
        for key in ("blazedbP50Ms", "blazedbP95Ms", "blazedbP99Ms", "blazedbAvgMs"):
            if key not in sample:
                fail(f"results.json rows must include {key}")
        # Encoded size required on insert/read style rows when present in newer publishes
        insertish = [r for r in rows if "Insert" in str(r.get("name", "")) or "Read" in str(r.get("name", ""))]
        if insertish and all(r.get("encodedPayloadBytes") is None for r in insertish):
            print(
                "WARN: insert/read rows lack encodedPayloadBytes — re-run comparison harness or backfill",
                file=sys.stderr,
            )
        else:
            for r in insertish:
                if r.get("encodedPayloadBytes") is None:
                    continue
                enc = int(r["encodedPayloadBytes"])
                if enc <= 0 or enc > 10_000:
                    fail(f"unexpected encodedPayloadBytes={enc} for {r.get('name')}")

    # Scripts must exist
    for rel in (
        "bench",
        "help",
        "Scripts/bench.sh",
        "Scripts/run_payload_size_sweep.sh",
        "Scripts/run_db_size_sweep.sh",
        "Scripts/run_comparison_benchmarks.sh",
    ):
        if not (ROOT / rel).is_file():
            fail(f"missing {rel}")

    # Regression: empty BLAZEDB_BENCH_ONLY / empty suite must not wipe published RESULTS.
    main_swift = require_file(ROOT / "BlazeDBBenchmarks" / "main.swift")
    if "guard !suite.results.isEmpty else" not in main_swift:
        fail("BlazeDBBenchmarks/main.swift missing empty-suite RESULTS write guard")
    if "BLAZEDB_BENCH_ONLY" not in main_swift:
        fail("BlazeDBBenchmarks/main.swift missing BLAZEDB_BENCH_ONLY handling")
    if "not writing RESULTS.md/results.json" not in main_swift:
        fail("BlazeDBBenchmarks/main.swift missing empty-suite skip message")

    print("OK: benchmark honesty checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
