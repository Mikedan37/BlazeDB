#!/usr/bin/env python3
"""
Bootstrap TEST_INVENTORY_MANIFEST.json from real Xcode plan discovery.

This script intentionally avoids filesystem fallback IDs (FS.*) and uses
testgov discovery outputs as the source of truth for bootstrap.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "Docs" / "Testing" / "TEST_INVENTORY_MANIFEST.json"
DEFAULT_ARTIFACTS = ROOT / ".artifacts" / "testgov-bootstrap"


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=str(cwd), check=False, capture_output=True, text=True)


def discover_plan(plan: str, artifacts_root: Path, project: str, scheme: str, destination: str) -> set[str]:
    cmd = [
        "swift",
        "Tools/TestGovernance/testgov.swift",
        "discover",
        "--source",
        "xcode",
        "--project",
        project,
        "--scheme",
        scheme,
        "--plan",
        plan,
        "--destination",
        destination,
        "--lane",
        "local",
        "--artifacts-root",
        str(artifacts_root),
    ]
    proc = run(cmd, ROOT)
    if proc.returncode != 0:
        raise RuntimeError(f"discover failed for {plan}:\n{proc.stdout}\n{proc.stderr}")
    discovered_path = Path(proc.stdout.strip().splitlines()[-1].strip())
    payload = json.loads(discovered_path.read_text(encoding="utf-8"))
    return set(payload.get("tests", []))


def guess_owner(test_id: str) -> str:
    tid = test_id.lower()
    if any(x in tid for x in ["transaction", "wal", "durability", "recovery", "mvcc"]):
        return "Transactions"
    if any(x in tid for x in ["sync", "distributed", "relay", "topology"]):
        return "Sync"
    if any(x in tid for x in ["security", "encrypt", "rls", "auth"]):
        return "Security"
    if any(x in tid for x in ["query", "index", "search", "aggregation"]):
        return "Query"
    if any(x in tid for x in ["telemetry", "metrics", "observability"]):
        return "Observability"
    return "Core"


def guess_deterministic(test_id: str) -> bool:
    tid = test_id.lower()
    nondeterministic_markers = ["fuzz", "chaos", "stress", "soak", "property", "benchmark", "performance"]
    return not any(marker in tid for marker in nondeterministic_markers)


def tier_from_module_prefix(test_id: str) -> str | None:
    module = test_id.split(".", 1)[0]
    if module == "BlazeDB_Tier0":
        return "T0"
    # All three Tier1 SwiftPM modules map to inventory bucket "T1". For human-facing CI
    # status, use Docs/Testing/CI_AND_TEST_TIERS.md (Tier1 PR gate vs depth vs full Tier1).
    # Legacy module name BlazeDB_Tier1 removed — inventory maps split targets only (Tier1Fast/Extended/Perf).
    if module in (
        "BlazeDB_Tier1Fast",
        "BlazeDB_Tier1Extended",
        "BlazeDB_Tier1Perf",
    ):
        return "T1"
    if module == "BlazeDB_Tier2":
        return "T2"
    if module in {"BlazeDB_Tier3_Heavy", "BlazeDB_Tier3_Destructive"}:
        return "T3"
    if module in {"BlazeDB_Benchmarks", "BlazeDBBenchmarks"}:
        return "BENCH"
    return None


def split_id(test_id: str) -> tuple[str, str]:
    module, rest = test_id.split(".", 1)
    return module, rest


def canonical_module_rank(module: str) -> int:
    if module == "BlazeDB_Tier0":
        return 0
    if module in (
        "BlazeDB_Tier1Fast",
        "BlazeDB_Tier1Extended",
        "BlazeDB_Tier1Perf",
    ):
        return 1
    if module == "BlazeDB_Tier2":
        return 2
    if module in {"BlazeDB_Tier3_Heavy", "BlazeDB_Tier3_Destructive"}:
        return 3
    if module in {"BlazeDB_Benchmarks", "BlazeDBBenchmarks"}:
        return 4
    return 10


def choose_canonical_id(ids: set[str]) -> str:
    return sorted(ids, key=lambda tid: (canonical_module_rank(split_id(tid)[0]), tid))[0]


def main() -> int:
    parser = argparse.ArgumentParser(description="Bootstrap authoritative test inventory manifest from Xcode discovery.")
    parser.add_argument("--project", default="BlazeDB.xcodeproj")
    parser.add_argument("--scheme", default="BlazeDB")
    parser.add_argument("--destination", default="platform=macOS")
    parser.add_argument(
        "--plans",
        nargs="*",
        default=["BlazeDB_Quick", "BlazeDB_Core", "BlazeDB_Integration", "BlazeDB_Core_Integration", "BlazeDB_Nightly", "BlazeDB_Destructive"],
    )
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    parser.add_argument("--artifacts-root", default=str(DEFAULT_ARTIFACTS))
    parser.add_argument("--discovered-files", nargs="*", default=[])
    args = parser.parse_args()

    artifacts_root = Path(args.artifacts_root)
    artifacts_root.mkdir(parents=True, exist_ok=True)

    discovered_by_plan: dict[str, set[str]] = {}
    if args.discovered_files:
        for discovered_file in args.discovered_files:
            payload = json.loads(Path(discovered_file).read_text(encoding="utf-8"))
            header = payload.get("header", {})
            plan = header.get("testPlan") or Path(discovered_file).parent.parent.name
            discovered_by_plan.setdefault(plan, set()).update(set(payload.get("tests", [])))
    else:
        for plan in args.plans:
            discovered_by_plan[plan] = discover_plan(plan, artifacts_root, args.project, args.scheme, args.destination)

    quick = discovered_by_plan.get("BlazeDB_Quick", set())
    core = discovered_by_plan.get("BlazeDB_Core", set())
    integration = discovered_by_plan.get("BlazeDB_Integration", set())
    nightly = discovered_by_plan.get("BlazeDB_Nightly", set())
    destructive = discovered_by_plan.get("BlazeDB_Destructive", set())

    all_ids = set().union(*discovered_by_plan.values())
    grouped_by_suffix: dict[str, set[str]] = {}
    for test_id in all_ids:
        _, suffix = split_id(test_id)
        grouped_by_suffix.setdefault(suffix, set()).add(test_id)

    expires_at = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=7)).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    tests: list[dict] = []
    for suffix in sorted(grouped_by_suffix.keys()):
        id_group = grouped_by_suffix[suffix]
        canonical_id = choose_canonical_id(id_group)
        module_tier = tier_from_module_prefix(canonical_id)
        if module_tier is not None:
            tier = module_tier
        elif any(test_id in quick for test_id in id_group):
            tier = "T0"
        elif any(test_id in core for test_id in id_group):
            tier = "T1"
        elif any(test_id in integration for test_id in id_group):
            tier = "T2"
        elif any(test_id in destructive for test_id in id_group) or any(test_id in nightly for test_id in id_group):
            tier = "T3"
        else:
            tier = "UNASSIGNED"

        aliases = sorted(alias for alias in id_group if alias != canonical_id)
        entry = {
            "id": canonical_id,
            "tier": tier,
            "owner": guess_owner(canonical_id),
            "deterministic": guess_deterministic(canonical_id),
        }
        if aliases:
            entry["aliases"] = aliases
        if tier == "UNASSIGNED":
            entry["unassignedExpiresAt"] = expires_at
        tests.append(entry)

    manifest = {
        "manifestVersion": 1,
        "updatedAt": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "tests": tests,
    }

    manifest_path = Path(args.manifest)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote manifest: {manifest_path}")
    print(f"tests: {len(tests)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

