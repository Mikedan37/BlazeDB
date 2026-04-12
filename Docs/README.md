# BlazeDB Documentation

This index separates the main public documentation path from maintainer-only or historical material. *Skim the headings to see where you are; you don’t have to read this file top to bottom.*

## Support-State Framing

*Quick mental model so you don’t assume sync/telemetry are in the default box.* Use this quick framing before diving into detailed docs:

- **Default shipped core:** embedded encrypted engine, typed/raw APIs, durability, import/export, health/stats, CLI tooling.
- **Advanced but supported:** migrations, schema validation, indexing/search tuning, manual mapping.
- **Conditional/deferred:** distributed sync/server/discovery and full telemetry path outside default OSS runtime packaging.
- **Historical/internal:** archive and project-management docs are non-authoritative for first-time adopters.

## Audience Segmentation

*Who each pile of docs is for—helps you ignore the wrong shelf.*

- **Public product docs:** what BlazeDB is, how to use it, what is supported now.
- **Public maintainer docs:** release/testing/CI operations for contributors.
- **Internal analysis docs:** branch/capability/positioning analysis artifacts for maintainers.

Internal analysis material lives under [`Docs/Internal/`](Internal/README.md) and should not be treated as onboarding guidance.

## Documentation guide

*Map of the folders: what to trust for “how does it work today.”* BlazeDB documentation is organized into:

- **Canonical docs (current, maintained)** — Use these first for behavior and APIs:
  - [Repository README](../README.md) (Start Here, try from repo / add to app, product summary)
  - [Getting Started](GettingStarted/) (first run, HOW_TO_USE, Linux notes)
  - [Testing / CI](Testing/) (tiers, test layout, execution model)
  - [Release](Release/) (release-facing checklists and notes)
  - [Architecture](Architecture/) — **core embedded runtime** (storage, queries, durability); prefer these over informal design notes for “what ships” in OSS.

- **Design / forward-looking docs** — Distributed transport, sync topology, and related material may describe **non-default** or **deferred** surfaces. Always cross-check [Distributed transport deferred](Status/DISTRIBUTED_TRANSPORT_DEFERRED.md) and the root `README.md` for what the default SwiftPM product includes.

- **Archived / historical docs** — [`Archive/`](Archive/) holds snapshots, old milestones, and superseded write-ups. **Not authoritative** for current OSS behavior unless explicitly cross-linked from a maintained doc.

## Start Here

*If you’re new, hit these in roughly this order—you’ll stay on the happy path.*

- [Getting Started](GettingStarted/README.md) — install the package, run `HelloBlazeDB`, paste the tiny starter snippet; the “I just want it working” path.
- [Developer Guide](DEVELOPER_GUIDE.md) — longer walkthrough of the public API in prose (CRUD, queries, patterns); read after you’ve run something once.
- [API Reference](API/API_REFERENCE.md) — lookup tables and signatures when you already know what you’re trying to call.
- [Examples](../Examples/) — copy-paste runnable projects and patterns when docs need a concrete file to stare at.

## Core Product Docs

*Stuff you’ll want when something “should work on my OS” or “what happens on crash / upgrade.”*

- [Compatibility](COMPATIBILITY.md) for supported platforms and release expectations.
- [Security](../SECURITY.md) for vulnerability reporting and disclosure expectations.
- [Durability Mode Support](Status/DURABILITY_MODE_SUPPORT.md) for WAL and recovery guarantees.
- [Key Management and Compatibility](Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md) for password and key-handling behavior.
- [Legacy Layout Migration Guidance](Status/LEGACY_LAYOUT_MIGRATION_GUIDANCE.md) for migration-sensitive upgrades.
- [Architecture](Architecture/README.md) for system design and internals.
- [Performance](Performance/README.md) for benchmark and performance guidance.

## Advanced Features (Supported)

*Still supported, just not the first day’s reading.*

- [Developer Guide](DEVELOPER_GUIDE.md) (advanced API sections)
- [API Reference](API/API_REFERENCE.md) (full reference; includes advanced and conditional surfaces)
- [Performance](Performance/README.md) (benchmark and tuning guidance)

## Conditional / Deferred Features

*May exist in the repo or docs but isn’t the default OSS story—read so you don’t cargo-cult sync/transport.*

- [Distributed Transport Deferred Status](Status/DISTRIBUTED_TRANSPORT_DEFERRED.md)
- [Sync Docs](Sync/README.md) - design and deferred transport context; not default OSS onboarding
- Telemetry and staging-related surfaces in source are conditional and should be treated as non-default runtime behavior

## Contributing And Project Policies

*Legal/social/process: how to contribute, behave, report issues, and what stability means.*

- [Contributing Guide](../CONTRIBUTING.md)
- [Code of Conduct](../CODE_OF_CONDUCT.md)
- [Security Policy](../SECURITY.md)
- [Support Policy](SUPPORT_POLICY.md)
- [API Stability](API_STABILITY.md)
- [Third-Party Notices](../THIRD_PARTY_NOTICES.md)

## Maintainer Docs

*CI lanes, releases, checklists—for people merging PRs or cutting releases.*

- [CI and Test Tiers](Testing/CI_AND_TEST_TIERS.md)
- [Testing Guide](TESTING_GUIDE.md)
- [Release Rollback Procedure](Status/RELEASE_ROLLBACK.md)
- [Open-Source Readiness Checklist](Status/OPEN_SOURCE_READINESS_CHECKLIST.md) (hosted CI expectations and local validation paths)
- [External Security Review Plan](Status/EXTERNAL_SECURITY_REVIEW_PLAN.md)
- [Master Documentation Index](MASTER_DOCUMENTATION_INDEX.md)
- [Agents Guide](AGENTS_GUIDE.md)

## Internal Analysis Docs

*Deep dives and positioning notes; interesting for maintainers, not required reading for app devs.*

- [Internal Docs Index](Internal/README.md)
- Analysis-style status artifacts are maintainer-facing and intentionally separated from user onboarding flow.

## Historical And Internal Material

*Old milestones, superseded designs, audits—useful for archaeology, not “current truth” unless linked from a maintained doc.*

- [Archive](Archive/) for historical release and design records (see [Archive README](Archive/README.md)).
- [Meta](Meta/README.md) for internal project-management documentation.
- [Audit](Audit/README.md) for audit snapshots and internal review artifacts.
- [Project](Project/README.md) for project status and assessment notes.
- [Tools](Tools/README.md) for tool-specific documentation.

Use the sections above as the default path. Archive and internal folders are useful for maintainers, but they are not the recommended starting point for new adopters.
