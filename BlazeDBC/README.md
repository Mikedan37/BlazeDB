# BlazeDBC

Stable C ABI for embedding BlazeDB from any language that can call C.

| Item | Path |
|------|------|
| Header | [`include/blazedb.h`](include/blazedb.h) |
| Design | [`Docs/Architecture/C_ABI_BYTE_KV.md`](../Docs/Architecture/C_ABI_BYTE_KV.md) |
| Release | [`RELEASE.md`](../RELEASE.md) (v0.1.0) |
| C example | [`Examples/C`](../Examples/C) |

```bash
swift build -c release --product BlazeDBC
# → .build/release/libBlazeDBC.a
```

Do **not** use `BlazeDBAndroidBridge` / `blazedb_bridge_*` as the long-term ABI — that surface is JSON/demo-oriented for KMM samples.
