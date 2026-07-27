# Tour 01 — Open and recovery

~15 minutes. Goal: follow a database from password to a live handle, including crash leftovers.

## Start here

1. `BlazeDB/Exports/PublicFacadeAPI.swift` — `BlazeDB.open`
2. `BlazeDB/Exports/BlazeDBClient+EasyOpen.swift`
3. `BlazeDB/Exports/BlazeDBClient.swift` — `init`, salt, `resolveEncryptionKey`, `restoreDurableTransactionBackupIfPresent`
4. `BlazeDB/Crypto/KeyManager.swift`
5. `BlazeDB/Storage/PageStore.swift` — `init` + WAL replay
6. `BlazeDB/Storage/WriteAheadLog.swift` — `replay`
7. `BlazeDB/Core/DynamicCollection.swift` — init / `StorageLayout.loadSecure`

## Follow this symbol

`BlazeDB.open` → `BlazeDBClient.init` → `loadOrCreateKDFSalt` → `KeyManager.getKey` → `restoreDurableTransactionBackupIfPresent` → `PageStore.init` → `_replayLegacyWAL` → `DynamicCollection.init` → ready client.

## Invariants

- Open always derives or restores a key; empty password is rejected on public paths.
- Default durability path uses binary WAL replay inside `PageStore` init.
- Interrupted client-transaction backups are considered **before** trusting on-disk state (#277).

## Associated tests

- `BlazeDBTests/Tier1Core/API/InitAPITests.swift`
- `BlazeDBTests/Tier1Core/Security/KeyManagerTests.swift`
- `BlazeDBTests/Tier0Core/Durability/TransactionDurabilityTests.swift` (`testStartupRestoresInterruptedTransactionBackup`)
- `BlazeDBTests/Tier0Core/Gate/LifecycleTests.swift`
- `BlazeDBTests/Tier1Core/Persistence/CrashRecoveryTests.swift`

## Try it

```bash
swift run HelloBlazeDB
./dev test InitAPITests
```

## Open work

#270 / #271 (open cost / KDF attribution), #277 (txn backup restore window), #293 (durability docs).

## Extension ideas

1. Clearer open-error messages — **safe untracked exploration** (keep secrets out of messages).
2. Document session warm-path vs cold KDF — **already tracked** (#270/#271).
3. Change KDF algorithm — **requires maintainer design**.
