# OSS core build boundary (BlazeDBCore)

The `BlazeDBCore` target is built from the `BlazeDB/` source directory using an `exclude:` list in the root `Package.swift`.

## What exclusion means

- **Excluded paths are not compiled** into the `BlazeDBCore` SwiftPM target. They remain in the repository for packaging reasons, future work, or alternate build graphs.
- **In-tree code is not automatically supported OSS runtime behavior** just because it exists. If it is excluded from `BlazeDBCore`, consumers of the published package should not rely on it unless you re-enable it in `Package.swift` and document that change.
- **Exclusion is a packaging and support boundary**, not a promise that the code is dead. Some excluded code is intentionally deferred (for example distributed or telemetry-related sources).

## What to read for the default engine

For durability, defaults, and what `BlazeDBClient` actually uses, see [Durability mode support policy](../Status/DURABILITY_MODE_SUPPORT.md).

## Categories in `exclude:` (see `Package.swift` for the authoritative list)

Examples include: distributed and telemetry **directories**; specific **Exports** files (sync, telemetry, server, shared secret); selected **Migration** sources tied to excluded infrastructure; **test plan** files excluded from source scanning.
