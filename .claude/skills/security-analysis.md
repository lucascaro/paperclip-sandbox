---
name: security-analysis
description: Run a security analysis of the paperclipai/companies.sh packages and generate a structured report.
user_invocable: true
---

# Security Analysis Skill

Run a full security analysis of the pinned paperclipai/companies.sh packages and produce a report.

## Steps

1. **Gather evidence.** Run `./security/analyze.sh` from the repo root. This downloads packages as tarballs (without executing them), collects npm metadata, runs pattern scans, and checks for known vulnerabilities. Capture the full output — this is the evidence bundle.

2. **Read the prompt template.** Read `security/analysis-prompt.md` for the exact report format and synthesis instructions.

3. **Read the previous report** (if it exists) at `security/SECURITY-ANALYSIS.md`. Use it as context for identifying changes, but do not copy from it uncritically — regenerate all findings from the current evidence.

4. **Synthesize the report.** Following the template instructions exactly, produce a new `security/SECURITY-ANALYSIS.md` from the evidence bundle. Every claim in the report must be backed by evidence from the bundle. Use the risk classification criteria from the template.

5. **Update VERSIONS.md.** Ensure the analysis date in `VERSIONS.md` matches today's date.

6. **Archive previous report.** If the package versions changed since the previous report, move the old report to `security/reports/SECURITY-ANALYSIS-{old-version-date}.md` before writing the new one. Create the `security/reports/` directory if it does not exist. If versions are unchanged, overwrite in place.

## Important

- Never execute the npm packages — only download and inspect as tarballs.
- The evidence gathering script (`analyze.sh`) does all the data collection. Do not duplicate its work manually.
- The report must be self-contained. A reader should not need to reference the evidence bundle.
- Reports are generated per main version and kept historically in `security/reports/`.
