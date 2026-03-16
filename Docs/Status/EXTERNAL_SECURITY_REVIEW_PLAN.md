# External Security Review Plan

This plan tracks third-party security review for BlazeDB's public core release path.

## Status

- **State:** Scheduled (vendor selection + booking in progress)
- **Target window:** 2026-04-01 through 2026-04-30
- **Scope owner:** Maintainers (`founder@danylchukstudios.dev`)

## Mandatory Review Scope

1. At-rest encryption and key-derivation paths
2. Metadata integrity signing/verification paths
3. Recovery and durability flows (WAL/recovery manager)
4. Import/export verification boundaries and legacy compatibility fallbacks

## Deliverables Required

- Signed report from reviewer with findings and severity
- Remediation plan with owner and due date for each finding
- Public summary note in release evidence docs

## Completion Criteria

- Review report received
- Critical/high issues either fixed or explicitly risk-accepted with rationale
- `Docs/Status/OPEN_SOURCE_READINESS_CHECKLIST.md` security-review item marked complete with report reference
