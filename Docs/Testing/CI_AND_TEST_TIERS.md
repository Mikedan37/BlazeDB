# CI And Test Tiers

This file is the single source of truth for BlazeDB CI lanes and test-tier intent.

If this file conflicts with other docs, treat this file and `.github/workflows/*.yml` as authoritative.

For branch discipline and PR hygiene, see `Docs/Guides/WORKFLOW_AND_STYLE_GUIDE.md`.

## Workflow Inventory

- `.github/workflows/ci.yml`
  - Triggers: push and pull_request on `main`, `develop`
  - Check name: `Build & Test`
  - Behavior:
    - Push: `swift test` (full suite)
    - PR: `swift test --filter BlazeDB_Tier0` (fast gate)
  - Blocking: yes

- `.github/workflows/core-tests.yml`
  - Triggers: nightly schedule + manual dispatch
  - Behavior:
    - Build `BlazeDBCore` and CLI tools
    - Run `BlazeDB_Tier0` and `BlazeDB_Tier1`
  - Blocking: no (deep lane)

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
  - Non-blocking lane by default.

- `BlazeDB_Tier3_Heavy` / `BlazeDB_Tier3_Destructive`
  - Stress, fuzz, and destructive/fault-injection lanes.
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
- Ensure required checks are green on PR (`Build & Test`).
- Do not mix workflow behavior changes with docs-only cleanup in the same PR unless explicitly scoped.

## Maintenance Policy

- Any workflow trigger/job/command change must update this file in the same PR.
- Any test-tier target rename must update:
  - this file
  - `CONTRIBUTING.md`
  - tier runner scripts under `Scripts/`
