# Security Playbook: paperclip-sandbox

How to safely evaluate and run `paperclipai/companies.sh` without trusting it.

## Threat Summary

`companies.sh` is not a simple CLI. Running `npx companies.sh add ...` does the following:

1. Downloads and executes the `companies.sh` CLI (TypeScript/Node.js)
2. Pulls in `paperclipai` as a hard dependency, which pulls in `@paperclipai/server` (744 files, 11MB)
3. Silently starts a **persistent background Node.js server** on port 3100 (`detached: true`, `child.unref()`)
4. Installs and runs a **local PostgreSQL database** via `embedded-postgres`
5. Downloads agent template files from GitHub and imports them into the running server
6. Writes a UUID to `~/.config/companies.sh/telemetry.json` and sends telemetry to an AWS Lambda endpoint — before any opt-in prompt

### Key risks

| Risk | Severity | Detail |
|------|----------|--------|
| Persistent background server | HIGH | Detached Node.js server on :3100 survives after the CLI exits |
| Large compiled core | MEDIUM | `@paperclipai/server` (11MB compiled JS) — source is public at github.com/paperclipai/paperclip but npm artifact is compiled and may diverge |
| Supply chain surface | MEDIUM | 20+ deps including `@aws-sdk/client-s3`, `embedded-postgres`, `sharp`, `chokidar` |
| Suspicious social proof | MEDIUM | Entire org is < 5 weeks old, 38k stars in 27 days, single maintainer (`cryppadotta`, protonmail) |
| Telemetry without consent | MEDIUM | Opt-out-by-env-var, not opt-in. UUID written to disk regardless |
| Agent filesystem access | MEDIUM | Agents get `$AGENT_HOME` with read/write; `chokidar` watches broadly |
| Template injection | MEDIUM | Community PRs to the template registry could inject malicious agent configs |

### Corrected findings (source audit 2026-03-29)

The original report claimed `@paperclipai/server` was closed-source. **This was incorrect.**
The full TypeScript source is at https://github.com/paperclipai/paperclip/tree/master/server/src (MIT license).

Source audit corrections:
- **S3**: Optional storage backend, defaults to `local_disk`. S3 is only used when explicitly configured. Not an exfiltration vector in default config.
- **Dynamic import (`new Function`)**: The compiled npm package uses `new Function("specifier", "return import(specifier)")` as a CJS-to-ESM bridge. In the TypeScript source, these are standard `await import()` calls for loading plugin manifests and the embedded-postgres module. Not arbitrary code execution.
- **Generic `fetch(url)`**: The server fetch calls are for (1) GitHub API to download company templates, (2) OpenAI/Anthropic API credential validation, (3) plugin HTTP with full SSRF protection (protocol whitelist, DNS resolution, private IP blocking, DNS-rebind prevention). Well-implemented security model.
- **`spawn("open", [url])`**: Located in `cli/src/client/board-auth.ts` — opens the dashboard URL in your browser for authentication. Standard UX pattern, not in the server.
- **`server.unref()`**: Used in port-availability checks and test cleanup. The persistent server concern is real but comes from the CLI layer (`companies.sh`), not the server source itself.

### Positive findings

- Full source is public, MIT-licensed, and auditable
- The CLI layer has clean, readable TypeScript
- `@paperclipai/server` source is public at github.com/paperclipai/paperclip (though npm artifact is compiled JS)
- Telemetry respects `DO_NOT_TRACK=1` and `CI=true`
- npm publishing uses GitHub Actions OIDC (not personal tokens)
- Plugin HTTP fetch has proper SSRF protection (DNS pinning, private IP blocking, protocol whitelist)
- Local disk storage has path traversal prevention (`resolveWithin` with `..` rejection)
- Agent instructions include "never exfiltrate" clauses (prompts, not access controls — but defense in depth)

---

## Trust Gates

Each gate is a checkpoint. **Do not proceed to the next gate unless the current one passes clean.**

### Gate 0: Static Analysis (no execution)

**Risk: zero.** Downloads packages as tarballs, unpacks, and scans with OSS tools + grep — never runs them.

