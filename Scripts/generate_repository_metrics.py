#!/usr/bin/env python3
"""
BlazeDB repository metrics (size + health).

Sole file inventory: `git ls-files`.
Produces:
  .metrics/repository-metrics.json   (source of truth)
  Docs/Meta/REPOSITORY_METRICS.md    (rendered from JSON)

Modes (via argv or repo-metrics.sh):
  (default)  write JSON + Markdown
  --check    fail if committed outputs are stale (ignore generated_at)
  --diff     print delta vs committed JSON without writing
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
JSON_REL = Path(".metrics/repository-metrics.json")
MD_REL = Path("Docs/Meta/REPOSITORY_METRICS.md")
INVENTORY_REL = Path("Docs/Audit/DOCUMENTATION_INVENTORY_2026_07.md")

# Curated architecture classification (NOT derived by the script).
CURATED_SUBSYSTEMS = [
    "engine core",
    "storage/WAL",
    "query",
    "crypto",
    "transactions",
    "C ABI",
    "CLI",
]

# Root Package.swift test targets → CI lane membership (from Docs/Testing/CI_AND_TEST_TIERS.md
# and .github/workflows). Exact static mapping; update when lanes change.
TEST_TARGET_LANES: dict[str, dict[str, Any]] = {
    "BlazeDB_Tier0": {
        "path": "BlazeDBTests/Tier0Core",
        "lanes": ["pr_macos", "pr_linux", "nightly_macos_tsan", "release_macos"],
    },
    "BlazeDB_CLITests": {
        "path": "BlazeDBCLITests",
        "lanes": ["pr_macos", "pr_linux", "release_macos"],
    },
    "BlazeDB_Tier1": {
        "path": "BlazeDBTests/Tier1Core",
        "lanes": ["pr_macos", "nightly_linux", "release_macos"],
    },
    "BlazeDB_SwiftUITests": {
        "path": "BlazeDBTests/SwiftUI",
        "lanes": [],
        "note": "Declared in Package.swift; not filtered in ci/nightly/deep/release",
    },
    "BlazeDB_Tier2": {
        "path": "BlazeDBTests/Tier2Integration/BlazeDBIntegrationTests",
        "lanes": ["nightly_macos", "nightly_linux", "release_macos"],
    },
    "BlazeDB_Tier2_Extended": {
        "path": "BlazeDBTests/Tier1Extended",
        "lanes": ["weekly_linux", "release_macos"],
    },
    "BlazeDB_Tier3_Heavy": {
        "path": "BlazeDBTests/Tier3Heavy",
        "lanes": ["weekly_macos", "weekly_linux", "release_macos"],
    },
    "BlazeDB_Tier3_Heavy_Perf": {
        "path": "BlazeDBTests/Tier1Perf",
        "lanes": ["weekly_macos", "weekly_linux", "release_macos"],
    },
    "BlazeDB_Tier3_Destructive": {
        "path": "BlazeDBTests/Tier3Destructive",
        "lanes": ["weekly_macos"],
        "note": "Weekly deep only; not in release.yml; not Linux CI",
    },
    "BlazeDB_Staging": {
        "path": "BlazeDBTests/Staging",
        "lanes": [],
        "note": "Declared; listed by swift test list; not in CI filters",
    },
}

TEST_TREES = (
    "Tests/",
    "BlazeDBTests/",
    "BlazeDBIntegrationTests/",
    "BlazeDBCLITests/",
    "BlazeDBVisualizerTests/",
    "BlazeDBExtraTests/",
    "BlazeDBTests_SPM/",
)

BINARY_EXT = {
    "png", "jpg", "jpeg", "gif", "webp", "ico", "icns", "bmp", "tiff", "tif",
    "pdf", "zip", "gz", "tgz", "xz", "bz2", "7z", "rar", "jar", "war",
    "dylib", "so", "a", "o", "obj", "lib", "exe", "dll", "wasm", "bc",
    "mp3", "mp4", "mov", "wav", "aac", "m4a", "webm",
    "ttf", "otf", "woff", "woff2", "eot",
    "class", "dex", "apk", "aab", "nib", "xcuserstate",
    "sqlite", "sqlite3", "db", "realm", "bin", "dat", "pak",
}
TEXT_EXT = {
    "swift", "md", "markdown", "txt", "sh", "bash", "zsh", "py", "rb", "pl",
    "c", "h", "cc", "cpp", "hpp", "m", "mm", "metal", "json", "yml", "yaml",
    "toml", "xml", "plist", "html", "css", "js", "ts", "tsx", "jsx", "cmake",
    "gradle", "kts", "properties", "xcconfig", "pbxproj", "xcworkspacedata",
    "modulemap", "swiftinterface", "podspec", "csv", "tsv", "sql", "kt",
    "java", "go", "rs", "entitlements", "xctestplan", "xcscheme", "svg",
    "mdc", "def", "bat", "html", "resolved", "gitignore",
}

XCTEST_FN = re.compile(r"^\s*func\s+(test[A-Za-z0-9_]*)\s*\(", re.M)
SWIFT_TEST = re.compile(r"@Test\b")
XCTSKIP = re.compile(r"\bXCTSkip\b|throw\s+XCTSkip")
PLATFORM_IF = re.compile(r"#if\s+os\(")
HELPER_HINT = re.compile(r"(Fixture|Helper|Support|Harness|Mock|Stub)", re.I)
LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+)$", re.M)
HTML_ID_RE = re.compile(r'\bid=["\']([^"\']+)["\']', re.I)
INVENTORY_ROW = re.compile(
    r"^\| `([^`]+)` \| ([^|]+) \| [^|]+ \| ([^|]+) \| "
    r"(KEEP_CANONICAL|KEEP_REFERENCE|MERGE|ARCHIVE|DELETE_CANDIDATE|REVIEW_REQUIRED) \| "
    r"([^|]*) \| ([^|]*) \|$"
)
TEST_ID_RE = re.compile(
    r"^([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)/([A-Za-z0-9_]+)$"
)


def run_git_ls_files() -> list[str]:
    out = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
    return [p for p in out.decode("utf-8", "replace").split("\0") if p]


def is_noise(path: str) -> bool:
    return path.startswith((
        ".build/", "DerivedData/", "Carthage/", "Vendor/", "vendor/",
        "node_modules/", ".git/",
    ))


def is_binary(path: Path) -> bool:
    ext = path.suffix.lower().lstrip(".")
    if ext in BINARY_EXT:
        return True
    if ext in TEXT_EXT or path.name in {
        "Package.swift", "Package.resolved", "Makefile", "Dockerfile",
        "LICENSE", "CHANGELOG.md", "VERSION", "dev",
    }:
        return False
    try:
        data = path.read_bytes()
    except OSError:
        return True
    return b"\0" in data


def line_count(path: Path) -> int:
    try:
        # Count newlines; match wc -l behavior for text without final newline.
        data = path.read_bytes()
    except OSError:
        return 0
    if not data:
        return 0
    return data.count(b"\n") + (0 if data.endswith(b"\n") else 1)


def is_test_tree(path: str) -> bool:
    return any(path.startswith(p) for p in TEST_TREES)


def is_docs_bucket(path: str) -> bool:
    if path.startswith("Docs/"):
        return True
    return path.lower().endswith((".md", ".markdown"))


def is_source_bucket(path: str) -> bool:
    if is_noise(path) or is_test_tree(path) or is_docs_bucket(path):
        return False
    if path.startswith(("Examples/", "Scripts/", "Docs/scripts/")):
        return False
    return True


def ext_of(path: str) -> str:
    name = Path(path).name
    if "." not in name:
        return "(none)"
    return name.rsplit(".", 1)[-1].lower()


def dir_key(path: str) -> str:
    parts = Path(path).parts
    if len(parts) >= 2:
        return f"{parts[0]}/{parts[1]}"
    if parts:
        return parts[0]
    return "(repo-root)"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_package_counts(text: str) -> dict[str, int]:
    products = len(re.findall(r"^\s*\.(library|executable|plugin)\(", text, re.M))
    targets = len(re.findall(
        r"^\s*\.(target|testTarget|executableTarget|systemLibrary)\(", text, re.M
    ))
    return {"products": products, "targets": targets}


def collect_size(tracked: list[str]) -> dict[str, Any]:
    text_files: list[tuple[str, int, str]] = []
    for rel in tracked:
        if is_noise(rel):
            continue
        p = ROOT / rel
        if not p.is_file() or is_binary(p):
            continue
        n = line_count(p)
        text_files.append((rel, n, ext_of(rel)))

    def sum_where(pred) -> tuple[int, int]:
        files = lines = 0
        for rel, n, _ in text_files:
            if pred(rel):
                files += 1
                lines += n
        return files, lines

    total_lines = sum(n for _, n, _ in text_files)
    swift_f, swift_l = sum_where(lambda r: r.endswith(".swift"))
    md_f, md_l = sum_where(lambda r: r.lower().endswith((".md", ".markdown")))
    src_f, src_l = sum_where(is_source_bucket)
    test_f, test_l = sum_where(is_test_tree)
    docs_f, docs_l = sum_where(is_docs_bucket)
    blaze_f, blaze_l = sum_where(lambda r: r.startswith("BlazeDB/"))
    tests_pref_f, tests_pref_l = sum_where(lambda r: r.startswith("Tests/"))
    docs_pref_f, docs_pref_l = sum_where(lambda r: r.startswith("Docs/"))
    archive_f, archive_l = sum_where(lambda r: r.startswith("Docs/Archive/"))

    by_ext: Counter[str] = Counter()
    by_ext_lines: Counter[str] = Counter()
    by_dir_files: Counter[str] = Counter()
    by_dir_lines: Counter[str] = Counter()
    for rel, n, ext in text_files:
        by_ext[ext] += 1
        by_ext_lines[ext] += n
        dk = dir_key(rel)
        by_dir_files[dk] += 1
        by_dir_lines[dk] += n

    pkg = parse_package_counts((ROOT / "Package.swift").read_text(encoding="utf-8", errors="replace"))

    ratio = round(test_l / src_l, 2) if src_l else None

    return {
        "precision": "exact",
        "tracked_paths": len(tracked),
        "tracked_text_files": len(text_files),
        "tracked_text_lines": total_lines,
        "swift_files": swift_f,
        "swift_lines": swift_l,
        "markdown_files": md_f,
        "markdown_lines": md_l,
        "source_files": src_f,
        "source_lines": src_l,
        "test_files": test_f,
        "test_lines": test_l,
        "docs_bucket_files": docs_f,
        "docs_bucket_lines": docs_l,
        "blazedb_engine_files": blaze_f,
        "blazedb_engine_lines": blaze_l,
        "tests_prefix_files": tests_pref_f,
        "tests_prefix_lines": tests_pref_l,
        "docs_prefix_files": docs_pref_f,
        "docs_prefix_lines": docs_pref_l,
        "archive_docs_files": archive_f,
        "archive_docs_lines": archive_l,
        "test_to_source_line_ratio": ratio,
        "package_products": pkg["products"],
        "package_targets": pkg["targets"],
        "by_extension": [
            {"extension": e, "files": by_ext[e], "lines": by_ext_lines[e]}
            for e in sorted(by_ext, key=lambda x: (-by_ext[x], x))
        ],
        "top_dirs_by_files": [
            {"directory": d, "files": by_dir_files[d], "lines": by_dir_lines[d]}
            for d, _ in by_dir_files.most_common(20)
        ],
        "top_dirs_by_lines": [
            {"directory": d, "lines": by_dir_lines[d], "files": by_dir_files[d]}
            for d, _ in by_dir_lines.most_common(20)
        ],
        "_text_index": text_files,  # internal, stripped before write
    }


def collect_swift_decls(text_files: list[tuple[str, int, str]]) -> dict[str, Any]:
    class_re = re.compile(
        r"^\s*(?:(?:public|open|internal|fileprivate|private)\s+)*(?:final\s+)?class\s+[A-Za-z_]",
        re.M,
    )
    struct_re = re.compile(
        r"^\s*(?:(?:public|open|internal|fileprivate|private)\s+)*(?:final\s+)?struct\s+[A-Za-z_]",
        re.M,
    )
    proto_re = re.compile(
        r"^\s*(?:(?:public|open|internal|fileprivate|private)\s+)?protocol\s+[A-Za-z_]",
        re.M,
    )
    enum_re = re.compile(
        r"^\s*(?:(?:public|open|internal|fileprivate|private)\s+)*(?:indirect\s+)?enum\s+[A-Za-z_]",
        re.M,
    )
    counts = Counter()
    for rel, _, ext in text_files:
        if ext != "swift":
            continue
        try:
            text = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        counts["class"] += len(class_re.findall(text))
        counts["struct"] += len(struct_re.findall(text))
        counts["protocol"] += len(proto_re.findall(text))
        counts["enum"] += len(enum_re.findall(text))
    return {
        "precision": "approximate",
        "note": "Line-anchored regex over tracked *.swift; nested/extension forms may skew counts.",
        "class": counts["class"],
        "struct": counts["struct"],
        "protocol": counts["protocol"],
        "enum": counts["enum"],
    }


def collect_tests(tracked: list[str], text_files: list[tuple[str, int, str]]) -> dict[str, Any]:
    test_swift = [rel for rel, _, ext in text_files if ext == "swift" and is_test_tree(rel)]
    xctest_decls = 0
    swift_testing = 0
    skip_hits = 0
    skip_files: list[str] = []
    platform_files: list[str] = []
    helpers: list[str] = []
    files_with_tests: set[str] = set()
    quarantine_hits = 0

    for rel in test_swift:
        try:
            text = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        tests = XCTEST_FN.findall(text)
        xctest_decls += len(tests)
        if tests:
            files_with_tests.add(rel)
        st = len(SWIFT_TEST.findall(text))
        swift_testing += st
        if st:
            files_with_tests.add(rel)
        sk = len(XCTSKIP.findall(text))
        if sk:
            skip_hits += sk
            skip_files.append(rel)
        if PLATFORM_IF.search(text):
            platform_files.append(rel)
        if re.search(r"quarantine|flaky", text, re.I):
            quarantine_hits += 1
        if rel not in files_with_tests and (
            HELPER_HINT.search(rel) or "Fixture" in rel or rel.endswith("Helpers.swift")
        ):
            helpers.append(rel)
        elif rel not in files_with_tests and rel.endswith(".swift"):
            # Swift file in test tree with no test declaration
            helpers.append(rel)

    # Byte-identical duplicates among test swift files
    hashes: dict[str, list[str]] = defaultdict(list)
    for rel in test_swift:
        p = ROOT / rel
        if p.is_file():
            hashes[sha256_file(p)].append(rel)
    duplicates = [
        {"sha256": h, "paths": sorted(paths)}
        for h, paths in hashes.items()
        if len(paths) > 1
    ]

    # Wired SPM paths vs orphan on-disk test trees
    wired_prefixes = [v["path"].rstrip("/") + "/" for v in TEST_TARGET_LANES.values()]
    wired_files = [r for r in test_swift if any(r.startswith(p) or r.startswith(p.rstrip("/")) for p in [x.rstrip("/") for x in wired_prefixes]) or any(r.startswith(pref) for pref in wired_prefixes)]
    # Fix: path may be exact directory
    def under_wired(rel: str) -> bool:
        for info in TEST_TARGET_LANES.values():
            base = info["path"]
            if rel == base or rel.startswith(base + "/"):
                return True
        return False

    wired = [r for r in test_swift if under_wired(r)]
    orphan = [r for r in test_swift if not under_wired(r)]

    # Unreferenced fixtures (heuristic): *Fixture*.swift with zero inbound path mentions
    fixture_cands = [r for r in test_swift if "Fixture" in Path(r).name]
    unref_fixtures: list[dict[str, Any]] = []
    # Build cheap mention index from test swift only
    blob_by_file = {}
    for rel in test_swift:
        try:
            blob_by_file[rel] = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            blob_by_file[rel] = ""
    for fix in fixture_cands:
        base = Path(fix).name
        stem = Path(fix).stem
        refs = 0
        for other, text in blob_by_file.items():
            if other == fix:
                continue
            if base in text or stem in text:
                refs += 1
                break
        if refs == 0:
            unref_fixtures.append({
                "path": fix,
                "evidence": "No other tracked test-tree Swift file mentions this fixture basename/stem",
                "confidence": "low",
                "why_manual_review": "May be loaded by stringly path, SPM resources, or unused",
            })

    # Runner discovery (optional; approximate when .build warm)
    discovered = try_spm_list_tests()

    targets_out = []
    for name, info in TEST_TARGET_LANES.items():
        targets_out.append({
            "target": name,
            "path": info["path"],
            "lanes": info["lanes"],
            "lane_count": len(info["lanes"]),
            "note": info.get("note"),
            "exercised_by_normal_lane": len(info["lanes"]) > 0,
        })

    review: list[dict[str, Any]] = []
    for t in targets_out:
        if not t["exercised_by_normal_lane"]:
            review.append({
                "path": t["path"],
                "kind": "orphan_test_target",
                "evidence": f"Package.swift test target {t['target']} has empty lane list in static CI mapping",
                "confidence": "high",
                "why_manual_review": "May be intentional local-only surface; confirm before removing",
            })
    for dup in duplicates[:20]:
        review.append({
            "path": dup["paths"][0],
            "kind": "duplicate_test_file",
            "evidence": f"SHA256-identical to {len(dup['paths'])} paths: {', '.join(dup['paths'])}",
            "confidence": "high",
            "why_manual_review": "Confirm which copy is canonical before deleting",
        })
    for fix in unref_fixtures[:15]:
        review.append({
            "path": fix["path"],
            "kind": "unreferenced_fixture_candidate",
            "evidence": fix["evidence"],
            "confidence": fix["confidence"],
            "why_manual_review": fix["why_manual_review"],
        })
    for rel in skip_files[:15]:
        review.append({
            "path": rel,
            "kind": "contains_XCTSkip",
            "evidence": "File contains XCTSkip / throw XCTSkip",
            "confidence": "medium",
            "why_manual_review": "Skipped paths may be platform-conditional or permanently disabled",
        })

    return {
        "precision_notes": {
            "xctest_func_test_declarations": "approximate — source pattern; not equal to executed cases",
            "swift_testing_at_test": "approximate — declaration count",
            "runner_discovered_tests": discovered.get("precision", "unavailable"),
            "lane_mapping": "exact — curated from CI docs/workflows; update when CI changes",
        },
        "test_tree_swift_files": len(test_swift),
        "xctest_func_test_declarations": xctest_decls,
        "swift_testing_at_test_declarations": swift_testing,
        "files_with_at_least_one_test_declaration": len(files_with_tests),
        "helper_or_fixture_swift_files_without_test_decl": len(set(helpers)),
        "helper_sample": sorted(set(helpers))[:25],
        "xctskip_occurrence_count": skip_hits,
        "files_with_xctskip": skip_files,
        "files_with_os_conditional": platform_files,
        "quarantine_or_flaky_mention_files": quarantine_hits,
        "byte_identical_duplicate_groups": duplicates,
        "wired_spm_test_swift_files": len(wired),
        "orphan_on_disk_test_swift_files": len(orphan),
        "orphan_on_disk_sample": orphan[:30],
        "unreferenced_fixture_candidates": unref_fixtures,
        "spm_targets": targets_out,
        "targets_not_in_any_normal_lane": [
            t["target"] for t in targets_out if not t["exercised_by_normal_lane"]
        ],
        "runner_discovery": discovered,
        "review_candidates": review,
    }


def try_spm_list_tests() -> dict[str, Any]:
    """Attempt `swift test list --skip-build`. Never fails the metrics run."""
    env = os.environ.copy()
    env.pop("BLAZEDB_TEST_SCOPE", None)
    try:
        proc = subprocess.run(
            ["swift", "test", "list", "--skip-build"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=180,
            env=env,
        )
        if proc.returncode != 0:
            proc = subprocess.run(
                ["swift", "test", "--list-tests"],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=180,
                env=env,
            )
        if proc.returncode != 0:
            return {
                "precision": "unavailable",
                "status": "failed",
                "stderr_tail": (proc.stderr or "")[-500:],
                "note": "Requires warm .build with full test products; unset BLAZEDB_TEST_SCOPE",
            }
        by_target: Counter[str] = Counter()
        ids: list[str] = []
        for raw in proc.stdout.splitlines():
            line = raw.strip()
            m = TEST_ID_RE.match(line)
            if not m:
                # Also accept "Target.Suite/test" without strict regex variants
                if "/" in line and "." in line and not line.startswith("["):
                    ids.append(line)
                    by_target[line.split(".", 1)[0]] += 1
                continue
            ident = f"{m.group(1)}.{m.group(2)}/{m.group(3)}"
            ids.append(ident)
            by_target[m.group(1)] += 1
        return {
            "precision": "approximate",
            "status": "ok",
            "discovered_count": len(ids),
            "by_target": dict(sorted(by_target.items())),
            "note": (
                "swift test list --skip-build; may undercount if package was last "
                "evaluated with BLAZEDB_TEST_SCOPE=tier0 or stale build graph"
            ),
        }
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return {
            "precision": "unavailable",
            "status": "error",
            "error": str(e),
        }


def norm_anchor(text: str) -> str:
    t = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    t = re.sub(r"[^\w\s\-]", "", t.strip().lower())
    return re.sub(r"\s+", "-", t)


def collect_docs(tracked: list[str]) -> dict[str, Any]:
    md_files = [p for p in tracked if p.lower().endswith(".md")]
    inventory_path = ROOT / INVENTORY_REL
    inventory_used = False
    inventory_tracked = INVENTORY_REL.as_posix() in set(tracked)
    classifications: dict[str, dict[str, str]] = {}
    if inventory_path.is_file():
        inventory_used = True
        for line in inventory_path.read_text(encoding="utf-8", errors="replace").splitlines():
            m = INVENTORY_ROW.match(line.strip())
            if not m:
                continue
            classifications[m.group(1)] = {
                "audience": m.group(2).strip(),
                "reachable_from": m.group(3).strip(),
                "recommendation": m.group(4).strip(),
                "canonical_destination": m.group(5).strip(),
                "evidence": m.group(6).strip(),
            }

    rec_counts = Counter(v["recommendation"] for v in classifications.values())

    # Map recommendations → activity buckets
    active_canonical = [p for p, v in classifications.items() if v["recommendation"] == "KEEP_CANONICAL"]
    active_reference = [p for p, v in classifications.items() if v["recommendation"] == "KEEP_REFERENCE"]
    archive_rec = [p for p, v in classifications.items() if v["recommendation"] == "ARCHIVE"]
    merge_rec = [p for p, v in classifications.items() if v["recommendation"] == "MERGE"]
    delete_cand = [p for p, v in classifications.items() if v["recommendation"] == "DELETE_CANDIDATE"]
    review_rec = [p for p, v in classifications.items() if v["recommendation"] == "REVIEW_REQUIRED"]

    archive_dir = [p for p in md_files if p.startswith("Docs/Archive/")]
    generated = [
        p for p in md_files
        if p.endswith("REPOSITORY_METRICS.md")
        or "generated" in p.lower()
        or p.startswith("Docs/Benchmarks/results_")
    ]

    # Reachability from primary entry points via markdown links
    entry = ["README.md", "CONTRIBUTING.md", "ROADMAP.md", "Docs/README.md"]
    entry = [e for e in entry if e in set(md_files)]
    contents = {}
    anchors = {}
    for rel in md_files:
        try:
            text = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""
        contents[rel] = text
        heads = {norm_anchor(m.group(2)) for m in HEADING_RE.finditer(text)}
        ids = set(HTML_ID_RE.findall(text))
        anchors[rel] = heads | ids | {norm_anchor(i) for i in ids}

    md_set = set(md_files)
    outbound: dict[str, list[str]] = defaultdict(list)
    broken_files: list[dict[str, str]] = []
    broken_anchors: list[dict[str, str]] = []

    def resolve(src: str, href: str) -> tuple[str | None, str | None]:
        href = href.strip()
        if not href or href.startswith(("http://", "https://", "mailto:")):
            return None, None
        if " " in href:
            href = href.split(" ")[0].strip("\"'")
        parsed = urlparse(href)
        path = unquote(parsed.path)
        frag = unquote(parsed.fragment) if parsed.fragment else None
        if href.startswith("#"):
            return src, href[1:]
        if not path:
            return src, frag
        if path.startswith("/"):
            target = path.lstrip("/")
        else:
            target = str((Path(src).parent / path).as_posix())
            parts: list[str] = []
            for part in target.split("/"):
                if part == "..":
                    if parts:
                        parts.pop()
                elif part not in (".", ""):
                    parts.append(part)
            target = "/".join(parts)
        return target, frag

    for src, text in contents.items():
        for m in LINK_RE.finditer(text):
            target, frag = resolve(src, m.group(2))
            if target is None:
                continue
            if target not in md_set and not (ROOT / target).exists():
                # skip weird line-range links
                if ":" in Path(target).name and not target.endswith(".md"):
                    continue
                broken_files.append({"src": src, "href": m.group(2).strip(), "resolved": target})
                continue
            if target in md_set:
                outbound[src].append(target)
                if frag:
                    cands = {norm_anchor(frag), frag.lower()}
                    if not any(c in anchors[target] for c in cands):
                        # known HTML-id false positives already in anchors set if present
                        broken_anchors.append({
                            "src": src, "href": m.group(2).strip(),
                            "target": target, "anchor": frag,
                        })

    from collections import deque
    reachable: set[str] = set()
    for root in entry:
        q = deque([root])
        reachable.add(root)
        while q:
            cur = q.popleft()
            for nxt in outbound.get(cur, []):
                if nxt not in reachable and nxt in md_set:
                    reachable.add(nxt)
                    q.append(nxt)

    # Active = KEEP_CANONICAL + KEEP_REFERENCE when inventory present; else non-Archive
    if classifications:
        active_set = set(active_canonical) | set(active_reference)
        reachable_active = sorted(p for p in active_set if p in reachable)
        unreachable_active = sorted(p for p in active_set if p not in reachable and p in md_set)
    else:
        active_set = {p for p in md_files if not p.startswith("Docs/Archive/")}
        reachable_active = sorted(p for p in active_set if p in reachable)
        unreachable_active = sorted(p for p in active_set if p not in reachable)

    # Byte-identical md duplicates
    hashes: dict[str, list[str]] = defaultdict(list)
    for rel in md_files:
        p = ROOT / rel
        if p.is_file():
            hashes[sha256_file(p)].append(rel)
    md_dups = [
        {"sha256": h[:16], "paths": sorted(ps)}
        for h, ps in hashes.items() if len(ps) > 1
    ]

    # Version/platform stale candidates (heuristic)
    stale_pat = re.compile(
        r"\b(iOS\s*1[0-3]|Swift\s*5\.|Xcode\s*1[0-4]|v0\.1\.|watchOS\s*[1-6])\b",
        re.I,
    )
    stale_docs: list[dict[str, Any]] = []
    for rel in md_files:
        if rel.startswith("Docs/Archive/"):
            continue
        text = contents.get(rel, "")
        m = stale_pat.search(text)
        if m:
            stale_docs.append({
                "path": rel,
                "evidence": f"Matched version/platform token: {m.group(0)!r}",
                "confidence": "low",
                "why_manual_review": "Token may be historical context or still accurate; not auto-stale",
            })

    # Documentation samples: ReadmeSamples coverage is the verified surface
    readme_samples = ROOT / "Examples/ReadmeSamples/README.md"
    verified_samples_note = (
        "Executable README samples verified via Examples/ReadmeSamples + Scripts/verify-readme-samples.sh; "
        "not a full fence audit of Docs/"
    )
    tested_examples = {
        "precision": "partial",
        "note": verified_samples_note,
        "harness_present": readme_samples.is_file(),
    }

    # Code fences count (approximate untested surface)
    fence_re = re.compile(r"^```(?:swift|c|bash|sh|json)?\s*$", re.M)
    fence_files = 0
    fence_blocks = 0
    for rel, text in contents.items():
        if rel.startswith("Docs/Archive/"):
            continue
        blocks = len(fence_re.findall(text))
        if blocks:
            fence_files += 1
            fence_blocks += blocks

    review: list[dict[str, Any]] = []
    for p in unreachable_active[:25]:
        review.append({
            "path": p,
            "kind": "unreachable_active_doc",
            "evidence": "Classified active (or non-archive) but not reachable from primary entry-point BFS",
            "confidence": "medium",
            "why_manual_review": "May be intentionally internal; or needs index link",
        })
    for p in delete_cand:
        review.append({
            "path": p,
            "kind": "inventory_delete_candidate",
            "evidence": classifications.get(p, {}).get("evidence", "inventory DELETE_CANDIDATE"),
            "confidence": "medium",
            "why_manual_review": "Inventory recommendation only — not a deletion warrant",
        })
    for d in md_dups[:10]:
        review.append({
            "path": d["paths"][0],
            "kind": "duplicate_markdown",
            "evidence": f"Byte-identical group: {', '.join(d['paths'])}",
            "confidence": "high",
            "why_manual_review": "Confirm canonical path before removing copies",
        })
    for s in stale_docs[:15]:
        review.append({**s, "kind": "version_platform_token"})

    # Superseded: MERGE with destination, or ARCHIVE with destination
    superseded = []
    for p, v in classifications.items():
        if v["recommendation"] in {"MERGE", "ARCHIVE"} and v["canonical_destination"].strip() not in {"", "—", "-"}:
            superseded.append({
                "path": p,
                "recommendation": v["recommendation"],
                "canonical_destination": v["canonical_destination"],
            })

    return {
        "precision_notes": {
            "inventory_classifications": (
                "from Docs/Audit/DOCUMENTATION_INVENTORY_2026_07.md"
                + (" (on disk; not git-tracked yet)" if inventory_used and not inventory_tracked else "")
                if inventory_used else "unavailable — inventory file missing"
            ),
            "reachability": "exact for markdown link BFS from primary entry points",
            "broken_links": "exact for local file targets; anchors approximate (heading/HTML id)",
            "code_fences": "approximate fence count; not equal to untested samples",
        },
        "inventory_used": inventory_used,
        "inventory_tracked": inventory_tracked,
        "recommendation_counts": dict(rec_counts),
        "active_canonical_count": len(active_canonical),
        "active_reference_count": len(active_reference),
        "archive_recommendation_count": len(archive_rec),
        "merge_recommendation_count": len(merge_rec),
        "delete_candidate_count": len(delete_cand),
        "review_required_count": len(review_rec),
        "docs_archive_directory_markdown_files": len(archive_dir),
        "generated_doc_candidates": generated,
        "markdown_files_tracked": len(md_files),
        "reachable_from_primary_entry_points": len(reachable),
        "reachable_active_docs": len(reachable_active),
        "unreachable_active_docs": len(unreachable_active),
        "unreachable_active_sample": unreachable_active[:40],
        "broken_local_file_links": len(broken_files),
        "broken_anchors": len(broken_anchors),
        "broken_file_sample": broken_files[:30],
        "broken_anchor_sample": broken_anchors[:20],
        "byte_identical_markdown_groups": md_dups,
        "superseded_with_explicit_destination": superseded[:40],
        "version_platform_stale_candidates": stale_docs[:30],
        "code_fence_blocks_non_archive": fence_blocks,
        "files_with_code_fences_non_archive": fence_files,
        "documentation_examples": tested_examples,
        "why_docs_bucket_exceeds_markdown": (
            "Docs bucket = all files under Docs/ (any extension) plus every tracked *.md "
            "anywhere. Markdown count is *.md only. Non-Markdown under Docs/ (txt, json, "
            "scripts, exports) and double-counting rules explain the gap."
        ),
        "review_candidates": review,
    }


def load_committed_json() -> dict[str, Any] | None:
    """Previous snapshot from HEAD only (never the working tree)."""
    try:
        raw = subprocess.check_output(
            ["git", "show", f"HEAD:{JSON_REL.as_posix()}"],
            cwd=ROOT,
            stderr=subprocess.DEVNULL,
        )
        return json.loads(raw.decode("utf-8"))
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return None


def diff_snapshots(old: dict[str, Any] | None, new: dict[str, Any]) -> dict[str, Any]:
    if not old:
        return {"available": False, "note": "No previous committed snapshot"}
    def g(d, *keys, default=None):
        cur = d
        for k in keys:
            if not isinstance(cur, dict) or k not in cur:
                return default
            cur = cur[k]
        return cur

    pairs = [
        ("source_lines", ("size", "source_lines")),
        ("test_lines", ("size", "test_lines")),
        ("docs_bucket_lines", ("size", "docs_bucket_lines")),
        ("markdown_files", ("size", "markdown_files")),
        ("xctest_func_test_declarations", ("tests", "xctest_func_test_declarations")),
        ("runner_discovered_count", ("tests", "runner_discovery", "discovered_count")),
        ("reachable_active_docs", ("docs", "reachable_active_docs")),
        ("unreachable_active_docs", ("docs", "unreachable_active_docs")),
        ("broken_local_file_links", ("docs", "broken_local_file_links")),
        ("broken_anchors", ("docs", "broken_anchors")),
    ]
    changes = []
    for label, keys in pairs:
        a, b = g(old, *keys), g(new, *keys)
        if a is None and b is None:
            continue
        if a != b:
            changes.append({"metric": label, "before": a, "after": b, "delta": (b - a) if isinstance(a, int) and isinstance(b, int) else None})
    return {
        "available": True,
        "previous_commit": g(old, "meta", "commit"),
        "changes": changes,
    }


def build_report() -> dict[str, Any]:
    tracked = run_git_ls_files()
    size = collect_size(tracked)
    text_index = size.pop("_text_index")
    decls = collect_swift_decls(text_index)
    tests = collect_tests(tracked, text_index)
    docs = collect_docs(tracked)

    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip()
    cdate = subprocess.check_output(
        ["git", "show", "-s", "--format=%cI", "HEAD"], cwd=ROOT
    ).decode().strip()
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    report = {
        "meta": {
            "generated_at_utc": generated_at,
            "commit": sha,
            "commit_date": cdate,
            "generator": "Scripts/generate_repository_metrics.py",
            "inventory_source": "git ls-files only",
        },
        "bucket_definitions": {
            "text_files": "Tracked paths that exist on disk and are not binary (extension denylist + NUL check)",
            "source": "Text files outside test trees, Docs/, *.md, Examples/, Scripts/, and noise prefixes",
            "tests": "Text files under Tests/, BlazeDBTests/, BlazeDBIntegrationTests/, BlazeDBCLITests/, BlazeDBVisualizerTests/, BlazeDBExtraTests/, BlazeDBTests_SPM/",
            "docs_bucket": "All files under Docs/ plus every tracked *.md/*.markdown anywhere (explains Docs > Markdown)",
            "markdown": "Every tracked *.md / *.markdown regardless of directory",
            "archive": "Files under Docs/Archive/",
            "noise": ".build/, DerivedData/, Vendor/, vendor/, Carthage/, node_modules/",
            "curated_subsystems": {
                "precision": "curated — maintained classification, not filesystem-derived",
                "subsystems": CURATED_SUBSYSTEMS,
                "note": "Used for human-facing scale narrative only; not counted by scanning directories",
            },
        },
        "size": size,
        "swift_declarations": decls,
        "tests": tests,
        "docs": docs,
        "ci_lane_coverage": {
            "precision": "exact for static mapping; not a live Actions query",
            "targets": tests["spm_targets"],
            "android": "PR gate: cross-compile + KMM emulator smoke — no SPM XCTest tier execution",
            "macos": "PR Tier0+Tier1; nightly Tier2; weekly Tier3/Heavy/Perf/Destructive",
            "linux": "PR Tier0+CLITests; nightly Tier1+Tier2; weekly Extended+Heavy(+Perf)",
        },
        "methodology_limitations": [
            "Named XCTest methods ≠ executed cases (parameterization, skips, filters).",
            "swift test list may undercount when BLAZEDB_TEST_SCOPE=tier0 or .build is cold/stale.",
            "Documentation inventory classifications are used when the inventory file is present; they are human/agent judgments, not proofs of obsolescence.",
            "Old regression/compatibility tests are never auto-labeled obsolete.",
            "Curated subsystem list is architectural narrative, not a derived metric.",
            "Unreferenced-fixture detection is basename heuristic only.",
        ],
    }
    prev = load_committed_json()
    report["changes_since_previous_snapshot"] = diff_snapshots(prev, report)
    return report


def render_markdown(report: dict[str, Any]) -> str:
    m = report["meta"]
    s = report["size"]
    t = report["tests"]
    d = report["docs"]
    decl = report["swift_declarations"]
    ch = report["changes_since_previous_snapshot"]
    lines: list[str] = []
    A = lines.append

    A("# BlazeDB Repository Metrics")
    A("")
    A("> **Generated file.** Do not edit by hand.")
    A("> Regenerate with `./Scripts/repo-metrics.sh`.")
    A("> Machine-readable source of truth: `.metrics/repository-metrics.json`.")
    A("> Inventory source: `git ls-files` only (no `.build`, DerivedData, or untracked paths).")
    A("")
    A("| Field | Value |")
    A("|-------|-------|")
    A(f"| Generated at (UTC) | `{m['generated_at_utc']}` |")
    A(f"| Commit | `{m['commit']}` |")
    A(f"| Commit date | `{m['commit_date']}` |")
    A("")
    A("## 1. Bucket definitions")
    A("")
    for k, v in report["bucket_definitions"].items():
        if k == "curated_subsystems":
            A(f"- **{k}** ({v['precision']}): {', '.join(v['subsystems'])}. {v['note']}")
        else:
            A(f"- **{k}**: {v}")
    A("")
    A("### Why Docs lines can exceed Markdown lines")
    A("")
    A(d["why_docs_bucket_exceeds_markdown"])
    A("")
    A("## 2. Repository size")
    A("")
    A("| Metric | Files | Lines | Precision |")
    A("|--------|------:|------:|-----------|")
    A(f"| Tracked paths | {s['tracked_paths']} | — | exact |")
    A(f"| Tracked text | {s['tracked_text_files']} | {s['tracked_text_lines']} | exact |")
    A(f"| Swift | {s['swift_files']} | {s['swift_lines']} | exact |")
    A(f"| Markdown | {s['markdown_files']} | {s['markdown_lines']} | exact |")
    A(f"| Source bucket | {s['source_files']} | {s['source_lines']} | exact |")
    A(f"| Tests bucket | {s['test_files']} | {s['test_lines']} | exact |")
    A(f"| Docs bucket | {s['docs_bucket_files']} | {s['docs_bucket_lines']} | exact |")
    A(f"| `BlazeDB/` engine tree | {s['blazedb_engine_files']} | {s['blazedb_engine_lines']} | exact |")
    A(f"| `Tests/` prefix only | {s['tests_prefix_files']} | {s['tests_prefix_lines']} | exact |")
    A(f"| `Docs/` prefix only | {s['docs_prefix_files']} | {s['docs_prefix_lines']} | exact |")
    A(f"| `Docs/Archive/` | {s['archive_docs_files']} | {s['archive_docs_lines']} | exact |")
    A("")
    A(f"**Test-to-source line ratio:** {s['test_to_source_line_ratio']}  ")
    A(f"**SwiftPM products / targets:** {s['package_products']} / {s['package_targets']} (exact package manifest counts; products ≠ curated subsystems)")
    A("")
    A("### Swift declarations (approximate)")
    A("")
    A("| Declaration | Count |")
    A("|-------------|------:|")
    A(f"| class | {decl['class']} |")
    A(f"| struct | {decl['struct']} |")
    A(f"| protocol | {decl['protocol']} |")
    A(f"| enum | {decl['enum']} |")
    A("")
    A("## 3. Test execution and discovery")
    A("")
    A("| Metric | Value | Precision |")
    A("|--------|------:|-----------|")
    A(f"| Test-tree Swift files | {t['test_tree_swift_files']} | exact |")
    A(f"| XCTest `func test…` declarations | {t['xctest_func_test_declarations']} | approximate |")
    A(f"| Swift Testing `@Test` declarations | {t['swift_testing_at_test_declarations']} | approximate |")
    A(f"| Files with ≥1 test declaration | {t['files_with_at_least_one_test_declaration']} | approximate |")
    A(f"| Helper/fixture Swift without test decl | {t['helper_or_fixture_swift_files_without_test_decl']} | approximate |")
    A(f"| XCTSkip occurrences | {t['xctskip_occurrence_count']} | approximate |")
    A(f"| Files with `#if os(` | {len(t['files_with_os_conditional'])} | approximate |")
    A(f"| Wired SPM test Swift files | {t['wired_spm_test_swift_files']} | exact path membership |")
    A(f"| Orphan on-disk test Swift (not in Package test paths) | {t['orphan_on_disk_test_swift_files']} | exact |")
    rd = t["runner_discovery"]
    A(f"| Runner-discovered tests (`swift test list`) | {rd.get('discovered_count', '—')} | {rd.get('precision')} ({rd.get('status')}) |")
    A("")
    if rd.get("note"):
        A(f"_Runner note:_ {rd['note']}")
        A("")
    A("**Important:** `func test…` counts are **not** executed-test counts. Skips, filters, parameterization, and platform conditionals change what CI runs.")
    A("")
    A("## 4. Test review candidates")
    A("")
    A("Candidates only — **not** obsolete. Compatibility and regression tests may remain valuable indefinitely.")
    A("")
    A("| Path | Kind | Confidence | Evidence |")
    A("|------|------|------------|----------|")
    for c in t["review_candidates"][:40]:
        A(f"| `{c['path']}` | {c['kind']} | {c['confidence']} | {c['evidence'][:120].replace('|','/')} |")
    if not t["review_candidates"]:
        A("| — | — | — | none |")
    A("")
    A("## 5. Documentation activity and reachability")
    A("")
    A("| Metric | Value | Precision |")
    A("|--------|------:|-----------|")
    A(f"| Tracked Markdown files | {d['markdown_files_tracked']} | exact |")
    A(f"| Inventory used | {d['inventory_used']} | — |")
    A(f"| KEEP_CANONICAL | {d['active_canonical_count']} | inventory |")
    A(f"| KEEP_REFERENCE | {d['active_reference_count']} | inventory |")
    A(f"| ARCHIVE (recommendation) | {d['archive_recommendation_count']} | inventory |")
    A(f"| MERGE | {d['merge_recommendation_count']} | inventory |")
    A(f"| DELETE_CANDIDATE | {d['delete_candidate_count']} | inventory |")
    A(f"| REVIEW_REQUIRED | {d['review_required_count']} | inventory |")
    A(f"| Docs/Archive Markdown files | {d['docs_archive_directory_markdown_files']} | exact |")
    A(f"| Reachable from primary entry points | {d['reachable_from_primary_entry_points']} | exact BFS |")
    A(f"| Reachable active docs | {d['reachable_active_docs']} | mixed |")
    A(f"| Unreachable active docs | {d['unreachable_active_docs']} | mixed |")
    A(f"| Broken local file links | {d['broken_local_file_links']} | exact |")
    A(f"| Broken anchors | {d['broken_anchors']} | approximate |")
    A(f"| Code fence blocks (non-archive) | {d['code_fence_blocks_non_archive']} | approximate |")
    A("")
    A(f"_Documentation examples:_ {d['documentation_examples']['note']}")
    A("")
    A("## 6. Documentation review candidates")
    A("")
    A("| Path | Kind | Confidence | Evidence |")
    A("|------|------|------------|----------|")
    for c in d["review_candidates"][:40]:
        A(f"| `{c['path']}` | {c.get('kind','')} | {c.get('confidence','')} | {str(c.get('evidence',''))[:120].replace('|','/')} |")
    if not d["review_candidates"]:
        A("| — | — | — | none |")
    A("")
    A("## 7. CI lane coverage")
    A("")
    A("| Target | Path | Lanes | In normal lane? |")
    A("|--------|------|-------|-----------------|")
    for tgt in report["ci_lane_coverage"]["targets"]:
        lanes = ", ".join(tgt["lanes"]) if tgt["lanes"] else "_(none)_"
        A(f"| `{tgt['target']}` | `{tgt['path']}` | {lanes} | {'yes' if tgt['exercised_by_normal_lane'] else '**no**'} |")
    A("")
    A(f"- macOS: {report['ci_lane_coverage']['macos']}")
    A(f"- Linux: {report['ci_lane_coverage']['linux']}")
    A(f"- Android: {report['ci_lane_coverage']['android']}")
    A("")
    A("## 8. Changes since previous snapshot")
    A("")
    if not ch.get("available"):
        A(ch.get("note", "No previous snapshot."))
    else:
        A(f"Previous commit: `{ch.get('previous_commit')}`")
        A("")
        A("| Metric | Before | After | Delta |")
        A("|--------|-------:|------:|------:|")
        for c in ch.get("changes", []):
            A(f"| {c['metric']} | {c['before']} | {c['after']} | {c['delta']} |")
        if not ch.get("changes"):
            A("| — | — | — | no numeric deltas |")
    A("")
    A("## 9. Methodology limitations")
    A("")
    for item in report["methodology_limitations"]:
        A(f"- {item}")
    A("")
    A("## Files by extension")
    A("")
    A("| Extension | Files | Lines |")
    A("|-----------|------:|------:|")
    for row in s["by_extension"]:
        A(f"| `{row['extension']}` | {row['files']} | {row['lines']} |")
    A("")
    A("## Top 20 directories by file count")
    A("")
    A("| Directory | Files | Lines |")
    A("|-----------|------:|------:|")
    for row in s["top_dirs_by_files"]:
        A(f"| `{row['directory']}` | {row['files']} | {row['lines']} |")
    A("")
    A("## Top 20 directories by line count")
    A("")
    A("| Directory | Lines | Files |")
    A("|-----------|------:|------:|")
    for row in s["top_dirs_by_lines"]:
        A(f"| `{row['directory']}` | {row['lines']} | {row['files']} |")
    A("")
    A("---")
    A("")
    A("*End of generated metrics.*")
    A("")
    return "\n".join(lines)


def canonicalize_for_compare(report: dict[str, Any]) -> str:
    """Stable JSON for --check (drop time, deltas, and build-graph discovery counts)."""
    data = json.loads(json.dumps(report))
    if "meta" in data:
        data["meta"].pop("generated_at_utc", None)
    data.pop("changes_since_previous_snapshot", None)
    tests = data.get("tests") or {}
    rd = tests.get("runner_discovery") or {}
    if rd:
        tests["runner_discovery"] = {
            "precision": rd.get("precision"),
            "status": rd.get("status"),
            "note": rd.get("note"),
        }
        data["tests"] = tests
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def write_outputs(report: dict[str, Any]) -> None:
    (ROOT / ".metrics").mkdir(parents=True, exist_ok=True)
    json_path = ROOT / JSON_REL
    md_path = ROOT / MD_REL
    md_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    md_path.write_text(render_markdown(report), encoding="utf-8")
    print(f"Wrote {JSON_REL}")
    print(f"Wrote {MD_REL}")
    s = report["size"]
    print(
        f"source={s['source_lines']} test={s['test_lines']} docs={s['docs_bucket_lines']} "
        f"md_files={s['markdown_files']} xctest_funcs={report['tests']['xctest_func_test_declarations']}"
    )


def main(argv: list[str]) -> int:
    os.chdir(ROOT)
    mode = "write"
    if "--check" in argv:
        mode = "check"
    elif "--diff" in argv:
        mode = "diff"

    report = build_report()

    if mode == "diff":
        prev = load_committed_json()
        ch = diff_snapshots(prev, report)
        print(json.dumps(ch, indent=2))
        # Also print compact size now
        s = report["size"]
        print(
            f"\ncurrent: source={s['source_lines']} tests={s['test_lines']} "
            f"docs={s['docs_bucket_lines']} md={s['markdown_files']} "
            f"xctest={report['tests']['xctest_func_test_declarations']} "
            f"discovered={report['tests']['runner_discovery'].get('discovered_count')}"
        )
        return 0

    if mode == "check":
        json_path = ROOT / JSON_REL
        md_path = ROOT / MD_REL
        if not json_path.is_file() or not md_path.is_file():
            print(f"error: missing {JSON_REL} or {MD_REL}; run without --check", file=sys.stderr)
            return 1
        committed = json.loads(json_path.read_text(encoding="utf-8"))
        # Compare ignoring generated_at
        if canonicalize_for_compare(committed) != canonicalize_for_compare(report):
            print(f"error: {JSON_REL} is stale relative to HEAD working tree", file=sys.stderr)
            print("run: ./Scripts/repo-metrics.sh", file=sys.stderr)
            return 1
        # Markdown must match render of committed JSON (ignore generated_at in regen)
        # Re-render from freshly built report and compare MD without generated-at line
        fresh_md = render_markdown(report)
        old_md = md_path.read_text(encoding="utf-8")

        def strip_volatile_md(text: str) -> str:
            out = []
            skip = False
            for ln in text.splitlines():
                if ln.startswith("| Generated at (UTC) |"):
                    continue
                if ln.startswith("## 8. Changes since previous snapshot"):
                    skip = True
                    continue
                if skip and ln.startswith("## "):
                    skip = False
                if skip:
                    continue
                # Runner discovery count is build-graph dependent.
                if ln.startswith("| Runner-discovered tests"):
                    continue
                if ln.startswith("_Runner note:_"):
                    continue
                out.append(ln)
            return "\n".join(out)

        if strip_volatile_md(old_md) != strip_volatile_md(fresh_md):
            print(f"error: {MD_REL} does not match regenerated Markdown", file=sys.stderr)
            return 1
        print(f"OK: metrics snapshots match working tree for {report['meta']['commit']}")
        return 0

    write_outputs(report)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
