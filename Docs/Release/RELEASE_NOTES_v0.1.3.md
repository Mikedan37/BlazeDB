# BlazeDB v0.1.3 - SwiftUI APIs Now Available

**Release Date:** January 23, 2026
**Tag:** v0.1.3

---

## Added

- **SwiftUI Integration:** `@BlazeQuery` property wrapper is now available to consumers
- Included SwiftUI directory in BlazeDBCore target
- Fixed Swift 6 strict concurrency errors
- SwiftUI code is conditionally compiled (only builds on macOS, iOS, watchOS, tvOS)

---

## Fixed

- **Swift 6 Concurrency:** Fixed Timer deinit and actor isolation errors in SwiftUI code
- Marked `autoRefreshTimer` as `@MainActor`
- Fixed `enableAutoRefresh` and `disableAutoRefresh` actor isolation

---

## Public APIs Now Available

### SwiftUI Property Wrapper

```swift
import SwiftUI
import BlazeDBCore

struct BugListView: View {
 @BlazeQuery(
 db: myDatabase,
 where: "status", equals: .string("open")
 )
 var openBugs

 var body: some View {
 List(openBugs, id: \.id) { bug in
 Text(bug["title"]?.stringValue ?? "")
 }
 }
}
```

### Value Accessors

```swift
let record: BlazeDataRecord = ...

// These are now public APIs:
record["title"]?.stringValue
record["id"]?.uuidValue
record["active"]?.boolValue
record["count"]?.intValue
```

---

## Technical Details

**What Changed:**
- Removed SwiftUI exclusion from BlazeDBCore target in Package.swift
- Fixed Swift 6 concurrency errors (Timer deinit, actor isolation)
- SwiftUI code wrapped in `#if canImport(SwiftUI)` so it only compiles on supported platforms

**Platform Support:**
- macOS 12.0+
- iOS 15.0+
- watchOS 8.0+
- tvOS 15.0+
- Linux: SwiftUI not available (conditionally excluded)

---

## Installation

```swift
dependencies: [
 .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "0.1.3")
]
```

---

## Documentation

See `Docs/Guides/SWIFTUI_INTEGRATION.md` for complete SwiftUI usage guide.

---

**@BlazeQuery and value accessors are now public APIs!**
