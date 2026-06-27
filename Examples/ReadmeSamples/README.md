# README sample verification

Canonical mapping between [README.md](../../README.md) and executable verification.  
**Maintainers:** update this file whenever README samples or harness functions change.

## Documentation verification model

| Level | What it checks | How it runs |
|-------|----------------|-------------|
| **L1 — Quickstart** | Path A: clone → `swift run HelloBlazeDB` | `./Scripts/verify-readme-quickstart.sh` |
| **L2 — Public API** | Core CRUD, query, transactions, export, etc. | `BlazeDB_Tier0` → `PublicAPIVerificationTests` |
| **L3 — README samples** | Runnable Swift patterns copied from README | `./Scripts/verify-readme-samples.sh` → `swift run ReadmeSamples` |

**Goal:** every user-facing workflow that claims to be executable has a verification strategy — not every fenced code block.

L1 and L3 run in the **PR gate** (macOS) and **nightly** README jobs. L2 runs in Tier0 on every PR.

## Status meanings

| Status | Meaning |
|--------|---------|
| **Verified** | Executed in CI via `ReadmeSamples` or `HelloBlazeDB` |
| **Compile-only** | Intentionally compiled but not executed (none today) |
| **Manual** | Package manifests, install steps, external tooling — verified by human review |
| **Out of scope** | SwiftUI, platform-specific guides, conceptual prose — covered elsewhere or not executable in this harness |

## Contributor rule

If a README change introduces **executable BlazeDB API usage**, either:

1. **Add or update** a matching verification in `main.swift` and a row in the coverage table below, or  
2. **Document here** why the section is intentionally not verified (status **Manual** or **Out of scope**).

Every new example must land in one of those buckets — not an undocumented third state.

## Coverage table

| README anchor | Status | Verified by | CI |
|---------------|--------|-------------|-----|
| [Start Here](../../README.md#start-here-new-users) | Verified | `verifyStartHere()` | L3 |
| [Which API should I use?](../../README.md#which-api-should-i-use) | Out of scope | Prose/tables only; behavior covered by L3 rows below | — |
| [Try BlazeDB — minimal Note](../../README.md#try-blazedb-from-this-repo) | Verified | `verifyMinimalNote()` | L3 |
| [Try BlazeDB — `swift run HelloBlazeDB`](../../README.md#try-blazedb-from-this-repo) | Verified | `HelloBlazeDB` executable | L1 |
| [Add BlazeDB — Package.swift](../../README.md#add-blazedb-to-your-app) | Manual | SwiftPM manifest snippet; consumer integration | — |
| [List + List Items](../../README.md#example-lists-and-list-items) | Verified | `verifyListItems()` | L3 |
| [Direct CRUD](../../README.md#direct-crud-secondary) | Verified | `verifyDirectCRUD()` | L3 |
| [TypedStore](../../README.md#typedstore) | Verified | `verifyTypedStore()` | L3 |
| [Raw API](../../README.md#raw-api-advanced) | Verified | `verifyRawAPI()` | L3 |
| [Opening a database](../../README.md#opening-a-database) | Verified | `verifyOpening()` | L3 |
| [Transactions](../../README.md#transactions) | Verified | `verifyTransactions()` | L3 |
| [Utilities](../../README.md#utilities) | Verified | `verifyUtilities()` | L3 |
| [Default API](../../README.md#default-api-recommended) | Verified | `verifyStartHere()` | L3 |
| [SwiftUI query wrappers](../../README.md#swiftui-query-wappers-apple-platforms-only) | Out of scope | Apple/SwiftUI; see [SWIFTUI_DATABASE_PATTERNS.md](../../Docs/GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) | — |
| [BlazeDocument / `@BlazeQuery`](../../README.md#two-typed-protocols) | Out of scope | Advanced manual mapping; separate guides | — |
| Core Concepts, Durability, Platform, Tools, Limitations | Out of scope | Conceptual / matrix / links | — |

## Run locally

```bash
# All L3 samples (same as CI)
swift run ReadmeSamples

# One section (matches CI failure messages)
swift run ReadmeSamples --only transactions
swift run ReadmeSamples --only start-here

# Enforce checklist ↔ harness sync (no README parsing)
./Scripts/check-readme-sample-coverage.sh
```

Valid `--only` keys: `start-here`, `minimal-note`, `list-items`, `direct-crud`, `typed-store`, `raw-api`, `opening`, `transactions`, `utilities`.

## Checklist enforcement

`Scripts/check-readme-sample-coverage.sh` reads **this file's coverage table** (not README fences):

- Every **Verified** row with a `verify*()` function → function exists in `main.swift` and is invoked from `main()`.
- Every **Verified** row with `HelloBlazeDB` → executable target exists in `Package.swift`.

Run automatically at the start of `./Scripts/verify-readme-samples.sh`.
