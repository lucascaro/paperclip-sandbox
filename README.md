# Paperclip Sandbox

A hardened harness for running [paperclipai/companies.sh](https://github.com/paperclipai/companies) safely.

Paperclip is an AI agent orchestration platform that lets you create and manage
multiple "companies" — teams of AI agents (CEO, engineers, QA, etc.) that
coordinate through a shared server. This repo wraps it in Docker isolation,
network monitoring, and audit tooling so you can experiment without risk.

## Quick Start

```bash
# 1. Copy and fill in scoped API keys (see security/PLAYBOOK.md)
cp .env.example .env

# 2. Start the sandbox (Docker, no network by default)
./scripts/start.sh

# 3. Add a company template
./scripts/add-company.sh paperclipai/companies/default

# 4. Open the dashboard
open http://localhost:3100
```

## Project Structure

```
paperclip-sandbox/
├── docker/                  # Container config (Dockerfile, compose, entrypoint)
├── config/                  # Paperclip config overrides, network allowlist
├── data/                    # (gitignored) Bind-mounted as PAPERCLIP_HOME
├── scripts/                 # Safe wrappers: start, stop, add-company, monitor
├── security/                # Playbook, static scan, audit, analysis report
└── docs/                    # Architecture reference, upgrade checklist
```

## Safety Model

Everything runs inside Docker. The host never executes paperclipai code directly.

| Control | Detail |
|---------|--------|
| Filesystem | `data/` bind-mount only — nothing writes to `~/.paperclip` |
| Network | Disabled by default; allowlist mode for approved endpoints |
| Capabilities | `--cap-drop ALL`, `--security-opt no-new-privileges` |
| Memory | 1GB limit |
| Telemetry | Disabled (`DO_NOT_TRACK=1`) |
| Credentials | Scoped, rate-limited keys with spend caps |
| Monitoring | mitmproxy sidecar, post-run audit scripts |

## Trust Gates

Before running with real API keys, follow the incremental trust gates in
[security/PLAYBOOK.md](security/PLAYBOOK.md):

0. Static scan (no execution)
1. Docker with no network
2. Docker with mitmproxy monitoring
3. Docker with network allowlist
4. Normal operation with monitoring
5. Ongoing version-pinned hygiene

## Managing Companies

Companies are created inside the running Paperclip server. This repo has no
company-specific code — all company data lives in `data/` (the database).

```bash
# Add a pre-built company from the catalog
./scripts/add-company.sh paperclipai/companies/fullstack-forge

# Or create one interactively via the dashboard
open http://localhost:3100
```

## Security Report

See [security/PLAYBOOK.md](security/PLAYBOOK.md) for the full analysis and
mitigation plan. A .docx report suitable for sharing is in `security/`.
