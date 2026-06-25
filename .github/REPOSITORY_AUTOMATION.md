# Repository automation policy

## Cursor / Bugbot — do not open PRs automatically

Unsolicited PRs from `cursor[bot]` / `app/cursor` are auto-closed by `.github/workflows/reject-automated-prs.yml`.

To stop them from being created in the first place:

1. Open [cursor.com/dashboard](https://cursor.com/dashboard) → **Bugbot**
2. **Disable Autofix** (team default and personal setting)
3. **Remove BlazeDB** from enabled repositories, or set **Only run when mentioned**
4. If using **Background Agents**, revoke GitHub write access or disable scheduled runs for this repo

## Commit and PR attribution

In Cursor:

1. **Settings → Agents → Attribution** — turn off **Commit attribution** and **PR attribution**
2. CLI: `~/.cursor/cli-config.json` should set `"attributeCommitsToAgent": false` and `"attributePRsToAgent": false`

Project rules in `.cursor/rules/` reinforce: no `Co-authored-by: Cursor`, no `Made-with: Cursor`, no bot authorship.

## Dependencies

Dependabot does **not** open version-update PRs for this repo (`open-pull-requests-limit: 0`).

When a dependency should be updated, bump it directly on `main` (workflows, `Package.swift`, etc.) and verify CI.
