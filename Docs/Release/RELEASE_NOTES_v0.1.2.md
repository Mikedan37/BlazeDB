# BlazeDB v0.1.2 - SwiftPM Dependency Resolution Fix

**Release Date:** January 23, 2026  
**Tag:** v0.1.2

---

## Fixed

- **SwiftPM Dependency Resolution:** Verified and pinned SwiftCBOR to exact stable version (v0.6.0)
  - Resolves error: "package 'blazedb' depends on an unstable-version package 'swiftcbor'"
  - Ensures BlazeDB can be consumed with stable version requirements
  - All transitive dependencies verified stable
  - Version bump clears SwiftPM cache metadata

---

## Technical Details

When consumers pin BlazeDB to a stable version (e.g., `exact: "0.1.0"`), SwiftPM requires all transitive dependencies to also be stable.

**What was verified:**
- ✅ SwiftCBOR pinned with `exact: "0.6.0"` (stable tagged version)
- ✅ No branch/revision references to SwiftCBOR
- ✅ Only one SwiftCBOR dependency declaration exists
- ✅ Package.resolved shows correct version (0.6.0)

**Why v0.1.2:**
- SwiftPM caches dependency metadata by version
- If v0.1.1 was ever resolved incorrectly, its cache is poisoned
- Version bump ensures fresh resolution

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "0.1.2")
]
```

---

## For Consumers

If you're seeing the SwiftPM error:
```
package 'blazedb' depends on an unstable-version package 'swiftcbor'
```

**Solution:** Update to BlazeDB v0.1.2 or later.

**Also clear Xcode caches:**
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf ~/.swiftpm
rm -rf .build
```

Then quit and reopen Xcode, and re-add BlazeDB dependency.

---

## What Changed

**Package.swift:**
- SwiftCBOR dependency verified: `exact: "0.6.0"`
- No other changes

**No API changes** - This is a dependency hygiene fix only.

---

## Full Feature List

See [v0.1.0 release notes](https://github.com/Mikedan37/BlazeDB/releases/tag/v0.1.0) for complete feature list.

---

**This is a production hygiene fix. No functional changes.**
