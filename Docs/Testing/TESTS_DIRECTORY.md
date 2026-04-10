# Tests directory layout

## SwiftPM test targets (root package)

The repository root `Package.swift` defines test targets whose sources live under **`BlazeDBTests/`** (for example `BlazeDB_Tier0`, `BlazeDB_Tier1`, `BlazeDB_Tier2`, `BlazeDB_Tier3_Heavy`). That is what `swift test` and the default CI workflow exercise when filtering those targets.

## Top-level `Tests/` directory

The **`Tests/`** directory at the repository root is **not** the same tree as **`BlazeDBTests/`**. It may contain nested Swift packages, harnesses, or legacy layouts.

For example, `Tests/CrashRecoveryHarness/Package.swift` defines a **separate** Swift package that depends on this repo via a relative path. That means **`Tests/` is not automatically unused or safe to delete** without an inventory.

## Before deleting or moving `Tests/`

1. List nested `Package.swift` files under `Tests/`.
2. Search CI scripts, READMEs, and developer docs for references to `Tests/`.
3. Confirm no Xcode workspace or external workflow relies on paths under `Tests/`.

When in doubt, keep the tree and document it here rather than removing it.
