# ``BlazeDBCore``

BlazeDB is an encrypted, embedded database for Swift apps. Use it on the command line, in a plain Swift app, or in SwiftUI.

**New here?** Start with <doc:QuickReference>, then <doc:SwiftUIIntegration> for SwiftUI apps.

## Overview

Most apps follow one of two paths:

1. **SwiftUI apps** open the database once, inject ``BlazeDBClient`` with ``View/blazeDBEnvironment(_:)``, read with ``BlazeStorableQuery``, and write with ``EnvironmentValues/blazeDBClient``.
2. **Non-UI code** (CLI, services, tests) open with ``BlazeDB/open(name:password:)`` or ``BlazeDBClient/open(named:password:)``, then use ``BlazeDBClient/put(_:)``, ``BlazeDBClient/get(_:)``, and ``BlazeDBClient/query(_:)``.

The ``BlazeDB`` package product re-exports this module. In app code you usually write `import BlazeDB`.

All databases are encrypted. You must provide a password when opening.

Default file locations:

- **macOS:** `~/Library/Application Support/BlazeDB/`
- **iOS:** app sandbox `Library/Application Support/BlazeDB/`
- **Linux:** `~/.local/share/blazedb/`

## Topics

### Essentials

- <doc:QuickReference>
- <doc:GettingStarted>
- <doc:SwiftUIIntegration>

### App recipes

- <doc:AppPatterns>
- <doc:RelatedData>
- <doc:LocationQueries>

### Core types

- ``BlazeDB``
- ``BlazeDBClient``
- ``BlazeStorable``
