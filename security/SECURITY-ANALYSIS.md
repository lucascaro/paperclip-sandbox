# Security Analysis Report

## paperclipai/companies.sh

- npm package: companies.sh v2026.325.2
- npm package: paperclipai v2026.325.0
- npm package: @paperclipai/server (11MB, open source — MIT)
- Prepared: March 30, 2026
- Classification: Internal

> **OVERALL ASSESSMENT: PROCEED WITH EXTREME CAUTION**
>
> This package installs a persistent background server and a local database. The source code is fully public (MIT license). A source audit confirmed that S3 is an optional storage backend (local disk is default), dynamic imports are standard module loading, and plugin HTTP has SSRF protection. The persistent background server and young organization remain the primary concerns. Docker isolation is still recommended for initial evaluation.

---

## 1. Executive Summary

This report documents a security analysis of the paperclipai/companies.sh npm ecosystem, an AI agent orchestration framework. The analysis was conducted through static code inspection of downloaded (but never executed) packages.

### Key Findings

- **No direct credential theft detected** — no reads of ~/.ssh, ~/.aws, ~/.gnupg, or keychain paths in either package
- **Persistent background server** — the package silently starts a detached Node.js server on port 3100 that survives after the CLI exits
- **Open-source server** — @paperclipai/server source is public (MIT) at github.com/paperclipai/paperclip. Source audit verified S3 is optional, fetch has SSRF protection, and dynamic imports are standard module loading.
- **Dynamic code loading** — new Function() constructor enables arbitrary module imports at runtime, defeating static analysis
- **S3 upload infrastructure** — full AWS S3 client with a default bucket named "paperclip"; data exfiltration capability exists
- **Young organization** — the entire paperclipai GitHub org is < 5 weeks old with 38,000 stars in 27 days from a single maintainer

### Recommendation

> **DO NOT RUN ON HOST WITHOUT ISOLATION**
>
> Execute only inside a Docker container with network disabled (Gate 1), then with mitmproxy monitoring (Gate 2). Use scoped, rate-limited API keys with $5–10 spend caps. Follow the incremental trust gates detailed in Section 5.

---

## 2. Package Architecture

The companies.sh ecosystem is a three-layer system, not a simple CLI tool:

### Layer 1: companies.sh (CLI Orchestrator)

- Thin TypeScript CLI that fetches agent configuration templates from GitHub
- Checks if the local Paperclip server is running on 127.0.0.1:3100
- If not running, silently launches it in the background as a detached process
- Downloads company template files and imports them via the server API
- Writes telemetry UUID to ~/.config/companies.sh/ and phones home to AWS Lambda

### Layer 2: paperclipai (Server Engine)

- Full Node.js server that installs and starts a local PostgreSQL database
- Starts a web server on port 3100 with HTTP and WebSocket endpoints
- Runs persistently in the background after first launch
- Contains adapters for Claude Code, Codex, Cursor, Gemini CLI, and others

### Layer 3: @paperclipai/server (Open-Source Runtime)

- 744 files, 11MB unpacked — the actual agent execution engine
- Source is public (MIT license) at github.com/paperclipai/paperclip/tree/master/server/src; npm artifact is compiled JS
- Dependencies include @aws-sdk/client-s3, embedded-postgres, express, ws, sharp, chokidar, open, better-auth
- Manages agent filesystem access, memory, coordination, and execution

---

## 3. Risk Assessment

The following risks were identified through static analysis and dependency inspection:

| Risk | Severity | Detail |
|------|----------|--------|
| Persistent background server | **HIGH** | Running npx companies.sh add silently starts a detached Node.js server on port 3100 (detached: true, child.unref()). It survives after the CLI exits. No explicit "install a server" prompt is shown. |
| Young organization | MEDIUM | Entire org created 2026-02-27. 38k stars in 27 days, single maintainer. Source is public and auditable, but project maturity is low. |
| Supply chain attack surface | **HIGH** | 20+ dependencies including @aws-sdk/client-s3 (S3 uploads), embedded-postgres (database), open (browser launch), sharp (native binary), chokidar (filesystem watcher). |
| Dynamic imports (CORRECTED) | LOW | The new Function() in compiled npm package is a CJS-to-ESM bridge. Source shows standard await import() for plugin manifests and embedded-postgres. Not arbitrary code execution. |
| S3 storage (CORRECTED) | LOW | S3 is an optional storage backend; default is local_disk. Only activated when explicitly configured by the user. Not an exfiltration vector in default configuration. |
| Suspicious social proof | MEDIUM | Entire org created 2026-02-27. Main repo: 38k stars in 27 days, single maintainer (cryppadotta, protonmail). Source is public but project maturity is low. |
| Telemetry without consent | MEDIUM | Writes UUID to ~/.config/companies.sh/telemetry.json and POSTs to AWS Lambda on first run. Opt-out via env var, not opt-in. |
| Agent filesystem access | MEDIUM | Agents get $AGENT_HOME with read/write. Local disk storage has path traversal prevention (resolveWithin with .. rejection). chokidar watches broadly. |
| Template injection risk | MEDIUM | Community PRs to the template registry (46 forks, 6 open issues) could inject malicious agent configurations. |
| Plugin HTTP fetch (CORRECTED) | LOW | Plugin fetch has full SSRF protection: protocol whitelist (http/https only), DNS resolution with private IP blocking, and DNS-pinning to prevent rebinding attacks. Well-implemented. |

