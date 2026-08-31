# ``BlazeDB``

The **BlazeDB** Swift package product re-exports ``BlazeDBCore``. Use `import BlazeDB` in application code.

## Overview

Open an encrypted database with ``BlazeDB/open(name:password:)`` or ``BlazeDB/open(at:password:)``. The returned ``BlazeDBClient`` is where you call ``BlazeDBClient/put(_:)``, ``BlazeDBClient/get(_:)``, and ``BlazeDBClient/query(_:)``.

Step-by-step guides live in the **BlazeDBCore** documentation catalog:

- **Getting started with BlazeDBClient** for CLI, services, and tests
- **Using BlazeDB in SwiftUI** for ``BlazeStorableQuery`` and ``View/blazeDBEnvironment(_:)``

Symbol reference pages come from the ``BlazeDBCore`` module that this product re-exports.
