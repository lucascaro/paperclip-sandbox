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
- Telemetry respects `DO_NOT_TRACK=1` and `CI=true`
- npm publishing uses GitHub Actions OIDC (not personal tokens)
- Plugin HTTP fetch has proper SSRF protection (DNS pinning, private IP blocking, protocol whitelist)
- Local disk storage has path traversal prevention (`resolveWithin` with `..` rejection)
- Agent instructions include "never exfiltrate" clauses (prompts, not access controls — but defense in depth)

---

## Trust Gates

Each gate is a checkpoint. **Do not proceed to the next gate unless the current one passes clean.**

### Gate 0: Static Analysis (no execution)

**Risk: zero.** Downloads packages as tarballs, unpacks, and greps — never runs them.

```bash
./security/static-scan.sh
```

**What it checks:**
- Reads of sensitive paths (`.ssh`, `.aws`, `.gnupg`, keychains)
- `eval()` or `Function()` with dynamic input
- Child process spawning (`exec`, `spawn`, `fork`)
- Network calls to unknown endpoints
- Detached/background process creation
- S3 uploads or cloud exfiltration patterns
- Telemetry and tracking code
- Environment variable access

**Pass criteria:**
- No reads of `~/.ssh`, `~/.aws`, or keychain paths
- No calls to unknown endpoints (only `api.anthropic.com`, `api.openai.com`, `registry.npmjs.org`)
- No `eval()` with user/external input

**Stop if:** you see sensitive path access, arbitrary eval, or outbound calls to unrecognized hosts.

---

### Gate 1: Docker — No Network

**Risk: minimal.** Code runs in a locked-down container that cannot reach the internet.

```bash
./security/run-sandboxed.sh
```

Container restrictions:
- `--network none` (no internet)
- `--read-only` filesystem
- `--cap-drop ALL` (no Linux capabilities)
- `--security-opt no-new-privileges`
- `--memory 512m`
- `DO_NOT_TRACK=1`

**Pass criteria:**
- Process starts and attempts network calls, fails gracefully
- Only `api.anthropic.com`, `api.openai.com` appear in error logs
- No crashes or unexpected behavior

**After the run, audit:**
```bash
./security/audit-run.sh /tmp/paperclip-sandbox-run-marker-XXXXX
```

---

### Gate 2: mitmproxy Monitored Run

**Risk: low.** Code can reach the internet, but every HTTPS request is intercepted and logged.

**Prerequisites:**
```bash
brew install mitmproxy
```

**Terminal 1 — start the proxy:**
```bash
mitmproxy --mode regular --listen-port 8080 -w /tmp/paperclip-sandbox-traffic.mitm
```

**Terminal 2 — run through the proxy:**
```bash
./security/run-sandboxed.sh --proxy
```

**After the run, review all traffic:**
```bash
mitmweb -r /tmp/paperclip-sandbox-traffic.mitm
# Opens a browser UI showing every request, headers, and bodies
```

**Pass criteria:**
- ALL traffic goes to known-good endpoints only
- Request bodies contain only expected data (prompts, site configs)
- No env vars, filesystem contents, or credentials in request payloads
- No calls to unknown AWS endpoints, S3 buckets, or third-party servers

---

### Gate 3: Filesystem-Sandboxed Direct Run

**Risk: moderate.** Code runs on the host (not Docker) with filesystem restrictions.

Use the macOS `sandbox-exec` profile:
```bash
sandbox-exec -f sandbox.sb /path/to/node $(which npx) companies.sh add paperclipai/companies/default
```

Monitor file access in a second terminal:
```bash
sudo fs_usage -w -f filesys $(pgrep -d',' node) | tee /tmp/paperclip-sandbox-fs.log
```

After the run, check for access outside the project:
```bash
grep -v "/usr/lib\|/System\|/private/tmp\|paperclip-sandbox\|/dev/" /tmp/paperclip-sandbox-fs.log | head -50
```

**Pass criteria:**
- No file access attempts outside the project directory (beyond system libraries)

**Note:** `sandbox-exec` is deprecated by Apple. It works on macOS 13/14/15 but may be removed in the future. Docker (Gates 1-2) is the stronger isolation boundary.

---

### Gate 4: Normal Operation with Monitoring

Only after Gates 0-3 pass clean.

```bash
./security/run-sandboxed.sh --network
```

Keep monitoring in a second terminal:
```bash
# Watch network connections
watch -n 1 "lsof -i -P -n | grep -iE 'node|postgres' | head -20"
```

Run the post-audit:
```bash
./security/audit-run.sh /tmp/paperclip-sandbox-run-marker-XXXXX
```

---

### Gate 5: Ongoing Hygiene

Once trust is established, maintain it:

- **Pin the exact version** in `package.json` (e.g., `"companies.sh": "2026.325.2"`, not `"^2026.325.2"`)
- **Re-run Gates 0-2** before upgrading to any new version
- **Monitor API key usage** on provider dashboards after each session
- **Check for new LaunchAgents** periodically: `ls ~/Library/LaunchAgents/`
- **Kill the background server** when not in use: `lsof -i :3100` then `kill <pid>`

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
| `static-scan.sh` | Gate 0 — download and grep packages without executing |
| `run-sandboxed.sh` | Gates 1-4 — Docker wrapper with network/proxy modes |
| `audit-run.sh` | Post-run audit checking for files, processes, ports, telemetry |
| `../sandbox.sb` | macOS `sandbox-exec` profile for Gate 3 |
| `../Dockerfile.sandbox` | Hardened Docker container definition |
