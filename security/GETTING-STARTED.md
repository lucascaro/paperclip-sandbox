# Getting Started Safely with Paperclip AI (companies.sh)

*A step-by-step guide to running paperclipai safely using Docker isolation, network monitoring, and scoped credentials*

*March 2026*

> **WHO THIS IS FOR**
>
> Anyone evaluating paperclipai/companies.sh for the first time. This guide assumes you have Docker installed and basic command-line familiarity. No prior knowledge of Paperclip is needed.

---

## 1. What is Paperclip?

Paperclip is an AI agent orchestration platform. It lets you create virtual "companies" made of AI agents — a CEO agent, engineers, QA testers, designers — that coordinate through a shared server to accomplish tasks.

- **What it installs:** A Node.js server (port 3100) with an embedded PostgreSQL database, a React dashboard, and agent execution infrastructure.
- **What companies.sh does:** A CLI companion that imports pre-built company templates from a catalog of 16+ templates with 440+ agents.
- **What agents do:** Wake on scheduled "heartbeats," check for assigned tasks, execute work (code, research, content), delegate subtasks, and report results.

> **WHY CAUTION IS WARRANTED**
>
> The npm package installs a persistent background server and database. The GitHub organization is less than 5 weeks old with rapid star growth. The supply chain includes 20+ dependencies. A full security analysis (including source audit) is available in the [companion document](SECURITY-ANALYSIS.md). This guide focuses on how to run it safely despite these concerns.

---

## 2. Prerequisites

| Tool | Details |
|------|---------|
| Docker | Docker Desktop installed and running. This is the primary isolation boundary. |
| Git | For cloning the paperclip-sandbox repository. |
| Node.js | v22+ (for running the static scan script only — not for running Paperclip itself). |
| API Keys | Anthropic API key and/or Claude subscription token for LLM access. See Step 2 below. |

**Optional but recommended:** Review the mitmproxy web UI at http://localhost:8081 during Gate 1 — mitmproxy runs inside Docker, no local install needed.

### Security scanning tools (optional, recommended)

The static scan and analysis scripts integrate several OSS security tools. Install any or all for more comprehensive automated scanning:

```bash
# Vulnerability scanning
brew install trivy        # CVEs in npm deps, secrets, Dockerfile misconfigs
brew install grype        # Vulnerability scanner with SBOM support

# Static analysis (SAST)
brew install semgrep      # Pattern-based security scanner for JS/TS

# Secret scanning
brew install gitleaks     # Detect hardcoded secrets in source code
brew install trufflehog   # Secret scanner + verifies if credentials are active

# Supply chain & repo posture
brew install scorecard    # OpenSSF repo security scoring
npm install -g @socketsecurity/cli  # Supply chain attack detection
```

All tools are optional — the scripts skip any that are not installed and fall back to grep-based pattern matching.

---

## 3. Step-by-Step Setup

### Step 1: Clone the sandbox repository

From the GitHub page for this repository, click the green **Code** button, copy the HTTPS clone URL, and substitute it below.

```bash
git clone REPO_URL_FROM_GITHUB paperclip-sandbox
cd paperclip-sandbox
```

This repository contains Docker configuration, security scripts, and safe wrapper scripts. It does NOT contain Paperclip itself — Paperclip is installed inside the Docker container at build time.

### Step 2: Configure Claude authentication

You have two options for Claude authentication. Choose one:

#### Option A: Claude subscription token (recommended)

Use your existing Claude subscription. The token is stored securely in macOS Keychain — never written to disk as plain text.

```bash
# 1. In a separate terminal, generate a token:
npx @anthropic-ai/claude-code setup-token

# 2. Run the login script and paste the token when prompted:
./scripts/claude-login.sh
```

The token is stored in macOS Keychain (service: `paperclip-sandbox-claude-token`). To revoke it, visit claude.ai/settings/claude-code.

#### Option B: Scoped API key

1. Log in to console.anthropic.com
2. Create a new Workspace (or use an existing test workspace)
3. Create a new API key named "paperclip-sandbox"
4. Set a monthly spend limit of $5–10 on the workspace

#### Other LLM providers

- Only add if a specific company template requires them. Use test accounts with minimal permissions.

### Step 3: Configure environment

```bash
cp .env.example .env

# If using Option B (API key), edit .env:
# ANTHROPIC_API_KEY=sk-ant-...
```

> **NEVER DO THIS**
>
> Do not export API keys in your shell profile (e.g., `export ANTHROPIC_API_KEY=...`). Keys should only exist in the .env file (gitignored) or macOS Keychain. Never commit secrets to git or store tokens as plain text on disk.

### Step 4: Run the static security scan (Gate 0)

