#!/usr/bin/env python3
"""
Legacy compatibility wrapper for testing governance.

Authoritative governance now lives in Tools/TestGovernance/testgov.swift.
This script delegates to:
  - Scripts/bootstrap_test_inventory_manifest.py (optional bootstrap)
  - Scripts/testgov_ci.sh (policy validation)
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run(cmd: list[str]) -> int:
    proc = subprocess.run(cmd, cwd=str(ROOT), check=False)
    return proc.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description="Delegate inventory governance to testgov.")
    parser.add_argument("--bootstrap-manifest", action="store_true")
    parser.add_argument("--lane", default="pr", choices=["local", "pr", "nightly", "release"])
    parser.add_argument("--allow-fallback-filesystem", action="store_true")
    args = parser.parse_args()

    if args.allow_fallback_filesystem:
        print("WARN: --allow-fallback-filesystem is deprecated and ignored.")

    if args.bootstrap_manifest:
        code = run(["python3", "Scripts/bootstrap_test_inventory_manifest.py"])
        if code != 0:
            return code

    return run(["bash", "Scripts/testgov_ci.sh", args.lane])


if __name__ == "__main__":
    raise SystemExit(main())
