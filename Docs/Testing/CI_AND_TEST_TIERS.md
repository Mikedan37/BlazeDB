# CI And Test Tiers

This file is the single source of truth for BlazeDB CI lanes and test-tier intent.

If this file conflicts with other docs, treat this file and `.github/workflows/*.yml` as authoritative.

For branch discipline and PR hygiene, see `Docs/Guides/WORKFLOW_AND_STYLE_GUIDE.md`.

## Workflow Inventory

- `.github/workflows/ci.yml`
- Triggers: push and pull_request on `main`, `develop`
- All jobs use **`actions/checkout` with `fetch-depth: 0`** so tags and worktree scripts match a full clone.
- **Primary check (blocking):** `macOS 15 — build, CLI, tests, clean-checkout, quickstart`
- Runner: `macos-15`; **does not** use `swift-actions/setup-swift` — tests run with **Xcode’s** `swift` so XCTest/`XCTestCore` resolves (OSS Swift on macOS does not).
- `swift build --target BlazeDBCore`, CLI targets (`BlazeDoctor`, `BlazeDump`, `BlazeInfo`)
- `swift test --filter BlazeDB_Tier0`, then `swift test --skip-build --filter BlazeDB_Tier1Fast`
- `ripgrep` (brew if needed) + `./Scripts/verify-clean-checkout.sh` + `./Scripts/verify-readme-quickstart.sh` (same toolchain as local dev — not on Linux)
- **Secondary (non-blocking):** `Linux (Swift 6) — best-effort`
- Runner: `ubuntu-22.04`
- Same test tiers after `swift build`; `continue-on-error: true`

- `.github/workflows/tag-probe.yml`
- Trigger: **manual** (`workflow_dispatch`) only
- Runs `./Scripts/check-release-tag-builds.sh` (last three `v*` tags) on Ubuntu; use when you care about old tag buildability, not on every push

- `.github/workflows/tier1-depth.yml`
- Trigger: **weekly schedule** and **manual** (`workflow_dispatch`)
- Runs **`BlazeDB_Tier1Extended`** and **`BlazeDB_Tier1Perf`** only (not `BlazeDB_Tier1Fast`; that is already covered on every PR). This is the scheduled **Tier1 depth** lane—see [Reporting vocabulary](#reporting-vocabulary) below.

- `.github/workflows/release.yml`
- Trigger: tag push `v*`
- Behavior:
- Run `BlazeDB_Tier0`, `BlazeDB_Tier1Fast`, `BlazeDB_Tier1Extended`, `BlazeDB_Tier1Perf`, `BlazeDB_Tier3_Heavy`
- Build release artifact
- Generate release notes
- Publish GitHub release
- Blocking: release-only

## Tier Purposes

- `BlazeDB_Tier0`
- Fast deterministic correctness gate for PRs and local preflight.
- Must stay bounded and stable.

- `BlazeDB_Tier1Fast`
- Default PR and local correctness gate: deterministic core contracts without `measure()`, fixed sleeps, or benchmark-shaped workloads.
- Sources: `BlazeDBTests/Tier1Core/` (with a small `Package.swift` exclude list for broken/architectural tests).

- `BlazeDB_Tier1Extended`
- Integration, distributed sync, sleep-dependent timing, and large-N stress that should stay in CI but not in the default fast loop.
- Sources: `BlazeDBTests/Tier1Extended/` (includes most of `Sync/`). Shared helpers via symlink to `Tier1Core/Helpers`.
- **`Package.swift` excludes** a few sync harnesses that depend on distributed-only types (`InMemoryRelay`, cross-app sync, topology) until those are wired against a non–core-only build.

- `BlazeDB_Tier1Perf`
- XCTest `measure()` and benchmark-shaped suites.
- Sources: `BlazeDBTests/Tier1Perf/`. Shared helpers via symlink to `Tier1Core/Helpers`.

- `BlazeDB_Tier2`
- Integration and recovery scenarios.
- **Built from nested package** `BlazeDBExtraTests/` (not part of root `swift test` graph).
- Non-blocking lane by default.

- `BlazeDB_Tier3_Heavy` / `BlazeDB_Tier3_Destructive`
- Stress, fuzz, and destructive/fault-injection lanes.
- Declared under `BlazeDBExtraTests/Package.swift`; run via `cd BlazeDBExtraTests && swift test …`.
- Manual/explicit use only; never default PR gate.

## Reporting vocabulary

Use precise language so status and dashboards do not blur the PR gate with deeper lanes.

| Say this | Meaning |
| -------- | ------- |
| **Tier1 PR gate** / **T1 fast** | `BlazeDB_Tier1Fast` only—the default blocking Tier1 lane on PRs. |
| **Tier1 depth** | `BlazeDB_Tier1Extended` + `BlazeDB_Tier1Perf` (weekly/manual `tier1-depth.yml`, or `./Scripts/run-tier1-depth.sh`). Does *not* by itself imply `BlazeDB_Tier1Fast` ran. |
| **Full Tier1** / **Tier1 all lanes** | `BlazeDB_Tier1Fast` + `BlazeDB_Tier1Extended` + `BlazeDB_Tier1Perf` (e.g. release validation). |

Inventory/bootstrap code may still bucket all three SwiftPM modules under a single **`T1`** label for file-level manifests; that is a storage convenience. **Human-facing** summaries (CI names, release notes, team chat) should use the table above, not a vague “T1 passed.”

### Shared helpers (symlinks)

`Tier1Extended/Helpers` and `Tier1Perf/Helpers` symlink to `Tier1Core/Helpers` so helper sources stay single-sourced. SwiftPM generally handles this; if a platform or archive step misbehaves (often Linux or packaging), replace with a small **shared test-support target** and drop the symlinks—see `Package.swift` when that happens.

### `BlazeDB_Tier1Fast` excludes

A few files remain **excluded** from `Tier1Core` in `Package.swift` because they do not compile or fit the core-only harness yet. That is **intentional debt**: track them, rehome into the right lane, or fix the underlying code—do not treat the exclude list as permanent.

## Local Entry Points

- `./Scripts/preflight.sh`
- Runs exactly the local gate expected before push:
- `swift build`
- `./Scripts/run-tier0.sh`

- Tier runners:
- `./Scripts/run-tier0.sh`
- `./Scripts/run-tier1.sh` (Tier 0 + `BlazeDB_Tier1Fast` + execution coverage)
- `./Scripts/run-tier1-depth.sh` (`BlazeDB_Tier1Extended` + `BlazeDB_Tier1Perf`)
- `./Scripts/run-tier2.sh`
- `./Scripts/run-tier3.sh`

## Before Merge Checklist

- Confirm working tree is intentional (`git status`, `git diff`).
- Run `./Scripts/preflight.sh`.
- Ensure required checks are green on PR (primary: `macOS 15 — build, CLI, tests, clean-checkout, quickstart`).
- Do not mix workflow behavior changes with docs-only cleanup in the same PR unless explicitly scoped.

## Maintenance Policy

- Any workflow trigger/job/command change must update this file in the same PR.
- Any test-tier target rename must update:
- this file
- `CONTRIBUTING.md`
- tier runner scripts under `Scripts/`