---

## 4. Static Scan Results

Packages were downloaded as tarballs and unpacked without execution. The following patterns were searched via grep across all .js and .ts files.

### 4.1 companies.sh (CLI Layer)

| Finding | Verdict |
|---------|---------|
| Sensitive path access (.ssh, .aws, .gnupg, keychain) | CLEAN — none found |
| eval() / Function() constructor | CLEAN — none found |
| Child process spawning | EXPECTED — spawns the paperclip server process |
| Network requests | KNOWN — health check to localhost:3100 + telemetry to AWS Lambda |
| Environment variable access | REASONABLE — PAPERCLIPAI_CMD, PATH, CI detection flags |
| Filesystem writes outside cwd | KNOWN — writes to ~/.config/companies.sh/ (telemetry state) |
| Telemetry endpoints | CONFIRMED — rusqrrg391.execute-api.us-east-1.amazonaws.com/ingest |

### 4.2 paperclipai (Server Engine)

| Finding | Verdict |
|---------|---------|
| Sensitive path access (.ssh, .aws, .gnupg, keychain) | CLEAN — none found |
| eval() / Function() constructor | EXPLAINED — CJS-to-ESM bridge in compiled output. Source uses standard await import() for plugin manifests. |
| Network requests | VERIFIED — api.anthropic.com/api.openai.com (credential checks), GitHub API (template downloads), plugin fetch with SSRF protection |
| Environment variable access | HEAVY — 20+ env vars including DATABASE_URL, auth secrets, master encryption keys |
| Filesystem writes | EXTENSIVE — ~15 mkdirSync/writeFileSync calls; writes to PAPERCLIP_HOME, creates dirs and config files |
| Detached/background processes | CONFIRMED — spawn with detached: true and child.unref(); server.unref() keeps server alive |
| S3/cloud upload capability | OPTIONAL — S3 is an alternative storage backend, default is local_disk. Only used when explicitly configured by the user. |
| Database installation | CONFIRMED — embedded-postgres installs and runs a local PostgreSQL instance |

### Source Audit Clarifications

A source audit of the TypeScript code (github.com/paperclipai/paperclip/tree/master/server/src) resolved several concerns from the static scan of compiled artifacts. The new Function() pattern is a standard CJS-to-ESM bridge, not arbitrary code execution. The generic fetch() calls are for GitHub API access and plugin HTTP with SSRF protection (protocol whitelist, DNS pinning, private IP blocking). S3 is a user-configured optional storage backend. Docker isolation is still recommended for initial evaluation due to the persistent background server and the project's young age.

---

## 5. OSS Security Tool Results

Automated scans were run against the downloaded (never executed) packages using open-source security tools. See [GETTING-STARTED.md](GETTING-STARTED.md) for tool installation and usage instructions.

### 5.1 Trivy (Vulnerability + Secret + Misconfig Scanner)

| Target | HIGH/CRITICAL CVEs | Secrets | Misconfigs |
|--------|-------------------|---------|------------|
| companies.sh | 0 | 0 | 0 |
| paperclipai | 0 | 0 | 0 |
| Docker image | SKIPPED (not built) | — | — |

> **PASS** — No vulnerabilities, secrets, or misconfigurations detected in either package.

### 5.2 Grype (Vulnerability Scanner + SBOM)

| Target | Vulnerabilities (fixable) |
|--------|--------------------------|
| companies.sh | 0 |
| paperclipai | 0 |

> **PASS** — No known vulnerabilities found in either package.

### 5.3 Semgrep (SAST Scanner)

| Target | Errors | Warnings | Supply Chain |
|--------|--------|----------|--------------|
| companies.sh | 0 | 0 | 0 |
| paperclipai | 0 | 0 | 0 |

> **PASS** — No security findings from `auto`, `p/javascript`, `p/nodejs`, or `p/supply-chain` rulesets.

### 5.4 Gitleaks (Secret Scanner)

> **SKIPPED** — `gitleaks` not installed. Install with `brew install gitleaks`.

### 5.5 TruffleHog (Secret Scanner with Verification)

> **SKIPPED** — `trufflehog` not installed. Install with `brew install trufflehog`.

### 5.6 OpenSSF Scorecard (Repo Security Posture)

> **SKIPPED** — `GITHUB_TOKEN` not set (required to avoid rate limiting). Run with `GITHUB_TOKEN=ghp_... ./security/analyze.sh`.