This downloads the npm packages without executing them and runs automated security tools plus grep-based pattern matching.

```bash
./security/static-scan.sh
```

If you have the OSS tools installed (see Prerequisites), the script automatically runs Trivy, Semgrep, Gitleaks, and Socket CLI before the grep-based scan. For a full analysis with all seven tools:

```bash
./security/analyze.sh > /tmp/security-evidence-$(date +%Y%m%d).md
```

Review the output. You are looking for:

- **Trivy/Grype**: HIGH or CRITICAL CVEs in npm dependencies
- **Semgrep**: Code injection, eval with external input, dangerous API patterns
- **Gitleaks/TruffleHog**: Hardcoded API keys, tokens, or passwords
- **Socket**: Install scripts, obfuscated code, or network access in dependencies
- **OpenSSF Scorecard**: Low scores on branch protection, code review, or signed releases
- **Grep patterns**: Reads of sensitive paths (.ssh, .aws, keychains), network calls to unknown endpoints, detached background processes, S3 upload patterns

**If anything looks alarming, stop.** Share the output with someone who can review it. Do not proceed to the next step until you are comfortable with the scan results.

### Step 5: First run — proxy with allowlist (Gate 1)

The default mode routes all traffic through mitmproxy with a strict allowlist. Only hosts listed in `config/allowed-hosts.txt` are permitted — everything else gets a 403 block response. This lets the app start and function normally while preventing any unexpected outbound connections.

```bash
./scripts/start.sh
```

This starts three containers on a Docker internal network:

- **paperclip** — app server, only on `sandboxnet` (no direct internet access)
- **mitmproxy** — allowlist-enforcing proxy, bridges `sandboxnet` ↔ `default` network
- **caddy gateway** — TLS-terminating reverse proxy, publishes the dashboard over HTTPS

Open http://localhost:8081 in your browser (password: `p`). You will see every request in real time. Blocked requests appear as 403 responses with a clear message identifying the blocked host.

The dashboard is at **https://localhost:3100** (HTTPS with auto-generated TLS certificate — your browser will show a self-signed cert warning on first visit).

**What to verify:**

- All traffic goes to hosts in `config/allowed-hosts.txt`
- No blocked requests to unexpected hosts appear in the mitmproxy UI
- Request bodies contain only expected data (prompts, template downloads)
- No environment variables, file contents, or credentials appear in request payloads

**If you see blocked requests to a host you trust**, add it to `config/allowed-hosts.txt` and restart.

**Default allowlist** (`config/allowed-hosts.txt`):

- `localhost` / `host.docker.internal` — internal communication
- `registry.npmjs.org` — npm package resolution
- `api.anthropic.com` / `console.anthropic.com` / `statsigapi.net` — Claude API and auth

The allowlist also supports exact URL rules (`METHOD URL` format) for fine-grained access control. See the file for examples.

Stop the sandbox and run the audit:

```bash
./scripts/stop.sh
./security/audit-run.sh /tmp/paperclip-sandbox-marker-XXXXX
```

### Step 6: Normal operation

After Gates 0–1 pass clean, you can run with full network access:

```bash
./scripts/start.sh --open
```

The dashboard is at http://localhost:3100 (HTTP, no proxy). From here you can:

- Create companies via the UI
- Add pre-built company templates from the catalog
- Hire agents, assign tasks, and monitor execution

To add a company template:

```bash
./scripts/add-company.sh paperclipai/companies/default
```

To monitor resource usage and network connections:

```bash
./scripts/monitor.sh
```

---

## 4. Ongoing Safety Rules

### Always

- Run inside Docker — never `npx paperclipai` or `npx companies.sh` directly on your host
- Use scoped API keys with spend caps or subscription tokens with budget limits — check provider dashboards after each session
- Run the post-run audit after stopping the sandbox
- Back up before upgrades: `./scripts/backup.sh`

### Never

- Export API keys in your shell profile or .bashrc/.zshrc
- Run Paperclip outside of Docker on a machine with SSH keys, AWS credentials, or browser sessions
- Skip trust gates when upgrading to a new version
- Give Paperclip access to production API keys or real customer accounts

### When upgrading

1. Stop the sandbox
2. Back up: `./scripts/backup.sh`
3. Re-run Gate 0 (static scan) on the new version
4. Re-run Gate 1 (allowlist mode) to check for new endpoints
5. Only then start normally

---

## 5. Security Scanning Tools Reference

The analysis pipeline integrates seven OSS security tools. Each tool catches a different class of risk. Together they provide comprehensive coverage across vulnerabilities, secrets, code quality, supply chain, and repo posture.

### Tool Summary

