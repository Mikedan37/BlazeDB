# Release Rollback Procedure

This procedure is used when a newly published BlazeDB release is found to be broken or unsafe.

## Trigger Conditions

Initiate rollback when any of the following are confirmed:

- reproducible data-corruption behavior,
- deterministic crash in core CRUD/query paths,
- failed import/export integrity verification,
- security vulnerability requiring immediate mitigation.

## Immediate Actions (T+0 to T+30m)

1. Freeze new tags and release publishing.
2. Open a high-priority incident issue labeled `release-rollback`.
3. Post a short advisory in release notes and project discussion channel.
4. Assign an incident owner and a communications owner.

## Rollback Paths

### Path A: SwiftPM Release Tag Rollback

Use when the bad release is the latest tag.

1. Publish a hotfix release (`vX.Y.Z+1`) that reverts the faulty changes.
2. In the new release notes, clearly mark the prior tag as superseded.
3. Link mitigation and migration guidance in the hotfix release.

> Avoid deleting published tags unless absolutely necessary; prefer forward-fix.

### Path B: Feature Kill-Switch Rollback

Use when the defect can be safely disabled without full revert.

1. Ship a patch release that disables the affected feature path.
2. Preserve wire/storage compatibility.
3. Add explicit warning in release notes and docs.

## Verification Before Declaring Resolved

- `./Scripts/oss-readiness-local.sh` passes on a clean checkout.
- Golden-path tests pass (`Tier0` and `Tier1`).
- Incident reproduction case is now green.

## Postmortem Requirements

Within 72 hours of stabilization:

1. Publish root-cause summary.
2. Document preventive action items.
3. Add regression tests for the incident.
4. Update `CHANGELOG.md` and affected docs.
