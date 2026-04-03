#!/usr/bin/env python3
"""Convert `override func setUp() { ... super.setUp() ... }` to setUpWithError throws."""

import re
import sys
from pathlib import Path

SETUP_RE = re.compile(r"^(\s*)override func setUp\(\) \{\s*$")


def convert_file(text: str) -> str:
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = SETUP_RE.match(line)
        if m and "async" not in line:
            indent = m.group(1)
            new_line = f"{indent}override func setUpWithError() throws {{\n"
            out.append(new_line)
            depth = new_line.count("{") - new_line.count("}")
            i += 1
            replaced = False
            while i < len(lines) and depth > 0:
                l = lines[i]
                if not replaced and "super.setUp()" in l and "setUpWithError" not in l:
                    l = l.replace("super.setUp()", "try super.setUpWithError()", 1)
                    replaced = True
                depth += l.count("{") - l.count("}")
                out.append(l)
                i += 1
            continue
        out.append(line)
        i += 1
    return "".join(out)


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    paths = [Path(p) for p in sys.argv[1:]] if len(sys.argv) > 1 else list(
        (root / "BlazeDBTests" / "Tier1Core").rglob("*.swift")
    )
    for p in paths:
        raw = p.read_text(encoding="utf-8")
        new = convert_file(raw)
        if new != raw:
            p.write_text(new, encoding="utf-8")
            print(p.relative_to(root))


if __name__ == "__main__":
    main()
