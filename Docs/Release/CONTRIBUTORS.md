# BlazeDB contributors

How we credit people on releases, changelogs, and social posts.

## This release vs all-time

| Scope | What it means | Where it shows up |
|-------|----------------|-------------------|
| **This release** | Commit authors between the previous tag and the new tag | GitHub Release **Contributors (this release)** (auto-generated in CI) |
| **Ecosystem (all-time)** | Humans who landed merged work in the repo, even if their commits shipped in an earlier tag | **Ecosystem contributors** blurb on releases, CHANGELOG **Thanks**, [ECOSYSTEM_THANKS.md](ECOSYSTEM_THANKS.md) |

Do not drop all-time names on a big announcement just because they had no commits in the latest patch window.

## All-time humans (non-bot)

| GitHub | Notable work |
|--------|----------------|
| [@Mikedan37](https://github.com/Mikedan37) | Maintainer; core engine, Linux CI/portability, docs, security hardening |
| [@Nitjsefnie](https://github.com/Nitjsefnie) | Cache isolation (LazyField, JOIN, query), `notEquals` semantics, graph windows ([#377](https://github.com/Mikedan37/BlazeDB/pull/377)) |
| [@VedantMadane](https://github.com/VedantMadane) | SQL `RANK()` tie handling ([#472](https://github.com/Mikedan37/BlazeDB/pull/472)) |
| [@finagolfin](https://github.com/finagolfin) | Android build portability ([#21](https://github.com/Mikedan37/BlazeDB/pull/21)) |
| [@yu010101](https://github.com/yu010101) | CI test harness fixes ([#440](https://github.com/Mikedan37/BlazeDB/pull/440)) |
| [@jlonsdalen](https://github.com/jlonsdalen) | Durability docs ([#319](https://github.com/Mikedan37/BlazeDB/pull/319)) |

`Peter Z` is the same GitHub account as **@Nitjsefnie** (alternate author string on some commits). Credit **@Nitjsefnie** once.

## Linux vs Android

- **Linux** platform support and CI are mostly maintainer-led (see changelog entries for Linux CI #28/#29 and portability work).
- **@finagolfin** landed **Android** cross-build fixes, not the Linux port. Still worth naming on ecosystem posts.

## Release workflow

`.github/workflows/release.yml` appends [ECOSYSTEM_THANKS.md](ECOSYSTEM_THANKS.md) after the per-release contributor list. Edit that file when adding a new long-term contributor.

## LinkedIn / social (copy/paste)

**This release (v2.8.2 example):**

> Thanks to everyone who shipped in 2.8.2: @Nitjsefnie @VedantMadane @yu010101 @jlonsdalen — cache isolation, RLS hardening, RANK() ties, safer CLI passwords, and docs that match the real crypto story.

**Add ecosystem line:**

> Standing thanks to earlier contributors including @finagolfin (Android portability) and everyone who reviewed and filed issues.
