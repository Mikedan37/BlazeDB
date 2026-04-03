#!/usr/bin/env python3
"""
Optional fixtures + requireFixture() for Tier1 tests with a single XCTestCase and one BlazeDBClient `db`.
Skips multi-DB files and known specials; safe to re-run.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TIER1 = REPO / "BlazeDBTests" / "Tier1Core"

SKIP = frozenset(
    {
        "EncryptionSecurityTests.swift",
        "EncryptionRoundTripVerificationTests.swift",
        "ConcurrentJoinTests.swift",
        "BlazeTransactionTests.swift",
        "XCTestCase+FixtureRequire.swift",
        "LinuxXCTestMetricShim.swift",
        "QueryCacheTests.swift",
        "DataSeedingTests.swift",
        "BlazePaginationTests.swift",
        # Multi-client or multi-class (migrate by hand)
        "DXBugDiagnosticTests.swift",
        "BlazeJoinTests.swift",
        "ForeignKeyTests.swift",
        "SubqueryTests.swift",
        "DistributedSecurityTests.swift",
        "DistributedGCTests.swift",
        "DistributedGCPerformanceTests.swift",
        "GoldenPathIntegrationTests.swift",
        "BlazeDBTests.swift",
        "BlazeDBMemoryTests.swift",
        "BlazeDBPersistenceTests.swift",
        "CrashRecoveryTests.swift",
        "GraphQueryAPITests.swift",
    }
)


def should_process(name: str, text: str) -> bool:
    if name in SKIP:
        return False
    if text.count("final class ") != 1:
        return False
    if re.search(r"var (usersDB|bugsDB|commentsDB|db1|db2)\s*:\s*BlazeDBClient!", text):
        return False
    if "var db: BlazeDBClient!" not in text and "private var db: BlazeDBClient!" not in text:
        return False
    return True


def replace_properties(text: str) -> str:
    text = re.sub(r"\bvar tempURL: URL!", "var tempURL: URL?", text)
    text = re.sub(r"\bvar dbURL: URL!", "var dbURL: URL?", text)
    text = re.sub(r"\bprivate var dbURL: URL!", "private var dbURL: URL?", text)
    text = re.sub(r"\bvar db: BlazeDBClient!", "var db: BlazeDBClient?", text)
    text = re.sub(r"\bprivate var db: BlazeDBClient!", "private var db: BlazeDBClient?", text)
    return text.replace("try! BlazeDBClient(", "try BlazeDBClient(")


def upgrade_sync_setup(text: str) -> str:
    """setUp() { super.setUp() -> setUpWithError() throws { try super.setUpWithError()"""
    return re.sub(
        r"override func setUp\(\) \{\s*\n(\s*)super\.setUp\(\)",
        r"override func setUpWithError() throws {\n\1try super.setUpWithError()",
        text,
        count=1,
    )


def fix_tempurl_then_db(text: str) -> str:
    """tempURL = <rhs> ... db = try BlazeDBClient(..., fileURL: tempURL -> local url."""

    def repl(m: str) -> str:
        indent, assign_line, mid, db_line = m.group(1), m.group(2), m.group(3), m.group(4)
        if "fixtureURL" in assign_line or "fixtureURL" in db_line:
            return m.group(0)
        rhs = assign_line.split("=", 1)[1].strip()
        new_a = f"{indent}let fixtureURL = {rhs}\n{indent}tempURL = fixtureURL"
        new_db = db_line.replace("fileURL: tempURL", "fileURL: fixtureURL")
        return f"\n{new_a}{mid}{new_db}"

    text2 = re.sub(
        r"\n([ \t]+)(tempURL = .+)\n"
        r"([\s\S]*?)"
        r"\n([ \t]+db = try BlazeDBClient\([^\n]*fileURL: tempURL[^\n]*)\n",
        repl,
        text,
        count=1,
    )
    if text2 == text:
        return text

    return text2


def fix_dburl_then_db(text: str) -> str:
    def repl(m: str) -> str:
        indent, assign_line, mid, db_line = m.group(1), m.group(2), m.group(3), m.group(4)
        if "fixtureURL" in assign_line:
            return m.group(0)
        rhs = assign_line.split("=", 1)[1].strip()
        new_a = f"{indent}let fixtureURL = {rhs}\n{indent}dbURL = fixtureURL"
        new_db = db_line.replace("fileURL: dbURL", "fileURL: fixtureURL")
        return f"\n{new_a}{mid}{new_db}"

    text2 = re.sub(
        r"\n([ \t]+)(dbURL = .+)\n"
        r"([\s\S]*?)"
        r"\n([ \t]+db = try BlazeDBClient\([^\n]*fileURL: dbURL[^\n]*)\n",
        repl,
        text,
        count=1,
    )
    return text2 if text2 != text else text


def wrap_teardown_tempurl_removal(text: str) -> str:
    """try? remove(at: tempURL) -> if let tempURL { ... } for simple tearDown."""
    if "if let tempURL" in text or "guard let tempURL" in text:
        return text
    # Only wrap first consecutive removeItem(at: tempURL) lines in tearDown
    lines = text.split("\n")
    out = []
    i = 0
    in_teardown = False
    while i < len(lines):
        line = lines[i]
        if "override func tearDown()" in line or "override func tearDownWithError()" in line:
            in_teardown = True
        if in_teardown and line.strip() == "super.tearDown()":
            in_teardown = False
        out.append(line)
        i += 1
    s = "\n".join(out)
    # Single pattern: after db = nil, try? removeItem at tempURL
    s2 = re.sub(
        r"(\n[ \t]+)(db = nil\n)"
        r"([ \t]+)(try\? FileManager\.default\.removeItem\(at: tempURL\))",
        r"\1\2\3if let tempURL {\n\3    \4\n\3}",
        s,
        count=1,
    )
    if s2 != s:
        # close brace before super.tearDown if we added one block - naive: add } before super.tearDown in tearDown
        s2 = re.sub(
            r"(\n[ \t]+)(if let tempURL \{[^}]+)(\n[ \t]+super\.tearDown\(\))",
            lambda m: m.group(1) + m.group(2) + "\n" + m.group(1).rstrip() + "}" + m.group(3),
            s2,
            count=1,
        )
    return s2 if s2 != s else s


def inject_require_db(text: str) -> str:
    lines = text.split("\n")
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(
            r"^(\s*)func (test[A-Za-z0-9_]+)\([^\)]*\)((?:\s+async)?)((?:\s+throws)?)\s*\{\s*$",
            line,
        )
        if m:
            indent = m.group(1)
            rest = m.group(3) + m.group(4)
            out.append(line)
            if i + 1 < len(lines) and "requireFixture(self.db" in lines[i + 1]:
                i += 1
                out.append(lines[i])
                i += 1
                continue
            if "async" in rest and "throws" not in rest:
                out[-1] = line.replace(" async {", " async throws {")
            elif "throws" not in rest and "async" not in rest:
                out[-1] = line.replace(" {", " throws {")
            out.append(f'{indent}    let db = try requireFixture(self.db, "db should be set in setUp")')
            i += 1
            continue
        out.append(line)
        i += 1
    return "\n".join(out)


def ensure_setup_super(path: Path, text: str) -> str:
    """setUpWithError without super - add try super.setUpWithError() after brace."""
    if "override func setUpWithError()" not in text:
        return text
    if "try super.setUpWithError()" in text:
        return text
    text = re.sub(
        r"(override func setUpWithError\(\) throws \{)\s*\n",
        r"\1\n        try super.setUpWithError()\n",
        text,
        count=1,
    )
    return text


def migrate(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    if not should_process(path.name, text):
        return False
    orig = text
    text = replace_properties(text)
    if "override func setUp() async throws" not in text:
        text = upgrade_sync_setup(text)

    if "var tempURL: URL?" in text:
        text = fix_tempurl_then_db(text)
    if "var dbURL: URL?" in text:
        text = fix_dburl_then_db(text)

    text = ensure_setup_super(path, text)
    text = inject_require_db(text)
    text = wrap_teardown_tempurl_removal(text)

    if text != orig:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def main() -> int:
    changed = []
    for p in sorted(TIER1.rglob("*.swift")):
        if migrate(p):
            changed.append(str(p.relative_to(REPO)))
    for c in changed:
        print(c)
    print(f"Updated {len(changed)} files", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
