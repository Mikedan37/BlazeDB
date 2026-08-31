# ``BlazeDBCore``

BlazeDB is an encrypted, embedded database for Swift apps. Use it on the command line, in a plain Swift app, or in SwiftUI.

**New here?** Read <doc:DailyAPI> first (five operations). Then <doc:QuickReference> or <doc:SwiftUIIntegration>.

## Overview

Most apps follow one of two paths:

1. **SwiftUI apps** open once, inject with `.blazeDBEnvironment(_:)`, read with ``BlazeStorableQuery``, write with the `blazeDBClient` environment value.
2. **Non-UI code** open with ``BlazeDB/open(name:password:)``, then use `put`, `get`, and namespace `query`.

The ``BlazeDB`` package product re-exports this module. In app code you usually write `import BlazeDB`.

Open ``BlazeDBClient`` for curated topic groups at the top of that symbol page; the auto-generated list below it is the full advanced reference.

All databases are encrypted. You must provide a password when opening.

Default file locations:

- **macOS:** `~/Library/Application Support/BlazeDB/`
- **iOS:** app sandbox `Library/Application Support/BlazeDB/`
- **Linux:** `~/.local/share/blazedb/`

## Topics

### Start here (most apps)

- <doc:DailyAPI>
- <doc:QuickReference>
- <doc:ImplementationChecklist>
- <doc:SwiftUIIntegration>
- <doc:GettingStarted>

### App recipes

- <doc:AppPatterns>
- <doc:RelatedData>
- <doc:LocationQueries>

### Core types

- ``BlazeDB``
- ``BlazeDBClient``
- ``BlazeStorable``
