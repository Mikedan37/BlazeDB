# GitHub repository metadata (proposal)

**Status:** Draft for maintainer review — **not applied** by automation (remote settings out of scope for agents).

**Verified live values (2026-10-16 via `gh repo view`):**

| Field | Current | Problem |
|-------|---------|---------|
| Description | “BlazeDB is a **private**, encrypted embedded database…” | “Private” reads as closed-source; should mean on-device |
| Homepage | `…/blob/main/Docs/README.md` | Internal index; weak landing for humans |
| Topics | database, embedded-database, swift, android, encryption, ios, key-value-store, linux, macos, wal | Missing swiftui, spm, document-database, local-first, cli |
| Stars | 23 | — |
| SPI | 404 | Not listed |

---

## Proposed description (GitHub About)

```
Open-source Swift embedded document database: AES-256-GCM pages, WAL recovery, Codable queries, blazedb CLI. Single-process; macOS/Linux CI. MIT.
```

(Under 350 characters; no “private”; disambiguates from server/GPU “Blaze” products.)

---

## Proposed homepage URL

```
https://danylchukstudios.dev/work/blazedb
```

Alternative once a docs site exists: project-owned `https://…` with the same content as Getting Started + support matrix.

---

## Proposed topics (add)

- `swiftui`
- `swift-package-manager`
- `document-database`
- `local-first`
- `codable`
- `cli`
- `swift6`

Keep existing topics unless GitHub topic limit requires trimming (prefer dropping generic `database` last).

---

## Social preview

Upload a repository social image: product name + “Swift embedded · encrypted · WAL · CLI” (no performance superlatives).

---

## Rationale (visitor questions)

| Question | Answered by |
|----------|-------------|
| Is it open source? | Description says “Open-source”, MIT badge in README |
| What is it? | “Swift embedded document database” |
| Is it the GPU SQL engine? | Wording avoids “BlazingSQL”; README disambiguation |
| Where do I start? | Homepage → case study → GitHub Getting Started |
