# BlazeDBExtraTests

Swift package that depends on the root `BlazeDB` package and contains **Tier 2**, **Tier 3** (heavy + destructive), and **`DistributedSecuritySPMTests`**.

This keeps the root package’s default `swift test` graph small: CI and `swift test --filter BlazeDB_Tier0` no longer compile Tier 3 or unrelated SPM harnesses.

```bash
cd BlazeDBExtraTests
swift test --filter BlazeDB_Tier2
swift test --filter BlazeDB_Tier3_Heavy
```
