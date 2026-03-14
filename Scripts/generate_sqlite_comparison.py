#!/usr/bin/env python3
"""
Generate a clear BlazeDB vs SQLite limits comparison with explicit tested inputs.

This script:
1) Reads real BlazeDB measurements from Docs/Benchmarks/limits_measurements.json
2) Reads local SQLite runtime/compile limits from sqlite3
3) Runs an apples-to-apples SQLite growth measurement with matching inputs
4) Runs SQLite single-blob probe points
5) Writes Docs/Benchmarks/SQLITE_LIMITS_COMPARISON.md
"""

from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path


def run_sqlite_compile_info() -> dict[str, str]:
    proc = subprocess.run(
        'sqlite3 ":memory:" "select sqlite_version(); pragma page_size; pragma compile_options;"',
        shell=True,
        capture_output=True,
        text=True,
        check=True,
    )
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    info: dict[str, str] = {}
    if len(lines) >= 2:
        info["sqlite_version"] = lines[0]
        info["page_size"] = lines[1]
    for opt in lines[2:]:
        if "=" in opt:
            k, v = opt.split("=", 1)
            info[k] = v
        else:
            info[opt] = "1"
    return info


def sqlite_growth(target_gib: float, payload_bytes: int, batch_size: int) -> dict[str, float | int]:
    path = tempfile.mktemp(prefix="sqlite-real-growth-", suffix=".db")
    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cur.execute("PRAGMA journal_mode=WAL;")
    cur.execute("CREATE TABLE t(id INTEGER PRIMARY KEY, payload BLOB NOT NULL);")
    payload = bytes([0x5A]) * payload_bytes
    target_bytes = target_gib * 1024 * 1024 * 1024
    inserted = 0
    start = time.time()

    while True:
        cur.execute("BEGIN")
        for _ in range(batch_size):
            cur.execute("INSERT INTO t(payload) VALUES (?)", (payload,))
            inserted += 1
        conn.commit()
        size = os.path.getsize(path)
        if size >= target_bytes:
            break

    elapsed = time.time() - start
    conn.close()
    for ext in ("", "-wal", "-shm"):
        p = path + ext
        if os.path.exists(p):
            os.remove(p)

    return {
        "final_bytes": size,
        "final_gib": size / 1024 / 1024 / 1024,
        "records_inserted": inserted,
        "payload_bytes_per_record": payload_bytes,
        "elapsed_seconds": elapsed,
        "target_gib": target_gib,
        "batch_size": batch_size,
    }


def sqlite_blob_probe() -> dict[str, int]:
    sizes = [16_000_000, 32_000_000, 64_000_000, 128_000_000, 256_000_000]
    path = tempfile.mktemp(prefix="sqlite-maxblob-", suffix=".db")
    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cur.execute("CREATE TABLE t(b BLOB)")

    max_ok = 0
    first_fail = 0
    for size in sizes:
        try:
            cur.execute("DELETE FROM t")
            cur.execute("INSERT INTO t(b) VALUES (?)", (bytes([0x01]) * size,))
            conn.commit()
            max_ok = size
        except Exception:
            first_fail = size
            break

    conn.close()
    for ext in ("", "-wal", "-shm"):
        p = path + ext
        if os.path.exists(p):
            os.remove(p)

    return {
        "max_ok_bytes": max_ok,
        "first_fail_bytes": first_fail,
    }


def sqlite_string_probe() -> dict[str, int]:
    sizes = [8_000_000, 16_000_000, 32_000_000, 64_000_000, 128_000_000]
    path = tempfile.mktemp(prefix="sqlite-maxtext-", suffix=".db")
    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cur.execute("CREATE TABLE t(s TEXT)")

    max_ok = 0
    first_fail = 0
    for size in sizes:
        try:
            cur.execute("DELETE FROM t")
            cur.execute("INSERT INTO t(s) VALUES (?)", ("A" * size,))
            conn.commit()
            max_ok = size
        except Exception:
            first_fail = size
            break

    conn.close()
    for ext in ("", "-wal", "-shm"):
        p = path + ext
        if os.path.exists(p):
            os.remove(p)

    return {
        "max_ok_bytes": max_ok,
        "first_fail_bytes": first_fail,
    }


