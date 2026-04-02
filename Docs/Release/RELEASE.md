# BlazeDB Release Runbook

This runbook describes the current release process for BlazeDB.

## Release Trigger

- Releases are created from Git tags that match `v*`.
- Workflow: `.github/workflows/release.yml`.

## Pre-Tag Checklist

- `main` is clean and synced.
- PR gate (`macOS 15 — build, CLI, tests, clean-checkout, quickstart`) is green.
- `CHANGELOG.md` updated for the target version.
- Version snippets in user-facing docs are consistent.

## Tag + Push

```bash
git switch main
git pull --ff-only
git tag -a vX.Y.Z -m "BlazeDB vX.Y.Z"
git push origin vX.Y.Z
```

## What CI Does

Release workflow validates and publishes:

- Tier 0 tests
- Tier 1 tests
- Tier 3 heavy tests
- release build artifact
- generated release notes
- GitHub release

## Verification After Publish

- Confirm release exists under GitHub Releases.
- Confirm artifact download is present.
- Confirm `README.md` install snippet matches current release line.
- Confirm `CHANGELOG.md` contains release notes for `vX.Y.Z`.

## Tag Policy

- Use only `vX.Y.Z` tags for releases.
- Avoid non-`v` release tags to keep automation deterministic.

