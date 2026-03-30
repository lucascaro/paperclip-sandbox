---
name: update-analysis-versions
description: TODO — Skill to update packages to latest versions and re-run security analysis.
user_invocable: false
---

# TODO: Update Analysis to Latest Versions Skill

## Goal

Create a skill that:
1. Checks npm for the latest versions of companies.sh, paperclipai, and @paperclipai/server
2. Updates VERSIONS.md with the new versions and integrity hashes
3. Runs the `/security-analysis` skill to produce a new report for the updated versions
4. Archives the previous report before overwriting

## Important Notes

- **Reports are generated per main version and kept historically.** When a new version is analyzed, the previous report must be moved to `security/reports/SECURITY-ANALYSIS-{version-date}.md` before the new report is written. The `security/reports/` directory serves as a historical archive of all analyzed versions.
- The upgrade must re-run Gates 0-2 from the security playbook before the version bump is considered safe.
- The skill should refuse to update if the current trust gates have not passed.
- See `scripts/upgrade.sh` and `docs/UPGRADE-CHECKLIST.md` for the existing manual upgrade flow that this skill should automate.
