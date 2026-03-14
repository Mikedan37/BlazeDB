#!/usr/bin/env python3
"""
Generate a consolidated latency report for BlazeDB benchmarks.

Default mode:
- Reads Docs/Benchmarks/results.json and Docs/Benchmarks/limits_measurements.json
- Produces Docs/Benchmarks/LATENCY.md + Docs/Benchmarks/latency_measurements.json

Optional mode:
- Runs query percentile benchmark test and parses p50/p95 output
- Runs telemetry percentile integration test and parses avg/p95/p99 output
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def read_json(path: Path) -> dict[str, Any] | list[dict[str, Any]]:
    return json.loads(path.read_text(encoding="utf-8"))


def run_command(command: str, cwd: Path) -> tuple[int, float, str]:
    start = time.monotonic()
    proc = subprocess.run(
        command,
        cwd=str(cwd),
        shell=True,
        capture_output=True,
        text=True,
    )
    elapsed = time.monotonic() - start
    output = (proc.stdout or "") + "\n" + (proc.stderr or "")
    return proc.returncode, elapsed, output


def parse_query_percentiles(output: str) -> dict[str, float] | None:
    p50 = re.search(r"p50 query latency:\s*([0-9.]+)ms", output)
    p95 = re.search(r"p95 query latency:\s*([0-9.]+)ms", output)
    avg = re.search(r"Average per search:\s*([0-9.]+)ms", output)
    tput = re.search(r"Throughput:\s*([0-9.]+)\s+searches/sec", output)
    if not (p50 and p95 and avg and tput):
        p50 = re.search(r"ACTIVE_QUERY_P50_MS=([0-9.]+)", output)
        p95 = re.search(r"ACTIVE_QUERY_P95_MS=([0-9.]+)", output)
        p99 = re.search(r"ACTIVE_QUERY_P99_MS=([0-9.]+)", output)
        tput = re.search(r"ACTIVE_QUERY_THROUGHPUT_QPS=([0-9.]+)", output)
        if not (p50 and p95 and p99 and tput):
            return None
        return {
            "avg_ms": (float(p50.group(1)) + float(p95.group(1)) + float(p99.group(1))) / 3.0,
            "p50_ms": float(p50.group(1)),
            "p95_ms": float(p95.group(1)),
            "p99_ms": float(p99.group(1)),
            "throughput_searches_per_sec": float(tput.group(1)),
        }
    if not (p50 and p95 and avg and tput):
        return None
    return {
        "avg_ms": float(avg.group(1)),
        "p50_ms": float(p50.group(1)),
        "p95_ms": float(p95.group(1)),
        "p99_ms": float(p95.group(1)),
        "throughput_searches_per_sec": float(tput.group(1)),
    }


def parse_telemetry_percentiles(output: str) -> dict[str, float] | None:
    avg = re.search(r"Average:\s*([0-9.]+)ms", output)
    p95 = re.search(r"p95:\s*([0-9.]+)ms", output)
    p99 = re.search(r"p99:\s*([0-9.]+)ms", output)
    if not (avg and p95 and p99):
        avg = re.search(r"ACTIVE_TELEMETRY_AVG_MS=([0-9.]+)", output)
        p95 = re.search(r"ACTIVE_TELEMETRY_P95_MS=([0-9.]+)", output)
        p99 = re.search(r"ACTIVE_TELEMETRY_P99_MS=([0-9.]+)", output)
    if not (avg and p95 and p99):
        return None
    return {
        "avg_ms": float(avg.group(1)),
        "p95_ms": float(p95.group(1)),
        "p99_ms": float(p99.group(1)),
    }


def format_md_table(results: list[dict[str, Any]]) -> str:
    lines = [
        "| Condition | Support | Benchmark | BlazeDB ops/sec | avg ms | p50 ms | p95 ms | p99 ms | SQLite ops/sec | SQLite avg ms | SQLite p50 ms | SQLite p95 ms | SQLite p99 ms |",
        "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in results:
        lines.append(
            "| {condition} | {support} | {name} | {bops} | {bavg} | {bp50} | {bp95} | {bp99} | {sops} | {savg} | {sp50} | {sp95} | {sp99} |".format(
                condition=row.get("condition", "baseline"),
                support=row.get("supportStatus", "unknown"),
                name=row["name"],
                bops=f"{row.get('blazedbOpsPerSec', 0):.0f}",
                bavg=("N/A" if row.get("blazedbAvgMs") is None else f"{row['blazedbAvgMs']:.3f}"),
                bp50=("N/A" if row.get("blazedbP50Ms") is None else f"{row['blazedbP50Ms']:.3f}"),
                bp95=("N/A" if row.get("blazedbP95Ms") is None else f"{row['blazedbP95Ms']:.3f}"),
                bp99=("N/A" if row.get("blazedbP99Ms") is None else f"{row['blazedbP99Ms']:.3f}"),
                sops=("N/A" if row.get("sqliteOpsPerSec") is None else f"{row['sqliteOpsPerSec']:.0f}"),
                savg=("N/A" if row.get("sqliteAvgMs") is None else f"{row['sqliteAvgMs']:.3f}"),
                sp50=("N/A" if row.get("sqliteP50Ms") is None else f"{row['sqliteP50Ms']:.3f}"),
                sp95=("N/A" if row.get("sqliteP95Ms") is None else f"{row['sqliteP95Ms']:.3f}"),
                sp99=("N/A" if row.get("sqliteP99Ms") is None else f"{row['sqliteP99Ms']:.3f}"),
            )
        )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate BlazeDB latency report.")
    parser.add_argument(
        "--run-query-percentiles",
        action="store_true",
        help="Run concurrent search percentile benchmark test and parse output.",
    )
    parser.add_argument(
        "--run-telemetry-percentiles",
        action="store_true",
        help="Run telemetry integration percentile test and parse output.",
    )
    parser.add_argument(
        "--markdown-out",
        default="Docs/Benchmarks/LATENCY.md",
        help="Output markdown path (relative to repo root).",
    )
    parser.add_argument(
        "--json-out",
        default="Docs/Benchmarks/latency_measurements.json",
        help="Output JSON path (relative to repo root).",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    bench_json_path = repo_root / "Docs/Benchmarks/results.json"
    limits_json_path = repo_root / "Docs/Benchmarks/limits_measurements.json"
    if not bench_json_path.exists():
        raise SystemExit(f"Missing {bench_json_path}; run swift run BlazeDBBenchmarks first")
    if not limits_json_path.exists():
        raise SystemExit(f"Missing {limits_json_path}; run generate_limits_report.py first")

    bench_results = read_json(bench_json_path)
    if not isinstance(bench_results, list):
        raise SystemExit("Unexpected results.json format")
    limits = read_json(limits_json_path)
    if not isinstance(limits, dict):
        raise SystemExit("Unexpected limits_measurements.json format")

    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    real = (limits.get("real_measurement") or {}).get("metrics", {})
    growth_section: dict[str, float] = {}
    if real:
        growth_seconds = float(real.get("db_growth_elapsed_seconds", 0) or 0)
        growth_records = float(real.get("db_growth_records_inserted", 0) or 0)
        growth_bytes = float(real.get("db_growth_final_bytes", 0) or 0)
        if growth_seconds > 0:
            growth_section = {
                "avg_write_latency_ms": ((growth_seconds / growth_records) * 1000.0) if growth_records > 0 else 0.0,
                "records_per_second": growth_records / growth_seconds,
                "mib_per_second": (growth_bytes / (1024 * 1024)) / growth_seconds,
            }

    query_percentiles: dict[str, Any] = {"status": "not_run"}
    if args.run_query_percentiles:
        cmd = (
            'swift test --filter "BlazeDB_Tier3_Heavy.ActivePercentileBenchmarks/'
            'testActiveQueryPercentiles"'
        )
        rc, elapsed, out = run_command(cmd, repo_root)
        parsed = parse_query_percentiles(out)
        no_matching = "No matching test cases were run" in out
        query_percentiles = {
            "status": ("unavailable_in_active_tiers" if no_matching else ("ok" if (rc == 0 and parsed) else "failed")),
            "command": cmd,
            "seconds": elapsed,
            "metrics": parsed,
            "output_excerpt": "\n".join(out.splitlines()[-20:]),
        }

    telemetry_percentiles: dict[str, Any] = {"status": "not_run"}
    if args.run_telemetry_percentiles:
        cmd = (
            'swift test --filter "BlazeDB_Tier3_Heavy.ActivePercentileBenchmarks/'
            'testActiveOperationPercentiles"'
        )
        rc, elapsed, out = run_command(cmd, repo_root)
        parsed = parse_telemetry_percentiles(out)
        unavailable = "Telemetry integration scenarios require distributed build" in out
        no_matching = "No matching test cases were run" in out
        telemetry_percentiles = {
            "status": (
                "unavailable_in_core_build"
                if unavailable
                else ("unavailable_in_active_tiers" if no_matching else ("ok" if (rc == 0 and parsed) else "failed"))
            ),
            "command": cmd,
            "seconds": elapsed,
            "metrics": parsed,
            "output_excerpt": "\n".join(out.splitlines()[-20:]),
        }

    core_has_percentiles = False
    if isinstance(bench_results, list):
        core_has_percentiles = all(
            isinstance(row, dict)
            and row.get("blazedbP50Ms") is not None
            and row.get("blazedbP95Ms") is not None
            and row.get("blazedbP99Ms") is not None
            for row in bench_results
        )

    missing_measurements: list[str] = []
    if telemetry_percentiles.get("status") == "unavailable_in_core_build":
        missing_measurements.append(
            "Telemetry p95/p99 integration latency in active core-only build (requires distributed build path)."
        )
    if telemetry_percentiles.get("status") == "unavailable_in_active_tiers" and not core_has_percentiles:
        missing_measurements.append(
            "Telemetry percentile integration test is excluded from active Tier2 target in Package.swift."
        )
    if query_percentiles.get("status") == "unavailable_in_active_tiers" and not core_has_percentiles:
        missing_measurements.append(
            "Concurrent query percentile benchmark test is excluded from active Tier1 target in Package.swift."
        )
    if query_percentiles.get("status") == "failed":
        missing_measurements.append(
            "Concurrent query percentile benchmark failed to produce parseable p50/p95 output."
        )
    if telemetry_percentiles.get("status") == "failed":
        missing_measurements.append(
            "Telemetry integration percentile benchmark failed to produce parseable avg/p95/p99 output."
        )
    if not growth_section:
        missing_measurements.append(
            "Real 1MB write latency derivation missing because limits real-measurement metrics were unavailable."
        )

    markdown = f"""# BlazeDB Latency Metrics

