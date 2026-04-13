**Quick rules:** [CONTRIBUTING.md — PR expectations](CONTRIBUTING.md#pr-expectations) (one branch, `preflight`, list commands, docs with behavior, squash merge).

## Summary

- What changed?
- Why was it needed?

## Scope

- In scope:
- Out of scope:

## Validation

List **exact** commands you ran (copy-paste from your terminal):

```bash
./Scripts/preflight.sh
# add anything else (e.g. swift test --filter …)
```

## Checklist

- [ ] One branch = one concern
- [ ] `git status` / `git diff` reviewed for containment
- [ ] Docs updated in this PR if behavior or public usage changed
- [ ] `Docs/SYSTEM_MAP.md` / `Docs/Testing/CI_AND_TEST_TIERS.md` updated **only if** this PR changes material surface, architecture, or CI/tier semantics (see PR expectations)
- [ ] CI checks pass
