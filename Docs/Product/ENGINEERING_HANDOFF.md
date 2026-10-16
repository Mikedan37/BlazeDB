# Engineering handoff — public presentation pass

**Branch:** `cursor/public-presentations-4baf`  
**Date:** 2026-10-16  
**Scope:** Discoverability, first-use, docs credibility, contributor entry — no engine features.

## Verified baseline (sources)

| Fact | Source |
|------|--------|
| Latest release tag | `v2.8.2` — `git tag`, [RELEASE.md](../../RELEASE.md) |
| `VERSION` file | Aligned to `2.8.2` (was `2.8.1`) |
| Open GitHub issues | **145** — `gh issue list --state open --limit 500` (issues only) |
| Stars | **23** — `gh repo view` |
| GitHub About | Says “**private**” embedded DB — [GITHUB_METADATA_PROPOSAL.md](GITHUB_METADATA_PROPOSAL.md) |
| Swift Package Index | **404** — HTTP check 2026-10-16 |
| RLS #334–#337 | **CLOSED** 2026-08-27 — `gh issue view`; v2.8.2 release notes claim fixes |
| External security audit | Planned, not complete — [EXTERNAL_SECURITY_REVIEW_PLAN.md](../Status/EXTERNAL_SECURITY_REVIEW_PLAN.md) |
| Canonical first example | [HelloBlazeDB](../../Examples/HelloBlazeDB/main.swift) |

## Implemented in this pass

- README opening: positioning, BlazingSQL disambiguation, support/compare links, restrained star note
- `HelloBlazeDB`: close + reopen persistence check
- Linux getting started rewritten (removed stale `BlazeDBClient` quickstart)
- Support/limitations matrix, comparison hub, launch kit drafts, GitHub metadata proposal
- Contributor: STARTER_TASKS, label maintenance proposal, CONTRIBUTING 30-minute path
- Version pin drift fixes (Developer Guide, AGENTS_GUIDE, docc, MCP)
- Examples catalog: AshPile as application-shaped sample (not “production adoption”)
- Audit/adoption banners pointing evaluators to support matrix

## Real-world usage (2026-10-17 follow-up)

| Integration | Evidence |
|-------------|----------|
| Seeker iOS (TestFlight) | Public page: https://www.seekerscore.com/iphone — encrypted local résumé PDF + profile + matches |
| Seeker-shaped tests | `TransactionThrowRollbackTests`, `CrossContextKDFIterationTests` (comments) |
| Go job worker | Maintainer-operated queue program via cgo; minimal smoke: `Examples/Go/hello_blazedb.go` |

Documented in [REAL_WORLD_USAGE.md](../Adoption/REAL_WORLD_USAGE.md).

## Measurement plan (baseline only)

Use aggregate signals available to maintainers; do not equate stars with active users.

| Signal | Access | Use |
|--------|--------|-----|
| GitHub traffic / referrers | Repo Insights | See if SPI, Forums, or case study sends clones |
| Stars over time | Insights | Secondary; after metadata/SPI fixes |
| SPI referrals | SPI dashboard (after listing) | SPM discovery |
| First-time contributor PRs | GitHub PRs | Success = merged doc/CLI fixes from new authors |
| Integration reports | Issues/Discussions | Track “HelloBlazeDB works in my app” with repro |

**Behavioral success:** clean `swift run HelloBlazeDB` or SPM pin `2.8.2` open/put/query in a consumer project; independent developer confirms persistence.

## External actions (awaiting maintainer)

1. Apply [GITHUB_METADATA_PROPOSAL.md](GITHUB_METADATA_PROPOSAL.md) on GitHub  
2. Submit package to Swift Package Index ([LAUNCH_KIT.md](../Distribution/LAUNCH_KIT.md))  
3. Execute [LABEL_MAINTENANCE_PROPOSAL.md](../Contributing/LABEL_MAINTENANCE_PROPOSAL.md) on issues  

## Review cross-check (Phase 3)

- [ ] README install pin matches RELEASE.md  
- [ ] HelloBlazeDB APIs exist (`close`, `open(at:)`)  
- [ ] No claim of completed external audit  
- [ ] RLS described as closed issues + tests, not “certified secure”  
- [ ] Linux guide matches HelloBlazeDB  
