#!/usr/bin/env python3
"""
Generate BlazeDB limits + quick benchmark report.

Fast mode (default): parses source constants and emits markdown/json in seconds.
Optional mode (--run-fast-bench): runs a short deterministic test matrix and
includes timing measurements in the report.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass
class BenchResult:
    name: str
    command: str
    seconds: float
    passed: bool
    summary: str


@dataclass
class RealMeasurementResult:
    command: str
    seconds: float
    passed: bool
    metrics: dict[str, float | int]
    output_excerpt: str


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def parse_first_int(pattern: str, text: str, description: str) -> int:
    match = re.search(pattern, text)
    if not match:
        raise ValueError(f"Could not parse {description}")
    return int(match.group(1).replace("_", "").replace(",", ""))


def run_benchmark(command: str, cwd: Path, name: str) -> BenchResult:
    start = time.monotonic()
    proc = subprocess.run(
        command,
        cwd=str(cwd),
        shell=True,
        capture_output=True,
        text=True,
    )
    elapsed = time.monotonic() - start
    out = (proc.stdout or "") + "\n" + (proc.stderr or "")

    summary = "passed"
    if proc.returncode != 0:
        summary = "failed"
    else:
        executed = re.search(r"Executed\s+\d+\s+tests?,\s+with\s+0 failures", out)
        if executed:
            summary = executed.group(0)

    return BenchResult(
        name=name,
        command=command,
        seconds=elapsed,
        passed=(proc.returncode == 0),
        summary=summary,
    )


def run_real_measurement(
    cwd: Path,
    target_gib: float,
    payload_bytes: int,
    batch_size: int,
) -> RealMeasurementResult:
    command = (
        'swift test --filter "BlazeDB_Tier3_Heavy.RealLimitsMeasurementTests/'
        'testMeasure_RealLimitsAndGrowth"'
    )
    env = dict(**os.environ)
    env["BLAZEDB_REAL_LIMIT_TARGET_GIB"] = str(target_gib)
    env["BLAZEDB_REAL_LIMIT_PAYLOAD_BYTES"] = str(payload_bytes)
    env["BLAZEDB_REAL_LIMIT_BATCH_SIZE"] = str(batch_size)

    start = time.monotonic()
    proc = subprocess.run(
        command,
        cwd=str(cwd),
        shell=True,
        capture_output=True,
        text=True,
        env=env,
    )
    elapsed = time.monotonic() - start
    out = (proc.stdout or "") + "\n" + (proc.stderr or "")

    metrics: dict[str, float | int] = {}
    patterns = {
        "blob_max_bytes": r"REAL_LIMIT_BLOB_MAX_BYTES=(\d+)",
        "blob_max_mib": r"REAL_LIMIT_BLOB_MAX_MIB=([0-9.]+)",
        "string_max_bytes": r"REAL_LIMIT_STRING_MAX_BYTES=(\d+)",
        "string_max_mib": r"REAL_LIMIT_STRING_MAX_MIB=([0-9.]+)",
        "db_growth_final_bytes": r"REAL_DB_GROWTH_FINAL_BYTES=(\d+)",
        "db_growth_final_gib": r"REAL_DB_GROWTH_FINAL_GIB=([0-9.]+)",
        "db_growth_records_inserted": r"REAL_DB_GROWTH_RECORDS_INSERTED=(\d+)",
        "db_growth_payload_bytes_per_record": r"REAL_DB_GROWTH_PAYLOAD_BYTES_PER_RECORD=(\d+)",
        "db_growth_elapsed_seconds": r"REAL_DB_GROWTH_ELAPSED_SECONDS=([0-9.]+)",
    }
    for key, pattern in patterns.items():
        m = re.search(pattern, out)
        if not m:
            continue
        value = m.group(1)
        metrics[key] = float(value) if "." in value else int(value)

    excerpt_lines = [
        line
        for line in out.splitlines()
        if line.startswith("REAL_")
        or "Test Case '-[BlazeDB_Tier3_Heavy.RealLimitsMeasurementTests" in line
    ]
    excerpt = "\n".join(excerpt_lines[-16:])

    return RealMeasurementResult(
        command=f"BLAZEDB_REAL_LIMIT_TARGET_GIB={target_gib} "
        f"BLAZEDB_REAL_LIMIT_PAYLOAD_BYTES={payload_bytes} "
        f"BLAZEDB_REAL_LIMIT_BATCH_SIZE={batch_size} {command}",
        seconds=elapsed,
        passed=(proc.returncode == 0 and bool(metrics)),
        metrics=metrics,
        output_excerpt=excerpt,
    )


def format_bytes_as_mib(value: int) -> str:
    return f"{value / (1024 * 1024):.2f} MiB"


def generate_report(
    root: Path,
    run_fast_bench: bool,
    run_real_limits: bool,
    real_target_gib: float,
    real_payload_bytes: int,
    real_batch_size: int,
) -> tuple[str, dict[str, Any]]:
    page_store = read_text(root / "BlazeDB/Storage/PageStore.swift")
    overflow = read_text(root / "BlazeDB/Storage/PageStore+Overflow.swift")
    batch = read_text(root / "BlazeDB/Core/DynamicCollection+Batch.swift")
    health = read_text(root / "BlazeDB/Exports/DatabaseHealth+Limits.swift")
    decoder = read_text(root / "BlazeDB/Utils/BlazeBinaryDecoder.swift")

    page_size = parse_first_int(r"internal let pageSize = (\d+)", page_store, "page size")
    page_plaintext_overhead = parse_first_int(
        r"pageSize - ([0-9_]+)\) bytes for encrypted data",
        page_store,
        "single-page encrypted overhead",
    )
    page_plaintext_max = page_size - page_plaintext_overhead
    max_data_per_page_overhead = parse_first_int(
        r"/// Maximum data per page[\s\S]*?return pageSize - ([0-9_]+)",
        overflow,
        "maxDataPerPage overhead",
    )
    max_data_per_page = page_size - max_data_per_page_overhead
    max_data_per_overflow_page = page_size - parse_first_int(
        r"/// Maximum data per overflow page[\s\S]*?return pageSize - ([0-9_]+)",
        overflow,
        "maxDataPerOverflowPage overhead",
    )
    overflow_ref_v2_trailer = parse_first_int(
        r"static let encodedSize: Int = (\d+)", overflow, "OverflowReferenceV2 trailer size"
    )
    overflow_chain_limit = parse_first_int(
        r"let maxChainLength = ([0-9_]+)", overflow, "overflow max chain length"
    )

    main_payload_v2 = max_data_per_page - overflow_ref_v2_trailer
    max_overflow_v2_payload = main_payload_v2 + (
        overflow_chain_limit * max_data_per_overflow_page
    )

    batch_limit = parse_first_int(
        r"guard records\.count <= ([0-9_]+)",
        batch,
        "batch insert record-count limit",
    )
    batch_update_limit = 100000
    batch_delete_limit = 100000

    max_record_mb = parse_first_int(
        r"let maxRecordSize = (\d+) \* 1024 \* 1024", batch, "max record MB"
    )
    max_record_bytes = max_record_mb * 1024 * 1024

    health_max_page_count = parse_first_int(
        r"maxPageCount: Int = ([0-9_]+)", health, "health page count limit"
    )
    health_max_disk_bytes = parse_first_int(
        r"maxDiskUsageBytes: Int64 = ([0-9_]+)", health, "health disk byte limit"
    )
    # Build WAL ratio from decimal literal
    ratio_match = re.search(r"maxWALSizeRatio: Double = ([0-9]+)\.([0-9]+)", health)
    wal_ratio = 0.5
    if ratio_match:
        wal_ratio = float(f"{ratio_match.group(1)}.{ratio_match.group(2)}")

    max_string_bytes_decoder = parse_first_int(
        r"Invalid string length: .*max (\d+)MB", decoder, "decoder max string MB"
    ) * 1_000_000
    max_data_bytes_decoder = parse_first_int(
        r"Invalid Data length: .*max (\d+)MB", decoder, "decoder max data MB"
    ) * 1_000_000
    max_array_count = parse_first_int(
        r"guard count >= 0 && count < ([0-9_]+) else \{\n\s*throw BlazeBinaryError\.invalidFormat\(\"Invalid array count",
        decoder,
        "array count guard",
    )
    max_dict_count = parse_first_int(
        r"guard count >= 0 && count < ([0-9_]+) else \{\n\s*throw BlazeBinaryError\.invalidFormat\(\"Invalid dictionary count",
        decoder,
        "dictionary count guard",
    )

    benches: list[BenchResult] = []
    if run_fast_bench:
        benches = [
            run_benchmark(
                'swift test --filter "BlazeDB_Tier1Fast.OverflowChainCrashAtomicityTests"',
                root,
                "overflow_crash_atomicity",
            ),
            run_benchmark(
                'swift test --filter "BlazeDB_Tier3_Heavy.PageStoreBoundaryTests"',
                root,
                "page_store_boundary",
            ),
            run_benchmark(
                'swift test --filter "BlazeDB_Tier3_Heavy.FuzzTests/testFuzz_OverflowBoundaryChurn"',
                root,
                "overflow_boundary_fuzz",
            ),
        ]

    real_measurement: RealMeasurementResult | None = None
    if run_real_limits:
        real_measurement = run_real_measurement(
            cwd=root,
            target_gib=real_target_gib,
            payload_bytes=real_payload_bytes,
            batch_size=real_batch_size,
        )
    derived_real_metrics: dict[str, float] = {}
    if real_measurement and real_measurement.metrics:
        growth_seconds = float(real_measurement.metrics.get("db_growth_elapsed_seconds", 0) or 0)
        growth_bytes = float(real_measurement.metrics.get("db_growth_final_bytes", 0) or 0)
        growth_records = float(real_measurement.metrics.get("db_growth_records_inserted", 0) or 0)
        if growth_seconds > 0:
            derived_real_metrics["growth_records_per_second"] = growth_records / growth_seconds
            derived_real_metrics["growth_mib_per_second"] = (growth_bytes / (1024 * 1024)) / growth_seconds
            if growth_records > 0:
                derived_real_metrics["growth_avg_write_latency_ms"] = (growth_seconds / growth_records) * 1000.0

    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()

    markdown = f"""# BlazeDB Limits and Fast Benchmarks

