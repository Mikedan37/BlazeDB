# Cross-Version Compatibility Harness

This repo includes a fixture-driven harness test for dump restore compatibility:

- Test: `BlazeDB_Tier2.CrossVersionExportRestoreHarnessTests`
- Fixture root: `Tests/CompatibilityFixtures/`
- Fixture contract: one folder per version label with `dump.blazedump`

## Run Locally

```bash
swift test --filter BlazeDB_Tier2.CrossVersionExportRestoreHarnessTests
```

## What It Verifies

For each fixture dump, the harness verifies:

1. dump integrity validation succeeds,
2. restore into a fresh database succeeds,
3. restored record count matches `dump.manifest.recordCount`,
4. health is `ok` or `warn`.

## Current Status

- Harness is implemented and wired into Tier2.
- Released fixtures are present for `v0.1.3` and `v2.7.0`.
- Fixture provenance: generated from detached release-tag worktrees; `v2.7.0` required a non-core target-path shim for `ReferenceConsumer` to run CLI examples in the current toolchain.
- Legacy dump hash compatibility is explicitly enabled in the harness path to accommodate historical exporter canonicalization differences while keeping strict verification as default elsewhere.
