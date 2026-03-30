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
| Node.js | v20+ (for running the static scan script only — not for running Paperclip itself). |
| API Keys | Anthropic and/or OpenAI accounts for LLM access. You will create scoped, limited keys. |

**Optional but recommended:** mitmproxy (`brew install mitmproxy`) for inspecting all HTTPS traffic during Gate 2.

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

### Step 2: Create scoped API keys

This is the single most important safety step. Never use your primary development API keys.

#### Anthropic

1. Log in to console.anthropic.com
2. Create a new Workspace (or use an existing test workspace)
3. Create a new API key named "paperclip-sandbox"
4. Set a monthly spend limit of $5–10 on the workspace

#### OpenAI

1. Log in to platform.openai.com
2. Create a new Project named "paperclip-sandbox"
3. Set a $10/month budget on the Project
4. Create an API key scoped to that Project only

#### Other services

- Only add if a specific company template requires them. Use test accounts with minimal permissions.

### Step 3: Configure environment

```bash
cp .env.example .env

# Edit .env and add your scoped keys:
# ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...
```

> **NEVER DO THIS**
>
> Do not export API keys in your shell profile (e.g., `export OPENAI_API_KEY=...`). Keys should only exist in the .env file, which is gitignored and only passed to the Docker container. Do not commit .env to git.

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

### Step 5: First run — Docker with no network (Gate 1)

This is the safest possible execution. The container has no internet access, so even if the code is malicious, it cannot exfiltrate data.

```bash
./scripts/start.sh --isolated
```

What to expect:

- The container builds and starts Paperclip
- Onboarding runs automatically
- Network calls will fail (this is intentional)
- Check the logs for which endpoints it tried to reach

**Pass criteria:** Only api.anthropic.com, api.openai.com, and registry.npmjs.org appear in error logs. No unexpected endpoints.

Stop the sandbox and run the audit:

```bash
./scripts/stop.sh
./security/audit-run.sh /tmp/paperclip-sandbox-marker-XXXXX
```

### Step 6: Monitored run with mitmproxy (Gate 2)

Now enable network access, but route all traffic through a proxy that logs every request.

```bash
./scripts/start.sh --proxy
```

This starts two containers:

- Paperclip server (all traffic routed through the proxy)
- mitmproxy web UI at http://localhost:8081

Open http://localhost:8081 in your browser. You will see every HTTPS request in real time — destination, headers, and full request/response bodies.

**What to verify:**

- All traffic goes to known-good endpoints (api.anthropic.com, api.openai.com, registry.npmjs.org, github.com)
- Request bodies contain only expected data (prompts, template downloads)
- No environment variables, file contents, or credentials appear in request payloads
- No requests to unknown AWS endpoints, S3 buckets, or third-party servers

### Step 7: Normal operation

After Gates 0–2 pass clean, you can run with network access:

```bash
./scripts/start.sh
```

The dashboard is at http://localhost:3100. From here you can:

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
- Use scoped API keys with spend caps — check provider dashboards after each session
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
4. Re-run Gate 1 (isolated) to check for new endpoints
5. Re-run Gate 2 (proxy) to inspect traffic changes
6. Only then start normally

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
| `./scripts/start.sh` | Start Paperclip in Docker with safety controls |
| `./scripts/start.sh --isolated` | Start with NO network (Gate 1) |
| `./scripts/start.sh --proxy` | Start with mitmproxy monitoring (Gate 2) |
| `./scripts/stop.sh` | Stop all containers, check for escaped processes |
| `./scripts/add-company.sh <template>` | Add a company template inside the running container |
| `./scripts/monitor.sh` | Live resource and network monitoring |
| `./scripts/backup.sh` | Snapshot data/ before upgrades |
| `./security/static-scan.sh` | Quick scan with OSS tools + grep patterns (Gate 0) |
| `./security/analyze.sh` | Full analysis with all 7 OSS tools + evidence bundle |
| `./security/audit-run.sh <marker>` | Post-run file, process, and port audit |

### Key URLs

- Paperclip Dashboard: http://localhost:3100
- mitmproxy UI (proxy mode): http://localhost:8081
- Health check: http://localhost:3100/api/health

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

### Proxy mode shows no traffic

- Ensure you used --proxy flag (not just --network)
- Check mitmproxy container is running: `docker ps`
- Open http://localhost:8081 — traffic appears in real time

### Need to start fresh

```bash
./scripts/stop.sh
rm -rf data/*
touch data/.gitkeep
./scripts/start.sh
```

---

*For the full security analysis, see the companion document: [Security Analysis Report](SECURITY-ANALYSIS.md)*
