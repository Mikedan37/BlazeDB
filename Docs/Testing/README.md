# Testing

Canonical testing docs:
- CI_AND_TEST_TIERS.md
- TEST_COVERAGE_DOCUMENTATION.md
- GC_TEST_COVERAGE.md

Policy note:
- `CI_AND_TEST_TIERS.md` is the authoritative home for lane contracts, runtime budgets, enforcement rollout, and migration/exemption rules.

Cadence (summary): PR gate (`ci.yml`) → nightly bounded confidence (`nightly.yml`) → weekly **`deep-validation.yml`** as **delta-only** (long-tail tiers not already owned by PR + nightly). See `CI_AND_TEST_TIERS.md` for exact jobs and filters.

