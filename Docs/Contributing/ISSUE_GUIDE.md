# Finding and claiming issues

This guide helps outside contributors pick work that matches BlazeDB’s supported product and risk model.

**Supported OSS product:** Swift embedded engine + CLI/operator tools + dynamic BlazeDBC C ABI.  
**Not default product:** distributed sync. **Experimental / deferred:** Android/KMM, Experimental B+.

For product priorities see [`ROADMAP.md`](../../ROADMAP.md). For tracker health see [`Docs/Product/ISSUE_TRACKER_AUDIT.md`](../Product/ISSUE_TRACKER_AUDIT.md).

## How to read the open issue count

Dozens of open issues does **not** mean every ticket is a release blocker. The tracker deliberately keeps verified defects visible rather than hiding them for cosmetics. Rough buckets:

| Bucket | Typical labels | Who owns it |
|--------|----------------|-------------|
| Good first issues | `good first issue`, often `documentation` | New contributors |
| Help wanted | `help wanted` | Outside contributors with maintainer backup |
| Maintainer-owned correctness | `bug` + `durability` / `concurrency` / `High Priority` | Maintainers / experienced systems contributors |
| Needs design | `needs design` | Decision before code |
| Measurement / packaging | `performance`, `ci`, `linux`, `Portability` | After evidence or platform gates |
| Experimental / later | Android, KMM, deferred sync | Not the default product path |

Release-oriented focus is summarized in [`ROADMAP.md`](../../ROADMAP.md) (**Maintainer priorities** / **Now**) and the README.

## Finding work

| Filter | Meaning |
|----------|---------|
| [`good first issue`](https://github.com/Mikedan37/BlazeDB/labels/good%20first%20issue) | Safe, bounded, usually docs/tooling. No storage-format, ABI, crypto behavior, auth semantics, or concurrency redesign. |
| [`help wanted`](https://github.com/Mikedan37/BlazeDB/labels/help%20wanted) | Maintainer wants help; may still need review on approach. |
| [`durability`](https://github.com/Mikedan37/BlazeDB/labels/durability) / [`concurrency`](https://github.com/Mikedan37/BlazeDB/labels/concurrency) / [`needs design`](https://github.com/Mikedan37/BlazeDB/labels/needs%20design) | Correctness-sensitive work — usually **not** beginner. Prefer these over a generic priority museum label. |
| Roadmap Now items | Linked from [`ROADMAP.md`](../../ROADMAP.md) (fixtures, Go smoke, BlazeDBC, schema guide, CLI honesty). |

**Start here (safe docs/tooling):** issues labeled `good first issue` + `documentation`.  
**Avoid as a first PR:** anything touching WAL commit order, encryption, RLS enforcement, or C ABI symbols unless you already know the subsystem.

## Label meanings (compact)

- **Type:** `bug`, `documentation`, `enhancement`, `cleanup`, `tech-debt`, `security`, `ci`, `tests`
- **Subsystem:** `storage-engine`, `reliability`, `concurrency`, `api-correctness`, `typed-store`, `linux`, `Portability`
- **Contributor:** `good first issue`, `help wanted`

Security vulnerabilities: **do not** open a public issue — follow [`SECURITY.md`](../../SECURITY.md).

## How to claim an issue

1. Comment that you are taking it (no formal assignment required).
2. Keep the PR small: one concern, one validation story.
3. Link the issue in the PR description.
4. If blocked > a few days, comment so others can continue.

## Expected PR size

Prefer PRs that change a **small file footprint** and are reviewable in one sitting. Split storage-format work from docs-only work.

## Validation commands

```bash
./dev help
./dev tests [search]    # discover focused tests
./dev test <filter>
arch -arm64 ./dev tier0 # on Apple Silicon if host arch mismatches
swift run HelloBlazeDB
```

Storage / WAL / encryption / recovery changes: also follow [`STORAGE_CHANGE_CHECKLIST.md`](STORAGE_CHANGE_CHECKLIST.md).

List the exact commands you ran in the PR body.

## Warnings (maintainer review required)

| Change type | Do not treat as good-first |
|-------------|----------------------------|
| Storage format / WAL / page layout | Requires checklist + recovery tests |
| Cryptographic parameters or KDF | Security review |
| Authorization / RLS semantics | Design first; docs-only fixes are OK |
| C ABI / exported symbols | Compatibility + release impact |
| Concurrency / queue barriers | Easy to introduce deadlocks |
| Benchmark claims / LATENCY numbers | Measure before rewriting headlines |

## What makes a good issue body

Every actionable issue should answer: what is wrong, where (paths), current vs expected, acceptance checklist, validation commands, and scope boundaries. Prefer evidence over speculation.

## Related docs

- [`CONTRIBUTING.md`](../../CONTRIBUTING.md)
- [`COMPATIBILITY.md`](../COMPATIBILITY.md)
- [`Docs/Testing/CI_AND_TEST_TIERS.md`](../Testing/CI_AND_TEST_TIERS.md)
