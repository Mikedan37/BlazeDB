# BlazeFSM Pin Issue

## Problem

SwiftPM is resolving an outdated BlazeFSM commit (5edf704) even though main has newer Linux-safe fixes. This breaks Linux builds on Orange Pi due to CoreGraphics imports.

## Attempted Fix

Added BlazeFSM as a direct dependency pinned to revision `58b292a27928d211eef12090cafcbf12b31d69c6`:

```swift
.package(
    url: "git@github.com:Mikedan37/BlazeFSM.git",
    revision: "58b292a27928d211eef12090cafcbf12b31d69c6"
)
```

## Current Blocker

**Error**: `blazefsm is required using two different revision-based requirements (58b292a27928d211eef12090cafcbf12b31d69c6 and main), which is not supported`

**Root Cause**: BlazeTransport (which BlazeDB depends on) also depends on BlazeFSM using `branch: "main"`. SwiftPM sees this as a conflict:
- BlazeDB wants: `revision: "58b292a27928d211eef12090cafcbf12b31d69c6"`
- BlazeTransport wants: `branch: "main"`

## Required Solution

BlazeTransport's Package.swift must be updated to also pin BlazeFSM to the same revision, OR BlazeTransport must be pinned to a revision that uses the correct BlazeFSM.

**Option 1**: Update BlazeTransport to pin BlazeFSM:
```swift
.package(
    url: "git@github.com:Mikedan37/BlazeFSM.git",
    revision: "58b292a27928d211eef12090cafcbf12b31d69c6"
)
```

**Option 2**: Pin BlazeTransport to a revision that already uses the correct BlazeFSM (if such a revision exists).

## Current Package.swift State

BlazeFSM pin is correctly added to BlazeDB's Package.swift. The blocker is in BlazeTransport's dependency configuration.

