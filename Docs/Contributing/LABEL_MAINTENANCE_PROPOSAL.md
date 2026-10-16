# Issue label maintenance (proposal)

**Not executed in this branch** — requires GitHub issue edits by a maintainer.

## Problem

~145 open issues; many carry **`good first issue`** while [ISSUE_GUIDE.md](ISSUE_GUIDE.md) restricts GFI to documentation and safe tooling. Mislabeled issues waste contributor time.

## Proposed actions

1. **Audit** open `good first issue` issues; remove label where work touches WAL, crypto, Android bridge runtime, or concurrency without maintainer pairing.
2. **Keep** label on issues listed in [STARTER_TASKS.md](STARTER_TASKS.md) and doc-only rows in [ISSUE_CODE_INDEX.md](ISSUE_CODE_INDEX.md).
3. **Add** `help wanted` to 3–5 maintainer-backed issues when scope is frozen (optional; do not promise review SLAs in docs).
4. **Refresh** `ISSUE_CODE_INDEX.md` tip SHA and the “help wanted: none open” line after each gardening pass (verify with `gh issue list --label "help wanted"`).

## Example commands (maintainer)

```bash
gh issue list --state open --label "good first issue" --limit 100
gh issue edit <num> --remove-label "good first issue"
gh issue edit <num> --add-label "help wanted"
```

## Success

New contributors landing from README [STARTER_TASKS.md](STARTER_TASKS.md) complete a doc PR without hitting storage-engine blockers.
