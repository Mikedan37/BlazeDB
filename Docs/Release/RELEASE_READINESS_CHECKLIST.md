# BlazeDB Release Readiness Checklist

Use this checklist before tagging any `vX.Y.Z` release.

This file is the release-facing checklist only. Historical strategy notes and speculative roadmap content belong in `Docs/Status/` or `Docs/Project/`, not here.

## 1) Release Preconditions

- [ ] Branch is clean and intentional (`git status`, `git diff`).
- [ ] PR gate is green (`macOS 15 — build, CLI, tests, clean-checkout, quickstart` from `.github/workflows/ci.yml`).
- [ ] `CHANGELOG.md` contains release notes for `vX.Y.Z`.
- [ ] Install snippets are current (`README.md`, `Docs/GettingStarted/*`).
- [ ] `Docs/Testing/CI_AND_TEST_TIERS.md` matches current workflow behavior.

## 2) Required Validation (Local)

- [ ] `./Scripts/preflight.sh` passes.
- [ ] `./Scripts/run-tier1.sh` passes (Tier 0 + Tier1Fast with coverage checks).
- [ ] `./Scripts/verify-clean-checkout.sh` passes.
- [ ] `./Scripts/verify-readme-quickstart.sh` passes.

## 3) Required Validation (CI)

- [ ] Push/PR CI check passed on the release commit:
- `swift build --target BlazeDBCore`
- Tier 0
- Tier1Fast
- clean-checkout verification
- README quickstart verification
- [ ] Release workflow passes for tag `vX.Y.Z` (`.github/workflows/release.yml`):
- Tier 0
- Tier1Fast
- Tier1Extended
- Tier1Perf
- Tier3 heavy

## 4) Security And Compatibility Gates

- [ ] `SECURITY.md` disclosure flow and response expectations are accurate.
- [ ] Compatibility docs are current:
- `Docs/COMPATIBILITY.md`
- `Docs/Status/DURABILITY_MODE_SUPPORT.md`
- `Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md`
- `Docs/Status/LEGACY_LAYOUT_MIGRATION_GUIDANCE.md`
- [ ] Cross-version compatibility harness is green (Tier2 cross-version export/restore).

## 5) Tag And Publish

- [ ] Create annotated tag: `git tag -a vX.Y.Z -m "BlazeDB vX.Y.Z"`.
- [ ] Push tag: `git push origin vX.Y.Z`.
- [ ] Confirm release workflow completed and GitHub Release was created.
- [ ] Confirm release artifacts and generated notes are present.

## 6) Post-Release Smoke

- [ ] Fresh sample project can add BlazeDB via SwiftPM and run a minimal open/insert/query/close flow.
- [ ] Public docs links resolve and point to current files.
- [ ] No emergency rollback conditions detected in first validation window.

## Stop/No-Go Conditions

Do not publish if any of these are true:

- Required local validation fails.
- PR gate or release workflow is red for the release commit/tag.
- Docs materially overstate or contradict current behavior.
- Security or compatibility docs are stale relative to code.

## Related Sources

- `Docs/Testing/CI_AND_TEST_TIERS.md`
- `Docs/Status/OPEN_SOURCE_READINESS_CHECKLIST.md`
- `Docs/Status/RELEASE_ROLLBACK.md`
- `Docs/Status/COMPATIBILITY_HARNESS.md`
