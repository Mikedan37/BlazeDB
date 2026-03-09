# ReferenceConsumer

Production-readiness example: boring lifecycle (open → write → read → observe → exit; reopen → verify).

Demonstrates:

1. Open/create a DB at a temp path  
2. Write a small dataset  
3. Read it back  
4. Call `observe()` and print snapshot at key points  
5. Simulate abrupt process exit after commit (phase 1 writes a flag and exits without `close()`)  
6. On second run: reopen, verify recovery, observe(), close and clean up  

No network, no background loops. Uses only sync APIs.

## One-command verification

Run phase 1 then phase 2 (two invocations). From repo root:

```bash
swift run ReferenceConsumer
swift run ReferenceConsumer
```

The example uses password `Ref-Consumer-Pwd-123` (must satisfy BlazeDB password-strength rules: uppercase, numbers, etc.).

**Expected output (phase 1):**

```
[phase1] inserted id=...
[phase1] read back count=1
[phase1] observe(): uptime=... health=OK tx committed=...
[phase1] wrote flag at ...; exiting without close (simulated abrupt exit after commit).
```

**Expected output (phase 2):**

```
[phase2] recovered record count=1
[phase2] observe(): uptime=... health=OK tx committed=...
[phase2] closed and cleaned up. Done.
```

If phase 2 reports `recovered record count=0` or exits with error, recovery or persistence is broken.

## Artifacts

- DB and flag live under `FileManager.default.temporaryDirectory/BlazeDB_ReferenceConsumer/`  
- Phase 2 removes the flag and artifact dir on success  

See `Docs/PRODUCTION_READINESS/REFERENCE_CONSUMER.md` for the contract this example satisfies.
