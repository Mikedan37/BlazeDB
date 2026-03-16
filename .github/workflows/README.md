# GitHub Actions Workflows

This directory defines BlazeDB CI/CD entry points.

For tier intent and local equivalents, see `Docs/Testing/CI_AND_TEST_TIERS.md`.

## Active Workflow Map

### `ci.yml` (Primary Gate)
- Triggers:
  - push: `main`, `develop`
  - pull_request: `main`, `develop`
- Job:
  - `Build & Test` on `ubuntu-22.04`
- Behavior:
  - build on clean runner
  - `swift test --filter BlazeDB_Tier0`
  - `swift test --skip-build --filter BlazeDB_Tier1`
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
  - run `BlazeDB_Tier0`, `BlazeDB_Tier1`, and `BlazeDB_Tier3_Heavy`
  - build/package release artifact
  - generate release notes
  - create GitHub release

### `oss-readiness-evidence.yml` (Evidence Lane)
- Triggers:
  - push: `main`
  - manual dispatch
- Behavior:
  - runs `./Scripts/verify-clean-checkout.sh`
  - runs `./Scripts/verify-readme-quickstart.sh`
  - runs legacy tag reproducibility probe and uploads `.tagcheck-*.log` artifacts
- Merge impact:
  - evidence lane (diagnostic and release-confidence focused)

## Rules

- Do not change workflow behavior in docs-only cleanup PRs.
- Any workflow trigger/job/command change must update this README and `Docs/Testing/CI_AND_TEST_TIERS.md` in the same PR.

