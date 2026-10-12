# Durability Mode Support Policy

This policy describes supported durability behavior in current BlazeDB releases.

## Default runtime path (OSS / `BlazeDBClient`)

The usual entry point is `BlazeDBClient`, which constructs `PageStore` with default parameters: **`enableWAL: true`** and **`walMode: .legacy`**. In that mode, **binary page-level WAL** (`WriteAheadLog`) is used: entries are appended and replayed during `PageStore` initialization for crash recovery. **High-level NDJSON “transaction log” files are not part of normal document durability** for this path; legacy NDJSON sidecar files may be removed on open (`BlazeDBClient.removeLegacyNDJSONTransactionLogFilesIfPresent()`).

For operators using `BlazeDBManager` or other tooling, note that manager-style helpers can replay any existing `txn_log*.json` files as plaintext page-level journals for migration or advanced recovery, but those artifacts are not created by the default `BlazeDBClient` path and are outside the encrypted binary WAL contract.

### Default durability contract (legacy WAL mode)

For the default `BlazeDBClient` path, durability is provided by the **legacy binary write-ahead log** at the **page** level:

- **Write ordering**
- For each page write, the encrypted page image is appended to the binary WAL **before** the main data file is updated.
- WAL entries may be appended with deferred durability and made durable at a later explicit sync boundary; a page write is considered committed only after its WAL data reaches that durability boundary.
- The corresponding main-file writes may occur before that boundary; `PageStore.synchronize()` fsyncs the WAL first and then the main data file before catalog or metadata publication.
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

- Overflow pages are allocated and written to the main file **before** the main page. Each overflow page is also appended to the same legacy WAL group as the main page. A freed record page can be reused as an overflow page; replay would otherwise copy that page's older record image back over the chain.
- The main page stores a committed overflow pointer and checksum (`OverflowReferenceV2`) and is the publish point for the chain. The WAL commit record covers the overflow pages and the main page together.
- On crash **before** that commit record is durable, replay ignores the open group. Orphan overflow bytes may remain on disk. They are not referenced by the catalog and are not visible via normal APIs.
- On crash **after** the commit record and the catalog are durable, replay writes every page in the group, including overflow pages. The record reads back through the main-page pointer and checksum.

This means:

- There is **no catalog-visible “torn” record** after reopen for the default path, assuming current tests pass.
- The durability story is **publish-last at the main page/catalog level**: overflow data becomes part of the logical record only once the main page and metadata have been persisted.
- Operators should be aware that crashes can leave **ghost/orphan overflow pages** that are not referenced by the catalog; these affect disk usage, not logical correctness.

## Modes in codebase

### Client transaction rollback

`BlazeDBClient.rollbackTransaction()` restores baseline records across their
original overflow pages, including records deleted during the transaction. It
also restores the free-page list so subsequent inserts cannot overwrite those
restored records. The change uses the existing file format and default legacy
WAL mode; existing databases do not require migration.

If rollback itself fails, the durable transaction backup remains available.
The client clears its in-memory transaction state and refuses a new transaction
until the database is reopened, rather than overwriting the recovery backup.
Reopening invokes the existing durable transaction recovery path. Callers must
not treat a failed rollback as a successful save or delete the backup.

After a rollback fails, the client rejects guarded reads, transactions, ordinary CRUD writes, index creation and explicit persistence until it is closed and reopened. Closing skips the normal client flush; reopening restores the durable transaction backup before accepting new writes. The sync and async transaction helpers, `performTransaction`, and import restoration report `BlazeTransactionRecoveryError` when both the operation and rollback fail, retaining both underlying errors. A successful rollback preserves the original operation error.

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