| Tool | Category | What It Catches |
|------|----------|-----------------|
| **Trivy** | SCA + Secrets + Misconfig | Known CVEs in npm deps, hardcoded secrets, Dockerfile misconfigurations |
| **Grype** | SCA + SBOM | Known vulnerabilities; pairs with Syft for SBOM generation |
| **Semgrep** | SAST | Code injection, dangerous API usage, security anti-patterns in JS/TS |
| **Gitleaks** | Secret Scanning | Hardcoded API keys, tokens, passwords in source code and git history |
| **TruffleHog** | Secret Scanning | Same as Gitleaks + verifies if discovered credentials are still active |
| **OpenSSF Scorecard** | Repo Posture | Branch protection, signed releases, CI hygiene, maintainer count, dependency updates |
| **Socket CLI** | Supply Chain | Install scripts, obfuscated code, network access in deps, typosquatting |

### How to Run

**Quick scan (Gate 0)** — runs Trivy, Semgrep, Gitleaks, and Socket if installed, plus grep patterns:

```bash
./security/static-scan.sh
```

**Full analysis** — runs all seven tools and generates a complete evidence bundle:

```bash
./security/analyze.sh > /tmp/security-evidence-$(date +%Y%m%d).md
```

### Interpreting Results

| Signal | Severity | Action |
|--------|----------|--------|
| Trivy/Grype: HIGH/CRITICAL CVE with fix available | **HIGH** | Do not proceed until upstream patches or you verify the vulnerable code path is not reachable |
| Semgrep: eval/Function with external input | **HIGH** | Manual review required — distinguish CJS-to-ESM bridge from actual injection |
| Gitleaks/TruffleHog: active credential found | **CRITICAL** | Report to upstream maintainer immediately; do not use the package |
| OpenSSF Scorecard: score < 4/10 | **MEDIUM** | Indicates weak security practices upstream; proceed with extra caution |
| Socket: install script or obfuscated code | **HIGH** | Investigate the flagged dependency before any execution |
| Socket: network access in postinstall | **CRITICAL** | Package executes code and phones home during installation — block |

---

## 6. Quick Reference

| Command | What it does |
|---------|--------------|
| `./scripts/start.sh` | Start with proxy allowlist — blocks unknown hosts (default, Gate 1) |
| `./scripts/start.sh --open` | Start with full network access, no proxy (after Gates pass) |
| `./scripts/claude-login.sh` | Store Claude subscription token securely in macOS Keychain |
| `./scripts/stop.sh` | Stop all containers, check for escaped processes |
| `./scripts/add-company.sh <template>` | Add a company template inside the running container |
| `./scripts/monitor.sh` | Live resource and network monitoring |
| `./scripts/backup.sh` | Snapshot data/ before upgrades |
| `./security/static-scan.sh` | Quick scan with OSS tools + grep patterns (Gate 0) |
| `./security/analyze.sh` | Full analysis with all 7 OSS tools + evidence bundle |
| `./security/audit-run.sh <marker>` | Post-run file, process, and port audit |

### Key URLs

- Paperclip Dashboard: https://localhost:3100 (sandbox mode) or http://localhost:3100 (open mode)
- mitmproxy UI (sandbox mode): http://localhost:8081 (password: `p`)
- Health check: https://localhost:3100/api/health

### Key Files

- `.env` — your scoped API keys (gitignored, never committed)
- `data/` — all Paperclip data: database, agent workspaces, backups (gitignored)
- `docker/` — container configuration and compose files
- `security/PLAYBOOK.md` — security playbook: trust gates, operational guardrails, and runbooks
- `security/SECURITY-ANALYSIS.md` — detailed security analysis report and threat model

---

## 7. Troubleshooting

### Container fails to start

- Check Docker Desktop is running
- Check .env file exists and has at least one API key
- Check port 3100 is not in use: `lsof -i :3100`

### Agents are not executing

- Check the dashboard for error messages on agent cards
- Verify API keys are valid and have remaining budget
- Check container logs: `docker logs paperclip-sandbox`

### Sandbox mode shows no traffic in mitmproxy

- Ensure you are running in default sandbox mode (not `--open`)
- Check mitmproxy container is running: `docker ps`
- Open http://localhost:8081 (password: `p`) — traffic appears in real time

### Browser shows certificate warning

- This is expected in sandbox mode — Caddy generates a self-signed TLS certificate
- Accept the certificate to proceed to the dashboard

### Need to start fresh

```bash
./scripts/stop.sh
rm -rf data/*
touch data/.gitkeep
./scripts/start.sh
```

---

*For the full security analysis, see the companion document: [Security Analysis Report](SECURITY-ANALYSIS.md)*