### 5.7 Socket CLI (Supply Chain Attack Detection)

| Package | Version | License | Direct Deps | Published By |
|---------|---------|---------|-------------|-------------|
| companies.sh | 2026.325.2 | MIT | 4 | GitHub Actions (OIDC) |
| paperclipai | 2026.325.0 | MIT | 10 | GitHub Actions (OIDC) |

> **PASS** — Both packages are published via GitHub Actions OIDC (not personal tokens). No install script alerts, no obfuscated code alerts, no typosquatting alerts from Socket.

---

## 6. Mitigation Plan: Incremental Trust Gates

Each gate is a checkpoint. Do not proceed to the next unless the current one passes clean.

| Gate | Action | Pass Criteria |
|------|--------|---------------|
| 0 | Static scan with OSS tools + grep (no execution) | No HIGH/CRITICAL CVEs without mitigations, no leaked secrets, no reads of sensitive paths, no calls to unknown endpoints, no eval with user input |
| 1 | Docker container, network disabled | Fails gracefully; only api.anthropic.com, api.openai.com, registry.npmjs.org in error logs |
| 2 | Docker + mitmproxy HTTPS inspection | All traffic to known-good endpoints; no env vars, filesystem content, or credentials in payloads |
| 3 | Filesystem-sandboxed host run (sandbox-exec) | No file access attempts outside the project directory |
| 4 | Normal operation with monitoring | Clean post-run audit; no new LaunchAgents, background processes, or listening ports |
| 5 | Ongoing hygiene | Version pinned; Gates 0–2 re-run before every upgrade |

### 6.1 Credential Safety (Pre-Requisite for All Gates)

- Anthropic: create a dedicated key named "paperclip-sandbox" with $5–10/month spend cap
- OpenAI: create a new Project with $10/month budget; key scoped to that Project only
- Other services: only add after trust gates pass; use test accounts with minimal permissions
- Never export API keys in shell profile — .env file only, never committed to git
- Monitor usage dashboards before and after every test run

### 6.2 Docker Sandbox Configuration

The provided Dockerfile.sandbox and run-sandboxed.sh script enforce:

- Read-only filesystem (--read-only)
- All Linux capabilities dropped (--cap-drop ALL)
- No privilege escalation (--security-opt no-new-privileges)
- 512MB memory limit
- Network disabled by default (--network none)
- Telemetry disabled (DO_NOT_TRACK=1)
- Non-root user inside container

### 6.3 Network Monitoring (Gate 2)

mitmproxy intercepts all HTTPS traffic, allowing inspection of:

- Every destination host and endpoint path
- Request headers (including any leaked credentials)
- Request/response bodies (data being sent and received)
- Connection timing and frequency

After the run, mitmweb provides a browser UI for reviewing all captured traffic. Look specifically for requests to endpoints other than api.anthropic.com, api.openai.com, and registry.npmjs.org.

### 6.4 Post-Run Audit Checklist

- Files modified outside project directory since the run marker timestamp
- New LaunchAgents installed in ~/Library/LaunchAgents/
- Background processes still running (paperclip, companies, embedded-postgres)
- Listening ports (node or postgres on any port, especially 3100)
- Telemetry artifacts at ~/.config/companies.sh/telemetry.json
- Docker containers still running from the sandbox image

---

## 7. Mitigating Factors

For balanced assessment, the following positive signals were observed:

- The CLI layer (companies.sh) has clean, readable TypeScript source code
- Telemetry implementation respects DO_NOT_TRACK=1 and CI=true environment variables
- npm publishing uses GitHub Actions OIDC for provenance (not a personal token)
- Agent instruction templates include explicit "never exfiltrate secrets" clauses
- The main paperclip repo has active commit history and contributor community
- Telemetry UUIDs rotate every 30 days and only fire on successful install

> **Important Caveat**
>
> Agent instruction clauses like "never exfiltrate secrets" are LLM prompts, not access controls. However, the server code (now auditable) implements real security boundaries: SSRF protection on plugin HTTP, path traversal prevention on local storage, and protocol whitelisting.

---

## 8. Conclusion

The paperclipai/companies.sh ecosystem presents a mixed security profile:

- **No smoking gun:** Static analysis found no direct reads of sensitive credentials, SSH keys, or browser data.
- **Source audit resolved key concerns:** S3 is optional (default: local disk), dynamic imports are standard module loading, and plugin HTTP has proper SSRF protection with DNS pinning.
- **Unusual trust signals:** A 5-week-old organization with 38k GitHub stars and a single anonymous maintainer warrants skepticism about the social proof.

The incremental trust gate approach (Section 6) provides a structured path to evaluate the framework safely. **Gate 0 (static scan) is complete and passed with caveats.** Gates 1–2 (Docker isolation + network monitoring) are required before any execution with real API keys.

---

*Prepared by automated security analysis. All findings based on static inspection of companies.sh v2026.325.2 and paperclipai v2026.325.0. No code was executed during this analysis.*
