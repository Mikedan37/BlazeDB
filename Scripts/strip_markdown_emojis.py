#!/usr/bin/env python3
"""
Remove emoji and emoji-like symbols from Markdown files for professional tone.
Run from repo root: python3 Scripts/strip_markdown_emojis.py [paths...]
Default: Docs/ CONTRIBUTING.md BlazeDB/BlazeDB.docc/BlazeDB.md Examples/SYNC_EXAMPLES_INDEX.md
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# Explicit symbols often used as list/heading markers (not full Unicode emoji sweep)
SYMBOL_STRIPS = str.maketrans(
    {
        "\u2705": "",  # ✅
        "\u274c": "",  # ❌
        "\u23f3": "",  # ⏳ hourglass
        "\u26a0": "",  # ⚠ (warning sign; FE0F may follow)
        "\u2744": "",  # ❄
        "\u2728": "",  # ✨
        "\u270f": "",  # ✏
    }
)

# Variation selector-16 (makes some chars emoji-style)
VS16 = "\ufe0f"

# Primary emoji plane (most pictographic emoji used in prose); avoid sweeping 2600–27FF
# so we do not strip typographic symbols used in technical text.
EMOJI_RE = re.compile("[\U0001f300-\U0001faff]", re.UNICODE)


def clean_line(line: str) -> str:
    s = line.translate(SYMBOL_STRIPS)
    s = s.replace(VS16, "")
    s = EMOJI_RE.sub("", s)
    # Tidy spacing after removals
    s = re.sub(r" {2,}", " ", s)
    s = re.sub(r"^[ \t]+([-*])", r"\1", s)  # odd indent before bullet
    return s.rstrip() + ("\n" if line.endswith("\n") else "")


def process_file(path: Path) -> bool:
    raw = path.read_text(encoding="utf-8")
    lines = raw.splitlines(keepends=True)
    out = "".join(clean_line(L) if L else L for L in lines)
    if out != raw:
        path.write_text(out, encoding="utf-8")
        return True
    return False


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    if len(sys.argv) > 1:
        roots = [(repo / Path(p)).resolve() for p in sys.argv[1:]]
    else:
        roots = [
            repo / "Docs",
            repo / "CONTRIBUTING.md",
            repo / "BlazeDB" / "BlazeDB.docc" / "BlazeDB.md",
            repo / "Examples" / "SYNC_EXAMPLES_INDEX.md",
        ]
    changed: list[Path] = []
    for root in roots:
        if not root.exists():
            continue
        if root.is_file():
            if root.suffix.lower() == ".md" and process_file(root):
                changed.append(root)
            continue
        for md in sorted(root.rglob("*.md")):
            if process_file(md):
                changed.append(md)
    for p in changed:
        try:
            rel = p.relative_to(repo)
        except ValueError:
            rel = p
        print(f"updated: {rel}")
    print(f"Total files updated: {len(changed)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
