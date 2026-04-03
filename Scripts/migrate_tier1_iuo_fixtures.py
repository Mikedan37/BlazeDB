#!/usr/bin/env python3
"""
Convert Tier1Core test IUO fixtures (!) to optionals (?) and requireFixture(...) for access.

  python3 Scripts/migrate_tier1_iuo_fixtures.py
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TIER1 = ROOT / "BlazeDBTests" / "Tier1Core"

URL_NAMES = frozenset(
    {
        "tempURL",
        "tempDir",
        "dbURL",
        "usersURL",
        "tempURL1",
        "tempURL2",
        "tempFile",
        "tempDBURL",
        "tempDumpURL",
        "originalDBPath",
        "dumpPath",
        "restoredDBPath",
        "metaURL",
    }
)

DB_NAMES = frozenset(
    {
        "db",
        "client",
        "db1",
        "db2",
        "usersDB",
        "bugsDB",
        "originalDB",
    }
)


def replace_url_decl(text: str) -> str:
    for name in URL_NAMES:
        text = re.sub(
            rf"\bprivate\s+var\s+{re.escape(name)}\s*:\s*URL!",
            f"private var {name}: URL?",
            text,
        )
        text = re.sub(
            rf"\bvar\s+{re.escape(name)}\s*:\s*URL!",
            f"private var {name}: URL?",
            text,
        )
    return text


def replace_db_decl(text: str) -> str:
    for name in DB_NAMES:
        text = re.sub(
            rf"\bprivate\s+var\s+{re.escape(name)}\s*:\s*BlazeDBClient!",
            f"private var {name}: BlazeDBClient?",
            text,
        )
        text = re.sub(
            rf"\bvar\s+{re.escape(name)}\s*:\s*BlazeDBClient!",
            f"private var {name}: BlazeDBClient?",
            text,
        )
    return text


def patch_url_access(text: str) -> str:
    for name in sorted(URL_NAMES, key=len, reverse=True):
        n = re.escape(name)
        # Avoid rewriting when another fixture helper already qualifies the name (e.g. self is rare).
        pfx = rf"(?<!\.)"
        text = re.sub(
            rf"{pfx}\b{n}\.deletingPathExtension\(\)",
            f"try requireFixture({name}).deletingPathExtension()",
            text,
        )
        text = re.sub(
            rf"{pfx}\b{n}\.deletingLastPathComponent\(\)",
            f"try requireFixture({name}).deletingLastPathComponent()",
            text,
        )
        text = re.sub(rf"{pfx}\b{n}\.lastPathComponent\b", f"try requireFixture({name}).lastPathComponent", text)
        text = re.sub(rf"{pfx}\b{n}\.path\b", f"try requireFixture({name}).path", text)
        text = re.sub(rf"\bat:\s*{n}\)", f"at: try requireFixture({name}))", text)
        text = re.sub(rf"\bto:\s*{n}\)", f"to: try requireFixture({name}))", text)
        text = re.sub(rf"\bfileURL:\s*{n}\s*,", f"fileURL: try requireFixture({name}),", text)
        text = re.sub(rf"\bcontentsOf:\s*{n}\)", f"contentsOf: try requireFixture({name}))", text)
        text = re.sub(rf"\bforWritingTo:\s*{n}\)", f"forWritingTo: try requireFixture({name}))", text)
        text = re.sub(rf"\bforUpdating:\s*{n}\)", f"forUpdating: try requireFixture({name}))", text)
    return text


def patch_db_access(text: str) -> str:
    for name in sorted(DB_NAMES, key=len, reverse=True):
        n = re.escape(name)
        pfx = rf"(?<!\.)"
        # Avoid churn on optional chaining
        text = re.sub(rf"\btry\s+{n}\.", f"try requireFixture({name}).", text)
        text = re.sub(rf"{pfx}\b{n}\.", f"try requireFixture({name}).", text)
    while "try try requireFixture" in text:
        text = text.replace("try try requireFixture", "try requireFixture")
    return text


def process_file(path: Path) -> bool:
    raw = path.read_text(encoding="utf-8")
    if "XCTestCase" not in raw:
        return False
    if "URL!" not in raw and "BlazeDBClient!" not in raw:
        return False

    text = raw
    text = replace_url_decl(text)
    text = replace_db_decl(text)
    text = patch_url_access(text)
    text = patch_db_access(text)

    if text != raw:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def main() -> None:
    changed = 0
    for path in sorted(TIER1.rglob("*.swift")):
        if process_file(path):
            print("updated:", path.relative_to(ROOT))
            changed += 1
    print(f"done, {changed} files changed")


if __name__ == "__main__":
    main()
