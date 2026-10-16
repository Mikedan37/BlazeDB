# Starter tasks (curated)

Five **documentation and tooling** tasks suitable for a first contribution. Each maps to an **open** GitHub issue as of 2026-10-16. Comment on the issue before opening a PR.

The [`good first issue`](https://github.com/Mikedan37/BlazeDB/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) label includes harder work (Android, concurrency). **Start here instead.**

**Minimum verification for doc-only PRs:**

```bash
./dev tier0                    # fast loop (~minutes)
rg -n '<phrase you changed>' Docs/   # confirm edits
```

For CLI/doc alignment tasks, also run the command listed in the issue body.

---

## 1. Issue #173 — Convenience API guide vs public facade

| | |
|--|--|
| **Scope** | Align `Docs/Guides/CONVENIENCE_API_GUIDE.md` with `BlazeDB.open` / `BlazeDBClient` patterns in [PublicFacadeAPI.swift](../../BlazeDB/Exports/PublicFacadeAPI.swift) |
| **Acceptance** | No doc examples using removed or deprecated initializers without a “legacy” label; link to [Getting Started](../GettingStarted/README.md) |
| **Verify** | `rg -n "BlazeDBClient\\(name:" Docs/Guides/CONVENIENCE_API_GUIDE.md` |
| **Review** | Docs-only; no storage changes |

---

## 2. Issue #273 — SECURITY.md vs KDF parameters

| | |
|--|--|
| **Scope** | Ensure [SECURITY.md](../../SECURITY.md) matches PBKDF2 iteration counts and naming in [KeyManager.swift](../../BlazeDB/Crypto/KeyManager.swift) (not Argon2id) |
| **Acceptance** | Single source of truth cross-linked from [KEY_MANAGEMENT](../Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md) |
| **Verify** | `rg -n "PBKDF2|600|Argon2" SECURITY.md BlazeDB/Crypto/KeyManager.swift` |
| **Review** | Docs-only |

---

## 3. Issue #262 — Homebrew / install path clarity

| | |
|--|--|
| **Scope** | Homebrew tap docs vs README install paths ([README_HOMEBREW_TAP.md](../../README_HOMEBREW_TAP.md) if present) |
| **Acceptance** | Linux and macOS install paths consistent with `from: "2.8.2"` pin |
| **Verify** | Follow tap README literally on one platform |
| **Review** | Docs-only |

---

## 4. Issue #259 — CLI doctor/dump/info dispatch honesty

| | |
|--|--|
| **Scope** | Align `Docs/Guides/CLI_REFERENCE.md` with actual executables (`blazedb` REPL vs `BlazeDoctor` / `BlazeDump` / `BlazeInfo`) |
| **Acceptance** | No doc implies `blazedb doctor` if only REPL `doctor` or separate binary applies |
| **Verify** | `rg -n "doctor" BlazedbCLI/BlazedbEntry.swift Docs/Guides/CLI_REFERENCE.md` |
| **Review** | Low; see [ROADMAP.md](../../ROADMAP.md) Documentation Now theme |

---

## 5. Issue #266 — Schema / migration canonical entry

| | |
|--|--|
| **Scope** | One linked path for schema validation and migrations ([MIGRATION.md](../MIGRATION.md), Developer Guide) |
| **Acceptance** | Docs/README advanced table points to a single “start here” for migrations |
| **Verify** | `./dev test SchemaValidationTests` unchanged (behavior not required for doc PR) |
| **Review** | Docs-only |

---

## After your first PR

- Read [LEARNING_PATHS.md](LEARNING_PATHS.md) Path B (CLI) or Path A (docs)  
- Storage/crypto issues: [STORAGE_CHANGE_CHECKLIST.md](STORAGE_CHANGE_CHECKLIST.md) + maintainer comment required  

**Proposed label maintenance (maintainer):** remove `good first issue` from open Android/concurrency bugs; see [LABEL_MAINTENANCE_PROPOSAL.md](LABEL_MAINTENANCE_PROPOSAL.md).
