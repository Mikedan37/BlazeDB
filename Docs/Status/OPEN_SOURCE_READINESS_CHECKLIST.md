# BlazeDB Open Source Readiness Checklist

> This document is an internal OSS release/process checklist. Most users should start with `README.md`
> and `Docs/GettingStarted/`.

Use this checklist to decide if the current branch is ready for a public OSS release.

## Hosted CI status

BlazeDB includes GitHub Actions workflows under `.github/workflows/` for CI validation (see `Docs/Testing/CI_AND_TEST_TIERS.md`).

**Note:** Whether workflows run successfully on every push/PR depends on **repository configuration, permissions, and GitHub billing / spending limits** for the hosting account. A missing or blocked hosted run does not by itself mean the codebase is wrong.

**Contributors should rely on local validation** before opening a PR:

- `./Scripts/preflight.sh` (or `swift test --filter BlazeDB_Tier0` plus build as documented in `CONTRIBUTING.md`)
- `./Scripts/run-tier1.sh` for the Tier0 + Tier1 fast gate with coverage checks
- `./Scripts/verify-clean-checkout.sh` and `./Scripts/verify-readme-quickstart.sh` before release-style confidence

## 1) Core Quality Gates

- [x] Tier0 golden-path gate test is enabled and passing.
- [x] Tier1 golden-path integration test is passing.
- [ ] Tier0 + Tier1 (`BlazeDB_Tier1`) are green in **hosted** CI when workflows are allowed to run (see [Hosted CI status](#hosted-ci-status) above).
- If hosted Actions cannot run (billing, forks, or org policy), treat **local** runs of the same commands as the merge gate evidence until CI is restored.
- [x] Next public release tag candidate build passes from a fresh clone.
- Verified locally via `Scripts/verify-clean-checkout.sh` and `Scripts/verify-readme-quickstart.sh`.
- OSS verification runs on **macOS** in `.github/workflows/ci.yml` (clean checkout + README quickstart on every push/PR).
- Legacy **`v*` tag buildability** (optional): manual workflow `.github/workflows/tag-probe.yml` and helper `Scripts/check-release-tag-builds.sh` (not run on every push/PR; see `Docs/Testing/CI_AND_TEST_TIERS.md`).
- Tooling in place: `Scripts/verify-clean-checkout.sh` (release build + clean-worktree validation path).
- Tag build probe: `Scripts/check-release-tag-builds.sh`.

## 2) Security and Trust

- [x] External third-party security review is scheduled/tracked (scope: at-rest crypto, metadata integrity, recovery paths).
- Tracking plan: `Docs/Status/EXTERNAL_SECURITY_REVIEW_PLAN.md`.
- Tracking issue template: `.github/ISSUE_TEMPLATE/security_review_tracking.md`.
- [x] Publish a security policy (`SECURITY.md`) with disclosure and response SLAs.
- [x] Document supported key-management modes and unsafe compatibility fallbacks.
- [x] Confirm benchmark-only no-encryption mode is clearly marked non-production.

## 3) Compatibility and Durability

- [x] Publish compatibility matrix (supported OS/Swift versions).
- [x] Document durability modes and support policy for legacy vs unified paths.
- [x] Add migration guidance for legacy metadata/layout encodings.
- [x] Validate export/restore compatibility across at least two released versions.
- Harness in place: `BlazeDB_Tier2.CrossVersionExportRestoreHarnessTests` + `Tests/CompatibilityFixtures/`.
- Evidence fixtures: `Tests/CompatibilityFixtures/v0.1.3/dump.blazedump` and `Tests/CompatibilityFixtures/v2.7.0/dump.blazedump`.

## 4) Contributor Experience

- [x] Ensure `README.md` quickstart works from scratch in under 5 minutes.
- Verified by `Scripts/verify-readme-quickstart.sh` (clean snapshot + `swift run HelloBlazeDB`, measured 35s on latest local run).
- `HelloBlazeDB` now uses an isolated temp database path per run to keep quickstart behavior deterministic.
- [x] Publish a one-command local verification script (build + core tests).
- [x] Reduce high-noise warnings in test output for clearer signal.
- `Scripts/oss-readiness-local.sh` and `Scripts/verify-clean-checkout.sh` now summarize per-step warning counts and write full logs to files instead of flooding terminal output.
- [x] Confirm `CONTRIBUTING.md` matches actual workflow and branch policy.

## 5) Release Operations

- [x] Pin release checklist in repo (`Docs/Status`) and link from `README.md`.
- [x] Produce versioned changelog entry with upgrade notes.
- [x] Define rollback/revert procedure for bad releases.
- [x] Define maintenance policy (supported versions, deprecation cadence).

## Go/No-Go Rule

Ship public OSS release only when:

1. Core gates are green from a **clean checkout** (hosted CI when available; otherwise the **same commands** run locally and documented in this checklist).
2. Security policy is published and external review is scheduled (or complete).
3. Durability/compatibility behavior is documented without ambiguous guarantees.
