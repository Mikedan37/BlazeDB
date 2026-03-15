# GitHub Actions Workflows

This directory defines BlazeDB CI/CD entry points.

For tier intent and local equivalents, see `Docs/Testing/CI_AND_TEST_TIERS.md`.

## Active Workflow Map

### `ci.yml` (Primary Gate)
- Triggers:
  - push: `main`, `develop`
  - pull_request: `main`, `develop`
- Job:
  - `Build & Test` on `macos-15`
- Behavior:
  - push: `swift test` (full suite)
  - pull_request: `swift test --filter BlazeDB_Tier0` (fast gate)
- Merge impact:
  - primary blocking check

### `core-tests.yml` (Deep Lane)
- Triggers:
  - nightly schedule
  - manual dispatch
- Job:
  - `Core Tests (Swift 6)` on `macos-14`
- Behavior:
  - build `BlazeDBCore` and CLI targets
  - run `BlazeDB_Tier0` and `BlazeDB_Tier1`
- Merge impact:
  - non-blocking deep validation lane

### `release.yml` (Tag Releases)
- Trigger:
  - tag push `v*`
- Behavior:
  - validate release tests
  - build/package release artifact
  - generate release notes
  - create GitHub release

### `test.yml` (Placeholder)
- Trigger:
  - push/manual
- Current role:
  - placeholder workflow
- Note:
  - keep only if explicitly needed; otherwise remove in a dedicated CI behavior PR

## Rules

- Do not change workflow behavior in docs-only cleanup PRs.
- Any workflow trigger/job/command change must update this README and `Docs/Testing/CI_AND_TEST_TIERS.md` in the same PR.

