# Roadmap backlog

Detailed candidates that support [`ROADMAP.md`](../../ROADMAP.md) without turning the public roadmap into a landfill. Prefer issues/milestones for concrete delivery commitments.

| Doc | Role |
|-----|------|
| [`ROADMAP.md`](../../ROADMAP.md) | Committed product priorities |
| **This file** | Verified gaps worth retaining |
| [`PRODUCT_AUDIT.md`](PRODUCT_AUDIT.md) | Full evidence and inventory |

Source audit: [`PRODUCT_AUDIT.md`](PRODUCT_AUDIT.md). Hygiene pass: 2026-07-26.

## Correctness and compatibility

| ID | Candidate | Exit criteria sketch |
|----|-----------|----------------------|
| C1 | Prior-release DB fixtures (v2.7.x → current) | CI opens tagged fixtures; read + one write path (**Now**) |
| C2 | WAL fixture compatibility | Replay fixtures from supported WAL generations |
| C3 | Overflow orphan reclaim verification | Test asserts orphans are invisible and reclaimable |
| C4 | Fail-loud typed bulk decode option | API or flag returns errors instead of silent drops |

## Contributor safety

| ID | Candidate | Exit criteria sketch |
|----|-----------|----------------------|
| S1 | Storage-change checklist | **Done** — [STORAGE_CHANGE_CHECKLIST.md](../Contributing/STORAGE_CHANGE_CHECKLIST.md) |
| S2 | Benchmark-change checklist | Require methodology + env capture for result doc edits |
| S3 | Security-sensitive / crypto-change checklist | Crypto/KDF/session/password paths; required validation commands |
| S4 | Issue template storage/WAL fields | Optional fields on bug form |
| S5 | GitHub `config.yml` security contact_links | Points to SECURITY.md email / reporting path |

## Release and FFI

| ID | Candidate | Exit criteria sketch |
|----|-----------|----------------------|
| R1 | Curated BlazeDBC artifact (lib + header + checksum) | Attached to GitHub Release; smoke-tested (**Now**) |
| R2 | Linux `.so` publish / release verification | Same layout as macOS dylib lane; release job proves artifact |
| R3 | ABI symbol snapshot / diff | Fail release if published symbols remove/change |
| R4 | CI compile+link `Examples/C/hello_blazedb.c` | PR or release gate (**Now**, with R1) |
| R5 | Attach curated RELEASE.md body | Prefer over raw `git log` subjects |
| R6 | Versioned Homebrew formula | Or explicit “head-only” statement in RELEASE |

## C ABI evolution (additive only)

| ID | Candidate | Exit criteria sketch |
|----|-----------|----------------------|
| F1 | `blazedb_last_error` | Hosts can diagnose open failures |
| F2 | Iterator / prefix scan | Matches reserved `BlazeDBIterator` story |
| F3 | Batch put/get/delete | Fewer round trips for managers |
| F4 | Optional transaction begin/commit/abort | Only if semantics match Swift client |

## Go packaging

| ID | Candidate | Exit criteria sketch |
|----|-----------|----------------------|
| G1 | Checked-in `Examples/Go` cgo smoke | Builds from clean checkout; open/put/get/close (**Now**) |
| G2 | CI Go E2E against built `BlazeDBC` | Gates releases that touch BlazeDBC (**Now**, with G1) |
| G3 | Separate `blazedb-go` module | SemVer + compatibility policy with BlazeDB tags |
| G4 | Idiomatic errors / finalizers / context | Document concurrency limits |

## Performance evidence

| ID | Candidate | Exit criteria sketch |
|----|-----------|----------------------|
| P1 | Short CI regression lane | Cold open + one insert/read; thresholds with slack |
| P2 | Single authoritative bench entry doc | Deprecate dual-script confusion |
| P3 | Wire `stats()` cache-hit metrics | Correct the field or remove it from the public surface |

## Developer tooling / CLI DX

| ID | Candidate | Exit criteria sketch |
|----|-----------|----------------------|
| D1 | `blazedb --version` | Prints package/SemVer consistently with RELEASE |
| D2 | Structured JSON for `BlazeDump` / `BlazeInfo` | Machine-readable output parity with REPL where useful |
| D3 | `./dev` host/tool architecture mismatch detection | Clear message + remediation (`arch -arm64 …` or rebuild) instead of opaque xctest loader errors |

## Platforms

| ID | Candidate | Exit criteria sketch |
|----|-----------|----------------------|
| L1 | Soften COMPATIBILITY iOS wording | **Done** — compile-tested / declared; matches README |
| L2 | Optional iOS Simulator Tier0 | Named Phase 2 in CI docs |
| L3 | Linux PR BlazeDBC smoke | Or document nightly-only clearly next to FFI |

## Documentation residue

| ID | Candidate | Exit criteria sketch |
|----|-----------|----------------------|
| Doc1 | Remove docs implying production B+ readiness | Public guides match stub quarantine (**Now**) |
| Doc2 | CLI Doctor/Dump/Info dispatch honesty | Docs/`--help` match executables (**Now**) |
| Doc3 | Schema / migration canonical entries | Advanced table points at one guide each (**Now**) |

## Intentionally deferred / reject (detail)

| Item | Reason |
|------|--------|
| Distributed default OSS | Deferred until public deps + CI |
| KMM production SDK claim | Experimental; packaging frozen until demand |
| Extra language wrappers before Go | No packaging pattern yet |
| Cost-based optimizer / marketing features | Not evidenced as near-term need |
| In-place key rotation | Large; export/reimport exists; needs design |
| Ceremonial full runtime CI for every Apple OS | Prefer targeted value |
