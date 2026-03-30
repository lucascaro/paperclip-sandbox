# Security Analysis Report Template

You are generating a security analysis report for the paperclipai/companies.sh npm ecosystem. You have been given a structured evidence bundle produced by `security/analyze.sh`. Your job is to synthesize the evidence into a consistent, actionable report.

## Instructions

1. **Do not speculate.** Only report findings backed by evidence in the bundle.
2. **Use the exact format below.** Every section must appear, even if the finding is "CLEAN."
3. **Classify risks** using: HIGH, MEDIUM, LOW. Use the criteria:
   - HIGH: Could lead to credential theft, data exfiltration, or persistent compromise
   - MEDIUM: Unexpected behavior, weak trust signals, or unnecessary capabilities
   - LOW: Minor concerns, mitigated by defaults, or standard patterns
4. **Compare with previous analysis** if version changes are noted in Section 7 of the evidence.
5. **Be concise.** Each finding should be 1-2 sentences. The risk table is the primary output.

## Report Format

Generate the report using exactly this structure:

```markdown
# Security Analysis Report

## paperclipai/companies.sh

- npm package: companies.sh v{VERSION}
- npm package: paperclipai v{VERSION}
- npm package: @paperclipai/server v{VERSION}
- Prepared: {DATE}
- Classification: Internal

> **OVERALL ASSESSMENT: {PROCEED WITH EXTREME CAUTION | PROCEED WITH CAUTION | ACCEPTABLE RISK}**
>
> {1-3 sentence summary of overall findings and recommendation}

---

## 1. Executive Summary

{3-5 bullet points covering the most important findings}

### Recommendation

> {Clear recommendation: run in Docker isolation, safe to run on host, etc.}

---

## 2. Package Architecture

### Layer 1: companies.sh (CLI Orchestrator)
{Brief description based on evidence — what it does, how it starts the server}

### Layer 2: paperclipai (Server Engine)
{Brief description — server, database, background process}

### Layer 3: @paperclipai/server (Runtime)
{Brief description — file count, size, license, key dependencies}

---

## 3. Risk Assessment

| Risk | Severity | Detail |
|------|----------|--------|
| {risk name} | {HIGH/MEDIUM/LOW} | {1-2 sentence description} |
{... one row per identified risk}

---

## 4. Static Scan Results

### 4.1 companies.sh (CLI Layer)

| Finding | Verdict |
|---------|---------|
| {pattern category} | {CLEAN / EXPECTED / KNOWN / CONFIRMED — with brief explanation} |
{... one row per scan category}

### 4.2 paperclipai (Server Engine)

| Finding | Verdict |
|---------|---------|
| {pattern category} | {CLEAN / EXPECTED / KNOWN / CONFIRMED / EXPLAINED — with brief explanation} |
{... one row per scan category}

### Source Audit Notes

{Any clarifications about scan results — e.g., explaining false positives like CJS-to-ESM bridges}

---

## 5. Known Vulnerabilities

{npm audit results — list any CVEs or "No known vulnerabilities found."}

---

## 6. Mitigation Plan: Incremental Trust Gates

| Gate | Action | Pass Criteria |
|------|--------|---------------|
| 0 | Static grep scan (no execution) | No reads of sensitive paths, no calls to unknown endpoints, no eval with user input |
| 1 | Docker container, network disabled | Fails gracefully; only expected hosts in error logs |
| 2 | Docker + mitmproxy HTTPS inspection | All traffic to known-good endpoints; no credentials in payloads |
| 3 | Filesystem-sandboxed host run | No file access attempts outside the project directory |
| 4 | Normal operation with monitoring | Clean post-run audit; no new LaunchAgents, background processes, or listening ports |
| 5 | Ongoing hygiene | Version pinned; Gates 0-2 re-run before every upgrade |

### Credential Safety (Pre-Requisite for All Gates)

{Standard credential scoping recommendations}

---

## 7. Mitigating Factors

{Positive signals observed — clean source, SSRF protection, telemetry opt-out, etc.}

---

## 8. Conclusion

{3-4 sentence summary: no smoking gun / key concerns / recommended next steps}

---

*Prepared by automated security analysis. All findings based on static inspection of companies.sh v{VERSION} and paperclipai v{VERSION}. No code was executed during this analysis.*
```

## Key Decisions

- If the evidence bundle shows **no version change** since the last analysis, note this prominently and state that re-analysis confirms prior findings still hold.
- If **new vulnerabilities** appear in npm audit, escalate the overall assessment accordingly.
- If a pattern scan finds **new matches** not present in the prior report, flag them in the risk table.
- Always include the trust gates section — it is the primary actionable output.
- The report MUST be self-contained — a reader should not need to reference the evidence bundle.