_Auto-generated by `Scripts/generate_latency_report.py` on {now}._

## How To Refresh

- Generate base benchmark + latency table:
  - `swift run BlazeDBBenchmarks`
  - `python3 Scripts/generate_latency_report.py`
- Also run percentile tests:
  - `python3 Scripts/generate_latency_report.py --run-query-percentiles --run-telemetry-percentiles`

## Core Benchmark Latencies (from `Docs/Benchmarks/results.json`)

{format_md_table(bench_results)}

## Real Growth Latency (from `limits_measurements.json`)

"""

    if growth_section:
        markdown += (
            f"- Average write latency (growth profile): `{growth_section['avg_write_latency_ms']:.3f}` ms/op\n"
            f"- Growth throughput: `{growth_section['records_per_second']:.2f}` records/sec\n"
            f"- Growth bandwidth: `{growth_section['mib_per_second']:.2f}` MiB/sec\n"
        )
    else:
        markdown += "- Not available.\n"

    markdown += "\n## Optional Percentile Test Outputs\n\n"
    if core_has_percentiles:
        markdown += "- Core benchmark rows already include p50/p95/p99 percentile latencies.\n"
    markdown += f"- Query concurrent percentile test status: `{query_percentiles.get('status')}`\n"
    if query_percentiles.get("metrics"):
        q = query_percentiles["metrics"]
        markdown += (
            f"  - avg: `{q['avg_ms']:.2f}` ms\n"
            f"  - p50: `{q['p50_ms']:.2f}` ms\n"
            f"  - p95: `{q['p95_ms']:.2f}` ms\n"
            f"  - p99: `{q['p99_ms']:.2f}` ms\n"
            f"  - throughput: `{q['throughput_searches_per_sec']:.0f}` searches/sec\n"
        )
    markdown += f"- Telemetry percentile integration status: `{telemetry_percentiles.get('status')}`\n"
    if telemetry_percentiles.get("metrics"):
        t = telemetry_percentiles["metrics"]
        markdown += (
            f"  - avg: `{t['avg_ms']:.2f}` ms\n"
            f"  - p95: `{t['p95_ms']:.2f}` ms\n"
            f"  - p99: `{t['p99_ms']:.2f}` ms\n"
        )

    markdown += "\n## Missing/Unavailable Measurements\n\n"
    if missing_measurements:
        for item in missing_measurements:
            markdown += f"- {item}\n"
    else:
        markdown += "- None identified in this run.\n"

    payload = {
        "generated_at_utc": now,
        "core_benchmark_latencies": bench_results,
        "real_growth_latency": growth_section,
        "query_percentiles": query_percentiles,
        "telemetry_percentiles": telemetry_percentiles,
        "missing_measurements": missing_measurements,
    }

    md_path = repo_root / args.markdown_out
    json_path = repo_root / args.json_out
    md_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    md_path.write_text(markdown, encoding="utf-8")
    json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    print(f"Generated markdown: {md_path}")
    print(f"Generated json:     {json_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
