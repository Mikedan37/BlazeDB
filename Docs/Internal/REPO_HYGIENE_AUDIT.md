# BlazeDB Repo Hygiene Audit

## 1. Suspected AI / Editor / Cloud Residue

| Path | Why it looks like residue | Severity | Recommended action |
|---|---|---|---|
| `.cursor/` | Editor workspace state and planning artifacts | High | Keep local only via `.gitignore` (already ignored) |
| `.claude/` | AI tooling workspace/worktree state | High | Keep local only via `.gitignore` (already ignored) |
| `.artifacts/` | Generated local build/editor artifacts | High | Keep local only via `.gitignore` (already ignored) |
| `.logs/` | Local machine logs and execution traces | Medium | Keep local only via `.gitignore` (already ignored) |
| `.DS_Store` (repo root, local file present) | macOS Finder metadata, non-product | Medium | Delete locally; keep ignored (already ignored) |
| `Docs/superpowers/specs/2026-03-14-blazedb-oss-cleanup-design.md` | Internal AI/process planning spec, not product docs | High | Move to internal analysis area (applied) |
| `Docs/Internal/Analysis/*.md` | Maintainer analysis artifacts, not onboarding docs | Low | Keep in git but internal-only and de-emphasized publicly |

## 2. Docs Audience Classification

| Path | Audience | Should remain in git? | Should remain linked publicly? |
|---|---|---:|---:|
| `README.md` | Public product | Yes | Yes |
| `Docs/README.md` | Public product/docs navigation | Yes | Yes |
| `Docs/GettingStarted/` | Public product onboarding | Yes | Yes |
| `Docs/API/` | Public API reference | Yes | Yes |
| `Examples/README.md` | Public product usage | Yes | Yes |
| `Docs/Status/DURABILITY_MODE_SUPPORT.md` | Public support-state | Yes | Yes |
| `Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md` | Public caveat/support-state | Yes | Yes |
| `Docs/Status/OPEN_SOURCE_READINESS_CHECKLIST.md` | Public maintainer | Yes | No (not onboarding) |
| `Docs/Testing/` | Public maintainer/contributor | Yes | No (not onboarding) |
| `Docs/Release/` | Public maintainer/release ops | Yes | No (not onboarding) |
| `Docs/Internal/README.md` | Internal maintainer | Yes | Linked only as internal index |
| `Docs/Internal/Analysis/` | Internal analysis | Yes | No (internal-only links) |
| `Docs/Audit/`, `Docs/Meta/`, `Docs/Project/` | Mixed maintainer/internal | Yes | Not from core onboarding paths |
| `.cursor/plans/` (local) | Local-only planning | No | No |

## 3. Recommended Removals from Git

| Path | Reason | Safe to delete? | Should be gitignored? |
|---|---|---:|---:|
| `Docs/superpowers/specs/2026-03-14-blazedb-oss-cleanup-design.md` (old location) | Process-planning artifact in semi-public docs tree | Yes (from old path) | Yes (`Docs/superpowers/`) |
| `.DS_Store` (if ever tracked) | OS metadata noise | Yes | Yes |

Notes:
- No tracked `.cursor/`, `.claude/`, `.artifacts/`, or session/worktree metadata was found.
- `.cursor/plans/...` appears local-only and is already covered by `.cursor/` ignore.

## 4. Recommended Relocations / Demotions

| Current path | Better location | Public link? | Internal link? |
|---|---|---:|---:|
| `Docs/superpowers/specs/2026-03-14-blazedb-oss-cleanup-design.md` | `Docs/Internal/Analysis/2026-03-14-blazedb-oss-cleanup-design.md` | No | Yes |
| `Docs/Internal/Analysis/*.md` | Keep where they are | No | Yes |

Additional demotion guidance (no move applied in this pass):
- Keep `Docs/Status/` focused on product/support state and release readiness.
- Keep deep audit/process material discoverable only from internal indexes.

## 5. AI / Process Trace Findings

| File | Text/pattern | Publicly acceptable? | Action |
|---|---|---:|---|
| `Docs/superpowers/specs/2026-03-14-blazedb-oss-cleanup-design.md` | Explicit multi-phase AI/process design language | No (in prior location) | Moved to internal analysis |
| `Docs/README.md` | "Internal analysis docs", "analysis artifacts" wording | Yes (if kept as audience segmentation) | Keep |
| `Docs/Internal/Analysis/*` | Capability/reconciliation/narrative-analysis labels | Yes (internal docs) | Keep internal-only |

No AI/process markers were found in primary onboarding/public entry docs (`README.md`, `Docs/GettingStarted/README.md`, `Examples/README.md`, `Docs/API/API_REFERENCE.md`) that would materially degrade first impression.

## 6. Gitignore / Local-Only Hygiene

Current strengths:
- `.gitignore` already excludes `.claude/`, `.cursor/`, `.artifacts/`, `.logs/`, `.build/`, `.swiftpm/`, and `.DS_Store`.

Gap found and fixed:
- Added `Docs/superpowers/` to prevent AI planning specs from re-entering tracked docs.

Remaining recommendations:
- Keep broad editor/AI ignore rules at top-level (already done).
- Avoid adding generic `*.plan.md` ignores globally (too risky for legitimate docs).

## 7. Final Keep / Move / Delete Matrix

| Category | Paths | Decision |
|---|---|---|
| Keep public | `README.md`, `Docs/README.md`, `Docs/GettingStarted/`, `Docs/API/`, `Examples/README.md`, security/license/contributing files | Keep and continue to prioritize in indexes |
| Keep maintainer-only | `Docs/Status/*` (release/readiness), `Docs/Testing/`, `Docs/Release/` | Keep in git; avoid top-onboarding prominence |
| Move to internal | `Docs/superpowers/specs/*` | Move under `Docs/Internal/Analysis/` |
| Delete from git | None beyond old moved path in this pass | Conservative cleanup (no broad destructive delete) |
| Ignore going forward | `.cursor/`, `.claude/`, `.artifacts/`, `.logs/`, `.DS_Store`, `Docs/superpowers/` | Enforced via `.gitignore` |

## 8. Changes Applied

1. Moved:
   - `Docs/superpowers/specs/2026-03-14-blazedb-oss-cleanup-design.md` -> `Docs/Internal/Analysis/2026-03-14-blazedb-oss-cleanup-design.md`
2. Updated ignore rules:
   - Added `Docs/superpowers/` to `.gitignore`
3. Updated internal index:
   - Added the moved spec to `Docs/Internal/README.md`

## 9. Verification Results

- `swift build`: PASS
- `./Scripts/verify-readme-quickstart.sh`: PASS
- Notes:
  - Quickstart verification succeeded end-to-end.
  - Existing compiler warning observed in quickstart snapshot build (`retiredCollection` written but never read in `BlazeDB/Storage/VacuumCompaction.swift`); unrelated to hygiene changes.

## 10. Final Recommendation

- Public repo cleanliness: **mostly clean and acceptable for OSS release** after this pass.
- Still-not-for-GitHub candidates: **none high-confidence found as tracked files** beyond the moved `Docs/superpowers` spec path.
- Remaining AI/process smell in public surface: **low**; mostly contained to clearly labeled internal/maintainer material.
- Exact next action:
  1. Delete local root `.DS_Store` file in your working copy.
  2. Keep internal analysis docs under `Docs/Internal/Analysis/` and avoid linking them from onboarding sections.
  3. Continue enforcing `.gitignore` as-is (now includes `Docs/superpowers/`).