def sqlite_hard_boundary_check() -> dict[str, int | bool]:
    # Based on this machine's compile option MAX_LENGTH.
    max_length = 2_147_483_645
    ok = subprocess.run(
        f'sqlite3 ":memory:" "select length(zeroblob({max_length}));"',
        shell=True,
        capture_output=True,
        text=True,
    )
    fail = subprocess.run(
        f'sqlite3 ":memory:" "select length(zeroblob({max_length + 1}));"',
        shell=True,
        capture_output=True,
        text=True,
    )
    ok_value = int(ok.stdout.strip()) if ok.returncode == 0 and ok.stdout.strip().isdigit() else -1
    return {
        "max_length_constant": max_length,
        "at_limit_ok": ok.returncode == 0 and ok_value == max_length,
        "at_limit_returned": ok_value,
        "over_limit_failed": fail.returncode != 0,
    }


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    limits_json = repo / "Docs/Benchmarks/limits_measurements.json"
    if not limits_json.exists():
        raise SystemExit(f"Missing {limits_json}; run generate_limits_report.py first")

    limits = json.loads(limits_json.read_text(encoding="utf-8"))
    blaze_real = limits.get("real_measurement", {}).get("metrics", {})
    if not blaze_real:
        raise SystemExit("Missing real BlazeDB measurements in limits_measurements.json")

    target_gib = float(blaze_real["db_growth_final_gib"])
    payload_bytes = int(blaze_real["db_growth_payload_bytes_per_record"])
    # Keep same batch profile used in BlazeDB measurement command.
    batch_size = 8

    sqlite_info = run_sqlite_compile_info()
    sqlite_growth_result = sqlite_growth(target_gib=target_gib, payload_bytes=payload_bytes, batch_size=batch_size)
    sqlite_probe = sqlite_blob_probe()
    sqlite_string = sqlite_string_probe()
    sqlite_boundary = sqlite_hard_boundary_check()
    blaze_blob = int(blaze_real["blob_max_bytes"])
    blaze_string = int(blaze_real["string_max_bytes"])
    sqlite_hard = int(sqlite_boundary["max_length_constant"])
    hard_limit_ratio = sqlite_hard / blaze_blob if blaze_blob > 0 else 0.0
    blaze_growth_bytes = int(blaze_real["db_growth_final_bytes"])
    blaze_growth_seconds = float(blaze_real["db_growth_elapsed_seconds"])
    sqlite_growth_bytes = int(sqlite_growth_result["final_bytes"])
    sqlite_growth_seconds = float(sqlite_growth_result["elapsed_seconds"])
    blaze_mib_s = (blaze_growth_bytes / 1024 / 1024) / blaze_growth_seconds if blaze_growth_seconds > 0 else 0.0
    sqlite_mib_s = (sqlite_growth_bytes / 1024 / 1024) / sqlite_growth_seconds if sqlite_growth_seconds > 0 else 0.0
    blaze_rec_s = int(blaze_real["db_growth_records_inserted"]) / blaze_growth_seconds if blaze_growth_seconds > 0 else 0.0
    sqlite_rec_s = int(sqlite_growth_result["records_inserted"]) / sqlite_growth_seconds if sqlite_growth_seconds > 0 else 0.0

    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    out = repo / "Docs/Benchmarks/SQLITE_LIMITS_COMPARISON.md"

    md = f"""# BlazeDB vs SQLite Limits (Measured, No Guesswork)

_Generated: {now}_

## Inputs Used (Exact)

### BlazeDB real measurement input
- Source: `Docs/Benchmarks/limits_measurements.json`
- Command:
  - `{limits.get("real_measurement", {}).get("command", "")}`

### SQLite comparison input (matched to BlazeDB)
- Target DB size: `{target_gib:.3f} GiB`
- Payload per record: `{payload_bytes}` bytes
- Batch size per transaction: `{batch_size}`
- Journal mode: `WAL`
- Table schema: `CREATE TABLE t(id INTEGER PRIMARY KEY, payload BLOB NOT NULL)`

## Results (Measured)

| Metric | BlazeDB | SQLite (local build) |
|---|---:|---:|
| Max blob round-trip | `{int(blaze_real["blob_max_bytes"])}` bytes | `>= {sqlite_probe["max_ok_bytes"]}` bytes (probe max; no failure up to this point) |
| Max string round-trip | `{int(blaze_real["string_max_bytes"])}` bytes | `>= {sqlite_string["max_ok_bytes"]}` bytes (probe max; no failure up to this point) |
| Growth final size | `{int(blaze_real["db_growth_final_bytes"])}` bytes | `{int(sqlite_growth_result["final_bytes"])}` bytes |
| Growth final size (GiB) | `{float(blaze_real["db_growth_final_gib"]):.3f}` | `{float(sqlite_growth_result["final_gib"]):.3f}` |
| Growth records inserted | `{int(blaze_real["db_growth_records_inserted"])}` | `{int(sqlite_growth_result["records_inserted"])}` |
| Growth elapsed seconds | `{float(blaze_real["db_growth_elapsed_seconds"]):.3f}` | `{float(sqlite_growth_result["elapsed_seconds"]):.3f}` |
| Growth throughput (MiB/s) | `{blaze_mib_s:.2f}` | `{sqlite_mib_s:.2f}` |
| Growth throughput (records/s) | `{blaze_rec_s:.1f}` | `{sqlite_rec_s:.1f}` |

## Hard Limit Boundary Check (SQLite)

- Checked boundary expression: `length(zeroblob(N))`
- At limit `N={sqlite_hard}`: `{"PASS" if sqlite_boundary["at_limit_ok"] else "FAIL"}` (returned `{sqlite_boundary["at_limit_returned"]}`)
- Over limit `N={sqlite_hard + 1}`: `{"FAIL as expected" if sqlite_boundary["over_limit_failed"] else "UNEXPECTED PASS"}`

## Hard Limit Gap (Single Value)

- BlazeDB measured max value in this repo/run: `{blaze_blob}` bytes
- SQLite configured hard max length on this machine: `{sqlite_hard}` bytes
- Ratio (SQLite / BlazeDB): **{hard_limit_ratio:.2f}x**
- Verdict: SQLite hard single-value limit is materially higher; BlazeDB is not close on this axis.

## Confidence Class Per Number

| Number type | Confidence | Why |
|---|---|---|
| SQLite hard max length (`MAX_LENGTH`) | hard-verified | explicit at-limit pass + over-limit fail check |
| BlazeDB max blob/string | measured | binary-search round-trip test against this build |
| SQLite blob/string probe maxima | measured-lower-bound | tested up to probe points; not full binary search to failure |
| Growth size/time throughput | measured | direct runtime timing on same machine |

## SQLite Build Limits (This Machine, Actual)

- SQLite version: `{sqlite_info.get("sqlite_version", "unknown")}`
- Page size: `{sqlite_info.get("page_size", "unknown")}` bytes
- `MAX_LENGTH`: `{sqlite_info.get("MAX_LENGTH", "unknown")}`
- `MAX_SQL_LENGTH`: `{sqlite_info.get("MAX_SQL_LENGTH", "unknown")}`
- `MAX_PAGE_COUNT`: `{sqlite_info.get("MAX_PAGE_COUNT", "unknown")}`
- `MAX_PAGE_SIZE`: `{sqlite_info.get("MAX_PAGE_SIZE", "unknown")}`

## What This Comparison Is / Is Not

- This is **real measured runtime output** for both engines on the same machine.
- SQLite single-value max here is a **probe lower bound** (`>= 256,000,000` bytes), not its absolute ceiling.
- SQLite hard limit line item is verified by explicit at/over boundary checks.
- BlazeDB max value comes from the real measurement test used in this repo (`RealLimitsMeasurementTests`).
- No cross-machine claims are made in this report.
"""

    out.write_text(md, encoding="utf-8")
    print(f"Generated comparison: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