_Auto-generated by `Scripts/generate_limits_report.py` on {now}._

## How To Refresh

- Fast limits only (seconds): `python3 Scripts/generate_limits_report.py`
- Limits + quick benchmark timings: `python3 Scripts/generate_limits_report.py --run-fast-bench`

## Hard Engine Limits

| Category | Value | Notes |
|---|---:|---|
| Page size | `{page_size}` bytes | Fixed page store page size |
| Single-page plaintext max | `{page_plaintext_max}` bytes | `PageStore` encrypted page envelope limit |
| Overflow main-page payload (v2) | `{main_payload_v2}` bytes | `maxDataPerPage - OverflowReferenceV2.encodedSize` |
| Overflow page payload | `{max_data_per_overflow_page}` bytes | Per overflow page |
| Overflow chain page cap | `{overflow_chain_limit}` pages | Corruption safety guard |
| Max record payload via overflow v2 (derived) | `{max_overflow_v2_payload}` bytes ({format_bytes_as_mib(max_overflow_v2_payload)}) | Approx upper bound before chain-limit rejection |

## API / Batch Limits

| Category | Value | Notes |
|---|---:|---|
| Batch insert count max | `{batch_limit}` | Throws above this |
| Batch update count max | `{batch_update_limit}` | Throws above this |
| Batch delete count max | `{batch_delete_limit}` | Throws above this |
| Batch record encoded max | `{max_record_bytes}` bytes ({format_bytes_as_mib(max_record_bytes)}) | Explicit guard in batch insert |

