# BlazeDB Distributed (experimental)

This directory contains **optional** distributed / sync transport code. It is **excluded** from the `BlazeDBCore` SwiftPM target (see root `Package.swift`).

## Build status (honest)

There is **no** separate SwiftPM library target for this folder yet. A trial `BlazeDBDistributed` target failed to compile cleanly: Swift 6 strict-concurrency, `BlazeDBClient.fileURL` visibility from outside the core module, incomplete `WebSocketRelay` / `WebSocketRelay+UltraFast` pairing, and other drift.

**Implication:** sources here are **not** continuously typechecked by `swift build` in this repo. Treat as **staging / experimental** until a dedicated target is added and kept green in CI.

## Xcode

The **Xcode project** may compile a different subset or flags; do not assume parity with SwiftPM.