```bash
# Quick scan (Trivy, Semgrep, Gitleaks, Socket + grep patterns)
./security/static-scan.sh

# Full analysis (all 7 tools + evidence bundle)
./security/analyze.sh > /tmp/security-evidence-$(date +%Y%m%d).md
```

**OSS tools used (optional — install for better coverage):**

| Tool | Install | What It Catches |
|------|---------|-----------------|
| Trivy | `brew install trivy` | CVEs in npm deps, hardcoded secrets, Dockerfile misconfigs |
| Semgrep | `brew install semgrep` | Code injection, dangerous APIs, security anti-patterns |
| Gitleaks | `brew install gitleaks` | Hardcoded secrets in source and git history |
| TruffleHog | `brew install trufflehog` | Secrets + verifies if credentials are still active |
| Grype | `brew install grype` | Vulnerabilities with SBOM generation (via Syft) |
| OpenSSF Scorecard | `brew install scorecard` | Repo security posture (branch protection, CI, signed releases) |
| Socket CLI | `npm i -g @socketsecurity/cli` | Install scripts, obfuscated code, typosquatting |

**What it checks (grep fallback, always runs):**
- Reads of sensitive paths (`.ssh`, `.aws`, `.gnupg`, keychains)
- `eval()` or `Function()` with dynamic input
- Child process spawning (`exec`, `spawn`, `fork`)
- Network calls to unknown endpoints
- Detached/background process creation
- S3 uploads or cloud exfiltration patterns
- Telemetry and tracking code
- Environment variable access

**Pass criteria:**
- No HIGH/CRITICAL CVEs without mitigations (Trivy/Grype)
- No leaked secrets (Gitleaks/TruffleHog)
- No supply chain attack signals (Socket)
- No reads of `~/.ssh`, `~/.aws`, or keychain paths
- No calls to unknown endpoints (only `api.anthropic.com`, `api.openai.com`, `registry.npmjs.org`)
- No `eval()` with user/external input

**Stop if:** you see active leaked credentials, HIGH/CRITICAL CVEs in reachable code paths, supply chain attack signals, sensitive path access, arbitrary eval, or outbound calls to unrecognized hosts.

---

### Gate 1: Sandbox with Allowlist

**Risk: low.** Code runs in a locked-down Docker container. All outbound traffic is routed through mitmproxy with a strict host allowlist — only hosts in `config/allowed-hosts.txt` are permitted. Everything else gets a 403 block response.

```bash
./scripts/start.sh
```

This starts three containers on a Docker internal network:

- **paperclip** — app server, only on `sandboxnet` (no direct internet)
- **mitmproxy** — allowlist-enforcing proxy, bridges `sandboxnet` ↔ `default` network
- **caddy gateway** — TLS-terminating reverse proxy, publishes the dashboard over HTTPS

Container restrictions:
- `--read-only` filesystem (tmpfs for `/tmp`)
- `--cap-drop ALL` (no Linux capabilities)
- `--security-opt no-new-privileges`
- `--memory 1g`
- `DO_NOT_TRACK=1`
- All traffic routed through mitmproxy via `HTTP_PROXY` env vars + Node 22 `--use-env-proxy`

**Monitor traffic** at http://localhost:8081 (password: `p`). Blocked requests appear as 403 responses with a clear message identifying the blocked host.

**Dashboard** at https://localhost:3100 (self-signed cert — accept the browser warning).

**What to verify:**
- All traffic goes to hosts in `config/allowed-hosts.txt`
- No blocked requests to unexpected hosts appear in the mitmproxy UI
- Request bodies contain only expected data (prompts, template downloads)
- No env vars, filesystem contents, or credentials in request payloads

**If you see blocked requests to a host you trust**, add it to `config/allowed-hosts.txt` and restart.

**After the run, stop and audit:**
```bash
./scripts/stop.sh
./security/audit-run.sh /tmp/paperclip-sandbox-marker-XXXXX
```

(The marker path is printed by `start.sh` at startup.)