## Binary Codec Guards

| Category | Value | Notes |
|---|---:|---|
| Max string length (decoder guard) | `{max_string_bytes_decoder}` bytes | Corruption/DoS guard |
| Max data/blob length (decoder guard) | `{max_data_bytes_decoder}` bytes | Corruption/DoS guard |
| Max array elements (decoder guard) | `{max_array_count}` | Guard against corrupt payload explosion |
| Max dictionary entries (decoder guard) | `{max_dict_count}` | Guard against corrupt payload explosion |

## Resource Warning Defaults (Soft Limits)

| Category | Default | Behavior |
|---|---:|---|
| Max WAL ratio | `{wal_ratio}` | Warning unless write refusal enabled |
| Max page count | `{health_max_page_count}` | Warning threshold |
| Max disk usage | `{health_max_disk_bytes}` bytes ({format_bytes_as_mib(health_max_disk_bytes)}) | Warning threshold |

"""

    if run_fast_bench:
        markdown += "\n## Quick Benchmark Results\n\n"
        markdown += "| Benchmark | Status | Seconds | Summary |\n|---|---|---:|---|\n"
        for bench in benches:
            status = "PASS" if bench.passed else "FAIL"
            markdown += f"| `{bench.name}` | {status} | `{bench.seconds:.3f}` | {bench.summary} |\n"
    else:
        markdown += "\n## Quick Benchmark Results\n\n_Not run. Use `--run-fast-bench` to include timing data._\n"

    if run_real_limits and real_measurement:
        markdown += "\n## Real Measured Limits\n\n"
        if real_measurement.passed and real_measurement.metrics:
            markdown += f"- Command: `{real_measurement.command}`\n"
            markdown += f"- Runtime: `{real_measurement.seconds:.3f}s`\n"
            markdown += f"- Max blob round-trip: `{int(real_measurement.metrics.get('blob_max_bytes', 0))}` bytes (`{real_measurement.metrics.get('blob_max_mib', 0)}` MiB)\n"
            markdown += f"- Max string round-trip: `{int(real_measurement.metrics.get('string_max_bytes', 0))}` bytes (`{real_measurement.metrics.get('string_max_mib', 0)}` MiB)\n"
            markdown += f"- Growth run final DB size: `{int(real_measurement.metrics.get('db_growth_final_bytes', 0))}` bytes (`{real_measurement.metrics.get('db_growth_final_gib', 0)}` GiB)\n"
            markdown += f"- Growth inserted records: `{int(real_measurement.metrics.get('db_growth_records_inserted', 0))}`\n"
            markdown += f"- Growth payload per record: `{int(real_measurement.metrics.get('db_growth_payload_bytes_per_record', 0))}` bytes\n"
            markdown += f"- Growth elapsed: `{real_measurement.metrics.get('db_growth_elapsed_seconds', 0)}` seconds\n"
            if derived_real_metrics:
                markdown += f"- Growth throughput: `{derived_real_metrics.get('growth_records_per_second', 0):.2f}` records/sec\n"
                markdown += f"- Growth bandwidth: `{derived_real_metrics.get('growth_mib_per_second', 0):.2f}` MiB/sec\n"
                markdown += f"- Growth average write latency: `{derived_real_metrics.get('growth_avg_write_latency_ms', 0):.3f}` ms/op\n"
            markdown += "\n### Measurement Output Excerpt\n\n"
            markdown += "```\n" + real_measurement.output_excerpt + "\n```\n"
        else:
            markdown += (
                f"- Command: `{real_measurement.command}`\n"
                f"- Runtime: `{real_measurement.seconds:.3f}s`\n"
                "- Status: FAILED to collect real metrics\n"
            )
    else:
        markdown += "\n## Real Measured Limits\n\n_Not run. Use `--run-real-limits` to execute real measurements._\n"

    payload: dict[str, Any] = {
        "generated_at_utc": now,
        "hard_limits": {
            "page_size_bytes": page_size,
            "single_page_plaintext_max_bytes": page_plaintext_max,
            "overflow_main_payload_v2_bytes": main_payload_v2,
            "overflow_page_payload_bytes": max_data_per_overflow_page,
            "overflow_chain_limit_pages": overflow_chain_limit,
            "derived_max_overflow_v2_payload_bytes": max_overflow_v2_payload,
        },
        "api_limits": {
            "batch_insert_max_records": batch_limit,
            "batch_update_max_records": batch_update_limit,
            "batch_delete_max_records": batch_delete_limit,
            "batch_record_encoded_max_bytes": max_record_bytes,
        },
        "codec_guards": {
            "max_string_bytes": max_string_bytes_decoder,
            "max_data_bytes": max_data_bytes_decoder,
            "max_array_count": max_array_count,
            "max_dictionary_count": max_dict_count,
        },
        "resource_warning_defaults": {
            "max_wal_ratio": wal_ratio,
            "max_page_count": health_max_page_count,
            "max_disk_usage_bytes": health_max_disk_bytes,
        },
        "quick_benchmarks": [
            {
                "name": b.name,
                "command": b.command,
                "seconds": b.seconds,
                "passed": b.passed,
                "summary": b.summary,
            }
            for b in benches
        ],
        "real_measurement": (
            {
                "command": real_measurement.command,
                "seconds": real_measurement.seconds,
                "passed": real_measurement.passed,
                "metrics": real_measurement.metrics,
                "derived_metrics": derived_real_metrics,
                "output_excerpt": real_measurement.output_excerpt,
            }
            if real_measurement
            else None
        ),
    }
    return markdown, payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate BlazeDB limits report.")
    parser.add_argument(
        "--run-fast-bench",
        action="store_true",
        help="Also run quick test benchmarks and include timings.",
    )
    parser.add_argument(
        "--run-real-limits",
        action="store_true",
        help="Run real measured limits benchmark (blob/string max + DB growth).",
    )
    parser.add_argument(
        "--real-target-gib",
        type=float,
        default=0.5,
        help="Growth target for --run-real-limits (default: 0.5 GiB).",
    )
    parser.add_argument(
        "--real-payload-bytes",
        type=int,
        default=1_000_000,
        help="Payload bytes per growth record for --run-real-limits.",
    )
    parser.add_argument(
        "--real-batch-size",
        type=int,
        default=8,
        help="Batch size for growth inserts in --run-real-limits.",
    )
    parser.add_argument(
        "--markdown-out",
        default="Docs/Benchmarks/LIMITS.md",
        help="Output markdown path (relative to repo root).",
    )
    parser.add_argument(
        "--json-out",
        default="Docs/Benchmarks/limits_measurements.json",
        help="Output JSON path (relative to repo root).",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    markdown, payload = generate_report(
        repo_root,
        run_fast_bench=args.run_fast_bench,
        run_real_limits=args.run_real_limits,
        real_target_gib=args.real_target_gib,
        real_payload_bytes=args.real_payload_bytes,
        real_batch_size=args.real_batch_size,
    )

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
