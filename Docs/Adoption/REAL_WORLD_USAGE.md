# Real-world usage (evidence map)

This page separates **what outsiders can verify** from **what the maintainer reports** about products that embed BlazeDB. It is not a testimonial page and does not imply independent certification.

## Evidence tiers

| Tier | Meaning |
|------|---------|
| **Public product claim** | A shipping or beta product page names BlazeDB and describes the data stored |
| **In-repo regression** | Tests or docs in this repository modeled on production failure shapes |
| **Maintainer-operated** | Described by the project owner; source may live outside this repo |
| **CI-verified sample** | Runnable example in-tree with documented build steps |

---

## Seeker for iPhone (TestFlight beta)

| | |
|--|--|
| **Tier** | Public product claim + maintainer-operated SwiftUI app |
| **What it uses BlazeDB for** | Encrypted **local** storage on device: active résumé (including PDF bytes), extracted profile, and saved job matches — survives app relaunch |
| **Public reference** | [Seeker for iPhone Beta](https://www.seekerscore.com/iphone) (states “Encrypted BlazeDB storage”) |
| **Status** | Early beta via TestFlight; features may change |
| **Not claimed here** | Production scale SLA, third-party security audit, or multi-device sync |

SwiftUI integration patterns in this repo use a `SeekerDatabase`-style singleton in DocC ([SwiftUIIntegration.md](../../BlazeDB/BlazeDBCore.docc/SwiftUIIntegration.md)). That name reflects this app’s shape; the Seeker app source is **not** in this repository.

### In-repo tests influenced by Seeker

These are **automated** shapes derived from production debugging, not a copy of the app:

| Test / area | What it guards |
|-------------|----------------|
| [TransactionThrowRollbackTests.swift](../../BlazeDBTests/Tier0Core/CoreCorrectness/TransactionThrowRollbackTests.swift) | Transaction rollback with large (overflow) records — comments reference Seeker job-record sizes |
| [CrossContextKDFIterationTests.swift](../../BlazeDBTests/Tier1Core/Security/CrossContextKDFIterationTests.swift) | Opening a DB written under production PBKDF2 iterations from test-hosted processes — regression for a Seeker crash class |

---

## Go worker + job queue (C ABI)

| | |
|--|--|
| **Tier** | Maintainer-operated + CI-verified **minimal** cgo sample in-tree |
| **Pattern** | A **Go** process persists queue/job state through **`BlazeDBC`** (`blazedb.h` byte-KV: `job:*` keys, opaque JSON or bytes). Same contract as the C hello sample (`job:42` / `queued`). |
| **In this repo** | [Examples/C/hello_blazedb.c](../../Examples/C/hello_blazedb.c) (C), [Examples/Go/hello_blazedb.go](../../Examples/Go/hello_blazedb.go) (cgo smoke) |
| **Outside this repo** | Full worker / queue program the maintainer runs in production is **not** vendored here yet; [ROADMAP.md](../../ROADMAP.md) tracks checked-in Go sources + CI gate ([#264](https://github.com/Mikedan37/BlazeDB/issues/264)) |
| **Limits** | One **owner** process per database file; other processes should talk to that owner (queue/RPC), not open the file for write themselves. Same rule for Go worker vs `blazedb` CLI on the same path. |

Build: [Examples/Go/README.md](../../Examples/Go/README.md) · ABI rules: [C_ABI_BYTE_KV.md](../Architecture/C_ABI_BYTE_KV.md).

---

## Other application-shaped examples (in-repo only)

| Sample | Role |
|--------|------|
| [AshPileExample.swift](../../Examples/AshPileExample.swift) | Multi-tenant bug-tracker sketch with RLS — **example**, not a shipped product |
| [HelloBlazeDB](../../Examples/HelloBlazeDB/main.swift) | Canonical Swift open → persist → reopen |

---

## How to add a new row (contributors)

1. Prefer a **public URL** or **runnable sample** in this repo.  
2. State **platform**, **data stored**, and **BlazeDB API surface** (Swift facade vs `BlazeDBC`).  
3. Do not imply SQL, sync, or multi-writer unless true.  
4. Open a docs PR updating this file; no telemetry required.

---

## Measurement (maintainer)

Track voluntary signals: TestFlight feedback mentioning data loss, issues referencing Seeker or Go worker builds, and successful runs of `hello_blazedb.go` / `HelloBlazeDB` on new OS releases. Stars and clones alone are not adoption proof.