**Pass criteria:**
- Only allowlisted hosts are contacted
- Request bodies contain only expected data
- No credentials or sensitive data in payloads
- Post-run audit shows no escaped processes, no files written outside `data/`, no new LaunchAgents

---

### Gate 2: Normal Operation

Only after Gates 0–1 pass clean.

```bash
./scripts/start.sh --open
```

This starts the paperclip container with full network access (no mitmproxy, no allowlist). The dashboard is at http://localhost:3100 (HTTP, no proxy).

Keep monitoring in a second terminal:
```bash
./scripts/monitor.sh
```

Run the post-audit after stopping:
```bash
./scripts/stop.sh
./security/audit-run.sh /tmp/paperclip-sandbox-marker-XXXXX
```

---

### Gate 3: Ongoing Hygiene

Once trust is established, maintain it:

- **Pin exact versions** in `docker/Dockerfile` — versions are set as `ARG` lines (see `VERSIONS.md` for integrity hashes)
- **Re-run Gates 0–1** before upgrading to any new version (see `docs/UPGRADE-CHECKLIST.md`)
- **Monitor API key usage** on provider dashboards after each session
- **Run the post-run audit** after every session: `./security/audit-run.sh`
- **Check for new LaunchAgents** periodically: `ls ~/Library/LaunchAgents/`
- **Back up before upgrades**: `./scripts/backup.sh`

---

## Credential Safety

Do this before any gate that uses real keys.

### Create scoped, rate-limited keys

| Provider | Action |
|----------|--------|
| **Anthropic** | Create a new key named `paperclip-sandbox-experiment` with a $5-10/month spend limit (Workspaces) |
| **OpenAI** | Create a new Project with a $10/month budget; create a key scoped to that Project |
| **Other services** | Only add after trust gates pass. Use test accounts with minimal permissions |

### Key handling rules

```bash
# WRONG — leaks to all child processes and shell history
export OPENAI_API_KEY=sk-...

# RIGHT — scoped to the project's .env file only
echo "OPENAI_API_KEY=sk-..." >> .env
```

- Never `export` API keys in your shell profile
- Never commit `.env` (already in `.gitignore`)
- Monitor usage on each provider's dashboard before and after test runs
- Revoke and rotate keys immediately if any gate fails unexpectedly

---

## Runtime Monitoring Tools

### File access (macOS)
```bash
sudo fs_usage -w -f filesys $(pgrep -d',' node) > /tmp/paperclip-sandbox-fs.log
```

### Network connections
```bash
# Real-time
nettop -p $(pgrep node) -d

# Snapshot
lsof -p $(pgrep node) | grep -E 'IPv4|IPv6|TCP'
```

### Process tree
```bash
ps aux | grep -iE "paperclip|companies|embedded-postgres|paperclip-sandbox" | grep -v grep
```

### Listening ports
```bash
lsof -i :3100 -P -n
```

### Quick post-run check
```bash
# Were any files written outside the project?
touch /tmp/before-run-marker  # create BEFORE the run
find ~ -newer /tmp/before-run-marker -type f 2>/dev/null \
  | grep -v "paperclip-sandbox\|Library/Caches\|.Trash\|.DS_Store" \
  | head -20

# New LaunchAgents?
ls ~/Library/LaunchAgents/

# Telemetry artifacts?
cat ~/.config/companies.sh/telemetry.json 2>/dev/null
```

---

## Files in This Directory

| File | Purpose |
|------|---------|
| `PLAYBOOK.md` | This document |
| `GETTING-STARTED.md` | Step-by-step setup guide for first-time evaluators |
| `SECURITY-ANALYSIS.md` | Security analysis report with tool results and risk assessment |
| `static-scan.sh` | Gate 0 — quick scan with OSS tools (Trivy, Semgrep, Gitleaks, Socket) + grep patterns |
| `analyze.sh` | Full analysis — all 7 OSS tools + evidence bundle generation |
| `audit-run.sh` | Post-run audit checking for files, processes, ports, telemetry |
| `analysis-prompt.md` | Prompt template used to generate security reports |
