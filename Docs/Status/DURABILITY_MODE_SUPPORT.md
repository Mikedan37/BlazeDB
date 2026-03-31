# Durability Mode Support Policy

This policy describes supported durability behavior in current BlazeDB releases.

## Default runtime path (OSS / `BlazeDBClient`)

The usual entry point is `BlazeDBClient`, which constructs `PageStore` with default parameters: **`enableWAL: true`** and **`walMode: .legacy`**. In that mode, **binary page-level WAL** (`WriteAheadLog`) is used: entries are appended and replayed during `PageStore` initialization for crash recovery. **High-level NDJSON “transaction log” files are not part of normal document durability** for this path; legacy NDJSON sidecar files may be removed on open (`BlazeDBClient.removeLegacyNDJSONTransactionLogFilesIfPresent()`).

For operators using `BlazeDBManager` or other tooling, note that manager-style helpers can replay any existing `txn_log*.json` files as plaintext page-level journals for migration or advanced recovery, but those artifacts are not created by the default `BlazeDBClient` path and are outside the encrypted binary WAL contract.

### Default durability contract (legacy WAL mode)

For the default `BlazeDBClient` path, durability is provided by the **legacy binary write-ahead log** at the **page** level:

- **Write ordering**
  - For each page write, the encrypted page image is appended to the binary WAL **before** the main data file is updated.
  - The WAL entry is fsync’d to disk before the page write is considered committed.
  - The main file is then written and fsync’d.
- **Crash recovery**
  - On open, `PageStore` replays any remaining WAL entries and reapplies the corresponding page images to the main file.
  - WAL replay is idempotent for committed streams: reapplying the same committed WAL sequence converges to a single final state.
  - Truncated or corrupt tail entries are detected (magic/length/CRC) and replay stops at the last valid entry.
- **Metadata and visibility**
  - Persisted record visibility is determined by the catalog/metadata (`StorageLayout.indexMap`), not by scanning raw pages.
  - A record is considered **published** only after both:
    1. Its page(s) are durably written (via WAL + main fsync), and
    2. The metadata has been updated and saved.
  - If an insert fails (for example, a metadata save error), `BlazeDBClient.performSafeWrite` restores the in-memory index map; the record is not visible via normal APIs, and reopen will not list it unless the metadata actually contains an entry.

### Large records and overflow pages (publish-last semantics)

Large records that do not fit in a single page are stored using an **overflow chain**:

- Overflow pages are allocated and written **before** the main page. These pages are **not** individually appended to the legacy binary WAL.
- The main page stores a committed overflow pointer and checksum (`OverflowReferenceV2`); this main page **is** WAL-protected and acts as the **publish point** for the chain.
- On crash **before** the main page is durably written, it is possible to have orphan overflow pages on disk that are not referenced by any catalog entry. These pages are not visible via normal APIs and may be reclaimed by garbage collection or vacuum.
- On crash **after** the main page and metadata are durably written, recovery treats the record as committed and uses the main page pointer+checksum to reconstruct the overflow chain. Any WAL replay operates on the main page image and does not log overflow pages separately.

This means:

- There is **no catalog-visible “torn” record** after reopen for the default path, assuming current tests pass.
- The durability story is **publish-last at the main page/catalog level**: overflow data becomes part of the logical record only once the main page and metadata have been persisted.
- Operators should be aware that crashes can leave **ghost/orphan overflow pages** that are not referenced by the catalog; these affect disk usage, not logical correctness.

## Modes in codebase

- **Legacy durability path (default for `BlazeDBClient`):** `WriteAheadLog` + encrypted page writes. WAL replay runs during `PageStore` init.
- **Unified durability path (optional):** `DurabilityManager` + `RecoveryManager` — selected by constructing `PageStore` with `walMode: .unified`. Use one mode consistently per database file.

## Configuration summary

| Mode | Default for `BlazeDBClient`? | Who uses it | Notes |
|------|------------------------------|-------------|--------|
| Legacy binary WAL (`WALMode.legacy`) | **Yes** | Default `PageStore(fileURL:key:)` | Crash recovery via WAL replay in `PageStore.init` |
| Unified WAL (`WALMode.unified`) | **No** (opt-in) | Callers that pass `walMode: .unified` | Alternative WAL implementation; tests and advanced setups |
| Client NDJSON transaction log | **Not used for durability** | N/A for normal CRUD | Legacy files may be deleted on open; not a replay source for document ops |

## Support position

- **Production defaults** for typical `BlazeDBClient` usage are **legacy binary WAL** as described above.
- **Unified WAL** is supported for deployments that explicitly opt in and validate recovery behavior for their workload.
- **Do not mix durability modes** on the same database file; migrate in a controlled window with backup and verification.

## Operational guidance

1. Use a single durability mode consistently per database file / deployment.
2. Validate crash-recovery and restore workflows before production rollout.
3. Treat mixed legacy/unified migration windows as controlled operations with backup and post-migration verification.
