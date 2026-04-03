# Compatibility Fixtures

This directory is used by `CrossVersionExportRestoreHarnessTests` to validate dump restore compatibility across releases.

## Expected Layout

Create one directory per release line/version label, each containing a deterministic dump:

```text
Tests/CompatibilityFixtures/
 2.6.0/
 dump.blazedump
 2.7.0/
 dump.blazedump
```

## Validation Contract

For each `dump.blazedump`, the Tier2 compatibility harness verifies:

1. dump integrity validation passes,
2. restore succeeds into a fresh database,
3. restored record count matches `manifest.recordCount`,
4. restored health is `ok` or `warn` (non-fatal advisory allowed).

## Notes

- This harness is intentionally fixture-driven; it skips when fixtures are absent.
- Add at least two released-version fixtures before declaring cross-version validation complete.
