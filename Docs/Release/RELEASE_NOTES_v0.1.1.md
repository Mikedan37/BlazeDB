# BlazeDB v0.1.1 - Dependency Stability Fix

**Release Date:** January 23, 2026  
**Tag:** v0.1.1

---

## Fixed

- **SwiftPM Dependency Resolution:** Pinned SwiftCBOR to stable tagged release (v0.6.0)
  - Resolves error: "package 'blazedb' depends on an unstable-version package 'swiftcbor'"
  - Ensures BlazeDB can be consumed with stable version requirements
  - All transitive dependencies are now stable

---

## Technical Details

When consumers pin BlazeDB to a stable version (e.g., `exact: "0.1.0"`), SwiftPM requires all transitive dependencies to also be stable. This patch release pins SwiftCBOR to a tagged version, ensuring reproducible builds and resolving SwiftPM dependency resolution errors.

**Why this matters:**
- SwiftPM enforces supply-chain integrity
- Stable transitive dependencies ensure reproducible builds
- This is required for production hygiene

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "0.1.1")
]
```

---

## What Changed

**Package.swift:**
- Added SwiftCBOR dependency pinned to `exact: "0.6.0"`
- Ensures stable dependency resolution for consumers

**No API changes** - This is a dependency hygiene fix only.

---

## For Consumers

If you're seeing the SwiftPM error:
```
package 'blazedb' depends on an unstable-version package 'swiftcbor'
```

**Solution:** Update to BlazeDB v0.1.1 or later.

---

## Full Feature List

See [v0.1.0 release notes](https://github.com/Mikedan37/BlazeDB/releases/tag/v0.1.0) for complete feature list.

---

**This is a production hygiene fix. No functional changes.**
