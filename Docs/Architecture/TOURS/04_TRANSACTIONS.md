# Tour 04 — Transactions

~20 minutes. Goal: separate “transaction API” from “buffered I/O” (they are not the same today).

## Start here

1. `BlazeDB/Exports/BlazeDBClient.swift` — `beginTransaction`, `commitTransaction`, `rollbackTransaction`, `performSafeWrite`
2. Same file — `createDurableTransactionBackups`, `restoreDurableTransactionBackupIfPresent`, `writeDurableTransactionState`
3. Tour [02_WRITE_PATH](02_WRITE_PATH.md) for insert sync behavior
4. `BlazeDB/Transactions/BlazeTransaction.swift` (higher-level helper; client APIs above are the primary path)
5. `Docs/Guarantees/SAFETY_MODEL.md` (may claim buffering — see #294)

## Follow this symbol

`beginTransaction` → persist/sync/checkpoint → durable backups + state `open` → snapshot maps  
→ mutations via `performSafeWrite` (skips indexMap snapshot backup only; **inserts still sync**)  
→ `commitTransaction` state `committing` → persist/sync/checkpoint → state `committed` → clear snapshots/backups  
→ or `rollbackTransaction` restore snapshots.

## Invariants

- Rollback restores pre-begin visible state.
- A crash in `open` or `committing` (before the post-checkpoint marker) restores the pre-transaction backup.
- A crash after the `committed` marker, while those backups are being removed, keeps the checkpointed database.
- Amortizing fsyncs to commit is desirable but **blocked on measurement #291** before design (#276).
- Never remove durability to make txn benches look like `insertMany`.

## Associated tests

- `BlazeDBTests/Tier0Core/Durability/TransactionDurabilityTests.swift` (`testCrashRecovery_NoPartialOutcomes_AllOrNothing`, `testStartupRestoresInterruptedTransactionBackup`)
- `BlazeDBTests/Tier1Core/Transactions/BlazeTransactionTests.swift`
- `BlazeDBTests/Tier0Core/Gate/CrashSurvivalTests.swift` (`testCrashDuringTransaction_UncommittedDataRolledBack`)

## Try it

```bash
./dev test TransactionDurabilityTests
./dev test BlazeTransactionTests
```

## Open work

#276, #277, #281, #285 (dead `transactionPagesWritten`), #294.

## Extension ideas

1. Doc honesty for write-through — **already tracked** (#294).
2. Amortized commit I/O — **already tracked** (#276 after #291).
3. Nested savepoints UX — **requires maintainer design**.
