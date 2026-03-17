# BlazeDB Open-Source Re-Audit (2026-03-16)

This re-audit captures current evidence after transport deferral gating and local-release hardening updates.

## Verdict

- **Release-candidate ready, pending CI evidence completion**.
- Core-only path is stable, reproducible locally, and now has explicit CI evidence automation.

## Evidence Collected

1. **Core clean-checkout verification**
   - Command: `./Scripts/verify-clean-checkout.sh`
   - Result: PASS
   - Notes: release build + Tier0/Tier1 golden path + Tier2 cross-version harness all pass in clean worktree snapshot.

2. **README quickstart verification**
   - Command: `./Scripts/verify-readme-quickstart.sh`
   - Result: PASS
   - Measured runtime: **35 seconds** (target: <= 300 seconds)
   - Fixes included:
     - `Examples/HelloBlazeDB/main.swift` now uses a password that passes current policy.
     - `Examples/HelloBlazeDB/main.swift` now uses an isolated temp database path per run so quickstart output stays deterministic.

3. **Release-tag reproducibility probe**
   - Command: `./Scripts/check-release-tag-builds.sh`
   - Result: FAIL on `v0.1.3`, `v2.6.0`, `v2.7.0`
   - Primary failure: private SSH dependency fetch (`git@github.com:Mikedan37/BlazeTransport.git`).

4. **Distributed transport scope**
   - Main branch is explicitly core-only.
   - Distributed transport calls are gated and documented for later re-enable.

5. **Security review scheduling**
   - External review plan created and tracked in-repo.
   - Issue template added for concrete schedule/remediation tracking.

## Checklist Delta from this Re-Audit

- Marked complete:
  - README quickstart from scratch under 5 minutes.
  - Warning-noise reduction in readiness script output (full logs captured; terminal output summarized).

- Still blocked:
  - Tier0 + Tier1 full suites green in CI on a clean runner (workflow updated, awaiting first green run evidence artifact).

## Remaining Path to Final Release

1. Run CI (`ci.yml`) and evidence lane (`oss-readiness-evidence.yml`) and attach green-run artifacts.
2. Cut next public tag from current core-only graph.
3. Keep legacy tags explicitly marked archival/non-reproducible unless re-cut from public dependencies.
4. Execute external security review per plan and publish report summary.

## Operational Blocker Note

Current PR checks for CI/evidence can fail before job start if hosted Actions billing is not active. In that case, resolve repository billing/spending-limit status and re-run checks to produce final green evidence artifacts.

Latest observed blocked runs on `main` (same billing blocker):
- `CI`: https://github.com/Mikedan37/BlazeDB/actions/runs/23174801316
- `OSS Readiness Evidence`: https://github.com/Mikedan37/BlazeDB/actions/runs/23174801313
