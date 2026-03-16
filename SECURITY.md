# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in BlazeDB, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, email **founder@danylchukstudios.dev** with:

1. A description of the vulnerability
2. Steps to reproduce
3. Potential impact
4. Suggested fix (if any)

You should receive a response within 72 hours. We will work with you to understand the issue and coordinate a fix before any public disclosure.

## Disclosure and Response SLAs

- **Initial acknowledgement:** within 72 hours
- **Triage decision (severity + scope):** within 7 calendar days
- **Coordinated fix target:** depends on severity
  - Critical: target hotfix within 7 days
  - High: target fix within 14 days
  - Medium/Low: next scheduled patch release
- **Coordinated disclosure:** after fix availability or agreed public timeline

If a timeline must change, maintainers will communicate the revised target to the reporter.

## Scope

This policy covers the BlazeDB library itself, including:

- Storage engine and page store
- Encryption and key management
- Transaction processing and WAL
- Query engine
- Row-level security (RLS)

Issues in example code, documentation, or test fixtures are appreciated but are lower priority.

## External Review Cadence

- BlazeDB targets an external third-party security review for public release paths.
- The active tracking plan is in `Docs/Status/EXTERNAL_SECURITY_REVIEW_PLAN.md`.
- Review tracking issues should use `.github/ISSUE_TEMPLATE/security_review_tracking.md`.
