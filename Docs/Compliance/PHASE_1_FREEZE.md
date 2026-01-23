# Phase 1 Freeze Policy

## Status: FROZEN

Phase 1 concurrency compliance is complete and frozen. This document defines the guardrails to prevent accidental violations.

## Core Modules Under Freeze

**No edits unless bugfix:**
- `PageStore.swift` and all `PageStore+*.swift` extensions
- `QueryBuilder.swift` and `QueryBuilder+*.swift` extensions
- `DynamicCollection.swift` and core collection logic
- Encoding/decoding core (`BlazeBinaryEncoder`, `BlazeBinaryDecoder`)
- Storage layout persistence

**Exception:** Critical bugfixes only (data corruption, security issues). All other changes require explicit Phase 1 freeze exception approval.

## Required Checks Before Any Change

**Any change to core modules must:**
1.  Run `swift test --filter BlazeDBClientTests.testDurabilityAfterConcurrencyChanges`
2.  Run all core tests (`swift test` excluding distributed modules)
3.  Verify Swift 6 strict concurrency still compiles: `swift build -Xswiftc -strict-concurrency=complete`
4.  Update `CONCURRENCY_COMPLIANCE.md` if concurrency-related

**Any concurrency change additionally requires:**
-  All 8 `queue.sync` guardrails still in place
-  No new `Task.detached` in core
-  No new `@unchecked Sendable` without documented justification
-  Deadlock guardrails verified (`dispatchPrecondition` checks)

## What IS Allowed (Feature Work)

**Safe to add without touching frozen core:**
- CLI tools (`blazedb doctor`, diagnostics)
- Diagnostics APIs (`db.stats()`, health checks)
- Test infrastructure (crash recovery, fuzzing, migration tests)
- Documentation (README, examples, tutorials)
- Packaging (versioning, CHANGELOG)
- Distributed modules (separate from core)

**Principle:** Features that operate "outside the heart" are encouraged. Features that touch storage/query/encoding core require freeze exception.

## Freeze Exception Process

To modify frozen core:
1. Document the bug/issue clearly
2. Explain why change cannot be avoided
3. Show test coverage for the change
4. Verify all required checks pass
5. Update `CONCURRENCY_COMPLIANCE.md` if applicable

**Default answer:** No. Freeze exists for a reason.

## Why This Matters

Phase 1 represents a correct, guarded, tested foundation. Violating the freeze risks:
- Reintroducing concurrency bugs
- Breaking Swift 6 compliance
- Undermining deadlock guardrails
- Compromising durability guarantees

**The freeze is not bureaucracy. It's protection against regression.**

## Phase 2 Status

Phase 2 (controlled parallelism) is documented in `PHASE_2_PARALLELISM.md` but **not started**.

Phase 2 will only begin when:
- Profiling shows encoding + compression ≥ 30–40% of batch time
- Storage is not the bottleneck
- Durability tests are boringly green

Until then: **Ship features, not optimizations.**
