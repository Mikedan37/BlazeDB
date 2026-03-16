# Release Evidence Blockers

This document records blockers discovered while executing OSS readiness evidence checks on clean worktrees.

## Release Tag Buildability

### Shared blocker across legacy tags

- Result: **fresh clean environment cannot fetch private SSH dependencies**.
- Failure:
  - `git@github.com: Permission denied (publickey).`
  - `Failed to clone repository git@github.com:Mikedan37/BlazeTransport.git`
- Impact:
  - Release-tag build reproducibility is not publicly verifiable without private SSH key access.
  - This does **not** block current core-only OSS builds on main; it blocks reproducibility for affected legacy tags and deferred distributed transport re-enable work.

### `v2.6.0`

- Result: **cannot build on current Swift toolchain**.
- Representative failures:
  - strict concurrency conformance/isolation errors in distributed relay types,
  - non-Sendable shared mutable state errors,
  - async API mismatch errors in query async extensions.

### `v2.7.0`

- Result: **package manifest/target path issue in clean worktree**.
- Failure:
  - `invalid custom path 'Examples/ReferenceConsumer' for target 'ReferenceConsumer'`.

## Impact

- Legacy-tag reproducibility remains blocked for historical pre-OSS tags until those tags are rebuilt from public dependencies (not possible in-place on immutable historical tags).
- Next-release (core-only) confidence is now covered by clean-snapshot verification and CI evidence workflows.
- Compatibility harness evidence now exists for two released lines (`v0.1.3`, `v2.7.0`) in `Tests/CompatibilityFixtures/`.
- Main-branch local evidence improved:
  - `Scripts/verify-clean-checkout.sh` passes with concise per-step logs.
  - `Scripts/verify-readme-quickstart.sh` confirms README quickstart behavior in a clean snapshot.

## Unblock Plan

1. Keep legacy tags explicitly marked archival/non-reproducible unless re-cut from public dependency URLs.
2. Ensure next public release tags are cut from the current core-only dependency graph.
3. Run clean fresh-clone evidence workflow on CI and attach artifacts/logs to release evidence.
4. Keep compatibility fixtures refreshed for new released lines.

## Local Tooling

- `Scripts/check-release-tag-builds.sh` performs reproducible tag buildability checks and emits per-tag logs.
- `Scripts/verify-clean-checkout.sh` performs clean worktree validation and stores logs under `.logs/clean-checkout/`.
- `Scripts/verify-readme-quickstart.sh` validates `HelloBlazeDB` quickstart from a clean snapshot within a 5-minute target.
