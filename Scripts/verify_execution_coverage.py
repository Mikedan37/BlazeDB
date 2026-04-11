#!/usr/bin/env python3
"""
Run a SwiftPM test target with execution undercount gating.

Emits JSON artifact with discovered/executed/missing counts and fails if
executed coverage is below required floor.
"""

from __future__ import annotations

import argparse
import os
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


TEST_ID_RE = re.compile(r"^([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)/([A-Za-z0-9_]+)$")


def run(
    cmd: list[str],
    cwd: Path,
    env: dict[str, str] | None = None,
    *,
    capture: bool = True,
) -> subprocess.CompletedProcess[str] | subprocess.CompletedProcess[bytes]:
    if capture:
        return subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True, check=False, env=env)
    # Stream to inherited stdout/stderr so CI logs stay live during long swift test runs.
    return subprocess.run(cmd, cwd=str(cwd), check=False, env=env)


def parse_discovered(text: str, target: str) -> set[str]:
    discovered: set[str] = set()
    for raw in text.splitlines():
        line = raw.strip()
        m = TEST_ID_RE.match(line)
        if m:
            ident = f"{m.group(1)}.{m.group(2)}/{m.group(3)}"
            if ident.startswith(f"{target}."):
                discovered.add(ident)
    return discovered


def parse_executed_from_xunit(path: Path) -> set[str]:
    if not path.exists():
        return set()
    tree = ET.parse(path)
    root = tree.getroot()
    executed: set[str] = set()
    for tc in root.iter("testcase"):
        classname = tc.attrib.get("classname", "")
        name = tc.attrib.get("name", "")
        if classname and name:
            executed.add(f"{classname}/{name}")
    return executed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, help="SwiftPM test target filter")
    parser.add_argument(
        "--package-path",
        type=str,
        default=None,
        help="Subdirectory (under repo root) with Package.swift, e.g. BlazeDBExtraTests",
    )
    parser.add_argument("--artifact-dir", required=True)
    parser.add_argument("--allowed-missing", type=int, default=0)
    parser.add_argument("--num-workers", type=int, default=1)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    pkg_root = (root / args.package_path).resolve() if args.package_path else root
    artifact_dir = Path(args.artifact_dir)
    artifact_dir.mkdir(parents=True, exist_ok=True)

    # SwiftPM discovery flags vary by toolchain. Prefer modern `swift test list`
    # and rely on parse_discovered() to filter by target prefix.
    print(f">> verify_execution_coverage: discovery (swift test list) for {args.target}", flush=True)
    list_cmd = ["swift", "test", "list", "--skip-build"]
    list_proc = run(list_cmd, pkg_root)
    if list_proc.returncode != 0:
        # Fallback for older SwiftPM supporting legacy flag style.
        list_proc = run(["swift", "test", "--list-tests"], pkg_root)
    if list_proc.returncode != 0:
        print(list_proc.stdout)
        print(list_proc.stderr, file=sys.stderr)
        print(f"DISCOVERY_FAILED:{args.target}", file=sys.stderr)
        return 20

    discovered = parse_discovered(str(list_proc.stdout), args.target)
    xunit_path = artifact_dir / f"{args.target}.xunit.xml"
    run_cmd = [
        "swift",
        "test",
        "--filter",
        args.target,
        "--parallel",
        "--num-workers",
        str(args.num_workers),
        "--xunit-output",
        str(xunit_path),
    ]
    run_env = os.environ.copy()
    if args.target == "BlazeDB_Tier0":
        run_env["BLAZEDB_TEST_SCOPE"] = "tier0"
    print(
        f">> verify_execution_coverage: running swift test (parallel workers={args.num_workers}) for {args.target}",
        flush=True,
    )
    run_proc = run(run_cmd, pkg_root, env=run_env, capture=False)

    executed = parse_executed_from_xunit(xunit_path)
    missing = sorted(discovered - executed)

    payload = {
        "target": args.target,
        "discoveredCount": len(discovered),
        "executedCount": len(executed),
        "allowedMissing": args.allowed_missing,
        "missingCount": len(missing),
        "missing": missing,
        "runExitCode": run_proc.returncode,
        "environment": {
            "swiftVersion": run(["swift", "--version"], root).stdout.strip(),
            "xcodeVersion": run(["xcodebuild", "-version"], root).stdout.strip(),
            "arch": run(["uname", "-m"], root).stdout.strip(),
            "numWorkers": args.num_workers,
            "tmpdir": os.environ.get("TMPDIR", ""),
            "seed": os.environ.get("BLAZEDB_TEST_SEED", ""),
        },
    }
    out_path = artifact_dir / f"{args.target}.execution.json"
    out_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    # First honor test execution failure (stdout/stderr only when capture was used).
    if run_proc.returncode != 0:
        out = run_proc.stdout
        err = run_proc.stderr
        if out:
            sys.stdout.write(out if isinstance(out, str) else out.decode("utf-8", errors="replace"))
        if err:
            sys.stderr.write(err if isinstance(err, str) else err.decode("utf-8", errors="replace"))
        return run_proc.returncode

    if len(missing) > args.allowed_missing:
        print(
            f"PLAN_EXECUTION_UNDERCOUNT:{args.target}:"
            f"discovered={len(discovered)} executed={len(executed)} missing={len(missing)}"
        )
        return 21
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
