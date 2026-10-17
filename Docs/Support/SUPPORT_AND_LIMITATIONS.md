# Support and limitations

Verified against `Package.swift`, `.github/workflows/ci.yml`, and [COMPATIBILITY.md](../COMPATIBILITY.md) on branch `main`. This page is the **public contract summary** for evaluators. Detail lives in linked docs; internal status folders may be historical.

**Current release tag:** `v2.8.2` ([RELEASE.md](../../RELEASE.md)). **Swift Package Index:** not listed as of 2026-10-16 (404 at `swiftpackageindex.com/Mikedan37/BlazeDB`); submission is a maintainer action ([launch kit](../Distribution/LAUNCH_KIT.md)).

## Platform matrix

| Platform | Declared in Package.swift | Runtime engine tests in PR CI | Notes |
|----------|---------------------------|-------------------------------|--------|
| macOS 15+ | Yes | Yes (Tier0, Tier1, CLI) | Primary contributor path |
| Linux (incl. aarch64) | Yes | Yes (Tier0 on PR; Tier1 on nightly) | `BLAZEDB_LINUX_CORE` disables some advanced surfaces |
| iOS, watchOS, tvOS, visionOS | Yes | Compile + KMM iOS simulator smoke | Not full host Tier0 on device in PR gate |
| Android | Bridge products only | Cross-compile + KMM emulator smoke | **Experimental** — no published Maven/CocoaPods SDK ([android-status.md](../android-status.md)) |

Compilation on a platform does **not** imply the same runtime test depth as macOS/Linux unless CI lists a runtime job ([CI_AND_TEST_TIERS.md](../Testing/CI_AND_TEST_TIERS.md)).

## Product scope (default OSS package)

| Capability | Status | Evidence |
|------------|--------|----------|
| Encrypted embedded storage (AES-256-GCM pages, PBKDF2 key derivation) | **Shipped** | [KEY_MANAGEMENT_AND_COMPATIBILITY.md](../Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md) |
| WAL-backed crash recovery (default path) | **Shipped** | [DURABILITY_MODE_SUPPORT.md](../Status/DURABILITY_MODE_SUPPORT.md) |
| Typed document API (`BlazeStorable`, namespace queries) | **Shipped** | [PublicFacadeAPI.swift](../../BlazeDB/Exports/PublicFacadeAPI.swift), `HelloBlazeDB` |
| Single-owner file (one engine writer per path; daemon/queue OK) | **Shipped** (by design) | [WHY_SINGLE_WRITER.md](../Guarantees/WHY_SINGLE_WRITER.md) |
| SQL | **Not supported** | Fluent Swift/document APIs only |
| Multi-device sync / distributed transport | **Deferred** from default package | [DISTRIBUTED_TRANSPORT_DEFERRED.md](../Status/DISTRIBUTED_TRANSPORT_DEFERRED.md) |
| Row-level security (RLS) | **Implemented**; known issues [#334–#337](https://github.com/Mikedan37/BlazeDB/issues/334) **closed** 2026-08-27 per tracker | [RELEASE.md](../../RELEASE.md) v2.8.2 notes; regression tests in tree — **not** a substitute for independent security review |
| Independent third-party security audit | **Planned / tracked**, not complete | [EXTERNAL_SECURITY_REVIEW_PLAN.md](../Status/EXTERNAL_SECURITY_REVIEW_PLAN.md), [SECURITY.md](../../SECURITY.md) |
| C ABI (`BlazeDBC`) | **Shipped** with documented header | [C_ABI_BYTE_KV.md](../Architecture/C_ABI_BYTE_KV.md) |

## When not to use BlazeDB

- **Two or more processes writing the same file without a single owner** (exclusive lock is intentional). On macOS/Linux, use one daemon/service or worker with a write queue; see [WHY_SINGLE_WRITER.md](../Guarantees/WHY_SINGLE_WRITER.md). iOS apps normally embed BlazeDB in-process only.
- Network filesystems for the database file
- A **built-in** networked database product (BlazeDB is embedded; you provide any server/queue layer)
- SQL reporting or ad hoc analytics
- Kotlin-first Android without owning the Swift bridge
- Requirements that need completed external audit reports today

See also the README [“Do not use”](../../README.md#do-not-use-blazedb-when-you-need) section.

## Security wording

- Use of **Apple CryptoKit / swift-crypto** and documented KDF parameters is **implementation fact**, not a guarantee of freedom from defects.
- Closing GitHub issues with tests is **project verification**, not **independent review**.
- Report vulnerabilities via [SECURITY.md](../../SECURITY.md), not public issues.

## Issue tracker (definitions)

As of 2026-10-16: **145 open issues** on `Mikedan37/BlazeDB` (GitHub API, issues only — not PRs). Many are documentation, platform experimental, or maintainer-sensitive correctness work. The [`good first issue`](https://github.com/Mikedan37/BlazeDB/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) label is **broader** than beginner-safe work; use [STARTER_TASKS.md](../Contributing/STARTER_TASKS.md) for curated entry points.
