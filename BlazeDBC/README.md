# BlazeDBC

Stable C ABI for embedding BlazeDB from any language that can call C.

- Header: [`include/blazedb.h`](include/blazedb.h)
- Design / compatibility rules: [`Docs/Architecture/C_ABI_BYTE_KV.md`](../Docs/Architecture/C_ABI_BYTE_KV.md)

SwiftPM product: `BlazeDBC` (static library).

```text
swift build --product BlazeDBC
```

Do not use `BlazeDBAndroidBridge` / `blazedb_bridge_*` as the long-term ABI — that surface is JSON/demo-oriented for KMM samples.
