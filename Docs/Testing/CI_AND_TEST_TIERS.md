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
    - `swift test --filter BlazeDB_Tier0`, then `swift test --skip-build --filter BlazeDB_Tier1`
    - `ripgrep` (brew if needed) + `./Scripts/verify-clean-checkout.sh` + `./Scripts/verify-readme-quickstart.sh` (same toolchain as local dev — not on Linux)
  - **Secondary (non-blocking):** `Linux (Swift 6) — best-effort`
    - Runner: `ubuntu-22.04`
    - Same test tiers after `swift build`; `continue-on-error: true`

- `.github/workflows/tag-probe.yml`
  - Trigger: **manual** (`workflow_dispatch`) only
  - Runs `./Scripts/check-release-tag-builds.sh` (last three `v*` tags) on Ubuntu; use when you care about old tag buildability, not on every push

- `.github/workflows/release.yml`
  - Trigger: tag push `v*`
  - Behavior:
    - Run `BlazeDB_Tier0`, `BlazeDB_Tier1`, `BlazeDB_Tier3_Heavy`
    - Build release artifact
    - Generate release notes
    - Publish GitHub release
  - Blocking: release-only

## Tier Purposes

- `BlazeDB_Tier0`
  - Fast deterministic correctness gate for PRs and local preflight.
  - Must stay bounded and stable.

- `BlazeDB_Tier1`
  - Deeper correctness contracts (persistence/security/feature behavior).
  - Used in nightly/manual and deeper local checks.

- `BlazeDB_Tier2`
  - Integration and recovery scenarios.
  - **Built from nested package** `BlazeDBExtraTests/` (not part of root `swift test` graph).
  - Non-blocking lane by default.

- `BlazeDB_Tier3_Heavy` / `BlazeDB_Tier3_Destructive`
  - Stress, fuzz, and destructive/fault-injection lanes.
  - Declared under `BlazeDBExtraTests/Package.swift`; run via `cd BlazeDBExtraTests && swift test …`.
  - Manual/explicit use only; never default PR gate.

## Local Entry Points

- `./Scripts/preflight.sh`
  - Runs exactly the local gate expected before push:
    - `swift build`
    - `./Scripts/run-tier0.sh`

- Tier runners:
  - `./Scripts/run-tier0.sh`
  - `./Scripts/run-tier1.sh`
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
