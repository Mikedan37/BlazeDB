# ``BlazeDBClient``

Encrypted database handle for BlazeDB.

## Overview

**Most apps only need the <doc:DailyAPI>:** open, `put`, `get`, namespace `query`, and `delete`.

SwiftUI apps usually hold one client on `SeekerDatabase.shared` (or similar) and inject with `.blazeDBEnvironment(_:)`. See <doc:SwiftUIIntegration>.

This page puts **curated links at the top** so you are not lost in one flat symbol list. The auto-generated sections below are the full reference (raw `insert` / `fetch`, `query()` builder, transactions, indexes, monitoring, backup, spatial, vector, distributed, CLI helpers, and more). Use the topic groups here first; search or filter the full list only when you need an advanced feature.

## Topics

### Start here

- <doc:DailyAPI>
- <doc:QuickReference>
- <doc:ImplementationChecklist>

### SwiftUI

- <doc:SwiftUIIntegration>
- ``BlazeStorableQuery``

### Open and session

- ``BlazeDB/open(name:password:)``
- ``BlazeDB/open(at:password:)``
- ``BlazeDBClient/open(named:password:)``
- ``BlazeDBClient/open(at:password:)``

### Typed models

- ``BlazeStorable``

### App recipes

- <doc:AppPatterns>
- <doc:RelatedData>
- <doc:LocationQueries>
