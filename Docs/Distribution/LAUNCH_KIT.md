# Distribution launch kit (drafts — not published)

Review-only drafts for maintainer use. **Do not post** until README, [SUPPORT_AND_LIMITATIONS.md](../Support/SUPPORT_AND_LIMITATIONS.md), and release tags match the claims below.

**Verified baseline (2026-10-16):** release `v2.8.2`, SPI **not** indexed (404), GitHub About still says “private” (see [GITHUB_METADATA_PROPOSAL.md](../Product/GITHUB_METADATA_PROPOSAL.md)), 23 stars, 145 open issues.

---

## 1. Show HN (draft)

**Title:** Show HN: BlazeDB – encrypted embedded database in Swift

**Description:**

BlazeDB is an MIT-licensed Swift document database that runs in-process on a local encrypted file: typed records, WAL-backed recovery, live queries, and a `blazedb` CLI/REPL on the same engine as apps. macOS and Linux are runtime-tested in CI; mobile is compile-tested; Android bridge is experimental.

It is intentionally not SQL and not multi-writer. We publish honest SQLite comparisons and benchmark methodology.

**Real use (verifiable):** [Seeker for iPhone beta](https://www.seekerscore.com/iphone) (local encrypted résumé + matches); job-queue persistence via `BlazeDBC` / Go cgo ([Examples/Go/hello_blazedb.go](../../Examples/Go/hello_blazedb.go)). See [REAL_WORLD_USAGE.md](../Adoption/REAL_WORLD_USAGE.md).

Try: clone → `swift run HelloBlazeDB`  
Docs: https://github.com/Mikedan37/BlazeDB#try-it  
Comparison: https://github.com/Mikedan37/BlazeDB/blob/main/Docs/GettingStarted/WHY_NOT_SQLITE.md

---

## 2. Swift Forums (update to existing showcase)

**Thread:** https://forums.swift.org/t/blazedb-swift-native-embedded-storage-engine-open-source/85813

**Suggested reply (short):**

Release **v2.8.2** is tagged; Linux getting started and support matrix docs are aligned with `HelloBlazeDB`. Swift Package Index listing is pending submission. If you evaluate BlazeDB for a single-process encrypted local store, issues with repro steps are welcome; curated starter tasks: `Docs/Contributing/STARTER_TASKS.md`.

---

## 3. Technical post outline (implementation story)

**Working title:** What broke when porting a Swift embedded database to Linux (and what we test now)

**Sections:**

1. Single-process `flock` and path defaults vs macOS  
2. `BLAZEDB_LINUX_CORE` feature gate — what is out of the Linux graph  
3. CI split: PR Tier0 on Linux vs nightly Tier1  
4. How to reproduce: `./dev tier0` and `swift run HelloBlazeDB`  
5. Explicit non-goals: sync, SQL, multi-writer  

**Canonical links:** `Docs/GettingStarted/LINUX_GETTING_STARTED.md`, `Docs/Testing/CI_AND_TEST_TIERS.md`

---

## 4. Awesome Swift (draft PR blurb)

**Category:** Database / Persistence

**Text:**

[BlazeDB](https://github.com/Mikedan37/BlazeDB) — Encrypted embedded document database for Swift (AES-GCM, WAL, typed Codable API, `blazedb` CLI). Single-process; macOS/Linux runtime CI. Honest SQLite comparison in-repo.

**Prerequisite:** confirm awesome-swift contribution rules before opening PR.

---

## 5. Swift Package Index submission

**Package URL:** `https://github.com/Mikedan37/BlazeDB`  
**Default branch:** `main`  
**Check before submit:** `swift build` + `swift test --filter BlazeDB_Tier0` green on macOS/Linux; README pin `from: "2.8.2"` matches latest tag.

Submit via SPI “Add a Package” flow after maintainer confirms build matrix.

---

## Distribution checklist (ordered)

| Step | Audience fit | Action |
|------|----------------|--------|
| 1 | All Swift devs | Apply [GITHUB_METADATA_PROPOSAL.md](../Product/GITHUB_METADATA_PROPOSAL.md) on GitHub |
| 2 | SPM users | SPI listing |
| 3 | Swift community | Forums update (§2) |
| 4 | Systems-curious Swift devs | Linux port post (§3) |
| 5 | HN readers | Show HN (§1) after metadata fixed |
| 6 | Persistence shoppers | awesome-swift PR (§4) |
| 7 | Portfolio | Ensure https://danylchukstudios.dev/work/blazedb links Getting Started + support matrix |

**Avoid:** subreddits that reject release posts without implementation depth; channels that expect sync/SQL features BlazeDB does not ship.
