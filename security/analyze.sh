#!/usr/bin/env bash
set -euo pipefail

# analyze.sh — Gather security evidence for paperclipai/companies.sh packages
# Usage: ./security/analyze.sh [--versions-file VERSIONS.md]
#
# Outputs a structured evidence bundle (Markdown) to stdout.
# Pipe to a file or feed directly to the analysis prompt template.
#
# Integrates the following OSS security tools (optional — skipped if not installed):
#   - Trivy:            container/filesystem vulnerability scanner (brew install trivy)
#   - Grype:            vulnerability scanner with SBOM support (brew install grype)
#   - Semgrep:          pattern-based SAST scanner (brew install semgrep)
#   - Gitleaks:         secret scanner for git repos (brew install gitleaks)
#   - TruffleHog:       secret scanner with credential verification (brew install trufflehog)
#   - OpenSSF Scorecard: GitHub repo security posture scoring (brew install scorecard)
#   - Socket CLI:       supply chain attack detection (npm install -g @socketsecurity/cli)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSIONS_FILE="${1:-$REPO_DIR/VERSIONS.md}"
SCAN_DIR="/tmp/paperclip-sandbox-security-analysis"

# --- Parse pinned versions from VERSIONS.md ---
parse_version() {
  local pkg="$1"
  grep "| \`$pkg\`" "$VERSIONS_FILE" | sed 's/.*| `[^`]*` | `\([^`]*\)`.*/\1/' | head -1
}

CLI_VERSION=$(parse_version "companies.sh")
SERVER_VERSION=$(parse_version "paperclipai")
RUNTIME_VERSION=$(parse_version "@paperclipai/server")

if [ -z "$CLI_VERSION" ] || [ -z "$SERVER_VERSION" ]; then
  echo "ERROR: Could not parse versions from $VERSIONS_FILE" >&2
  exit 1
fi

# --- Setup ---
rm -rf "$SCAN_DIR"
mkdir -p "$SCAN_DIR"

# --- Helper: section header ---
section() { echo ""; echo "## $1"; echo ""; }
subsection() { echo "### $1"; echo ""; }

# --- Helper: scan for patterns ---
scan_pattern() {
  local label="$1"
  local pattern="$2"
  local dir="$3"
  echo "**$label**"
  echo ""
  local results
  results=$(grep -rn "$pattern" "$dir" --include="*.js" --include="*.ts" --include="*.mjs" 2>/dev/null | grep -v "node_modules" | head -30) || true
  if [ -n "$results" ]; then
    echo '```'
    echo "$results"
    echo '```'
  else
    echo "(none found)"
  fi
  echo ""
}

# --- Helper: check if a tool is available ---
has_tool() {
  command -v "$1" &>/dev/null
}

# --- Helper: print skip message for missing tool ---
skip_tool() {
  local install_hint="$1"
  local description="$2"
  echo "**Status:** SKIPPED — not installed"
  echo ""
  echo "Install with: \`$install_hint\`"
  echo ""
  echo "*$description*"
  echo ""
}

# ============================================================
# BEGIN OUTPUT
# ============================================================

cat <<EOF
# Security Analysis Evidence Bundle

- Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
- Generator: security/analyze.sh
- Versions file: $VERSIONS_FILE

EOF

# --- Tool availability summary ---
section "0. Security Tool Inventory"

echo "| Tool | Installed | Purpose |"
echo "|------|-----------|---------|"
for tool_entry in \
  "trivy|brew install trivy|Container/filesystem vulnerability scanner" \
  "grype|brew install grype|Vulnerability scanner with SBOM support" \
  "semgrep|brew install semgrep|Pattern-based SAST scanner" \
  "gitleaks|brew install gitleaks|Secret scanner for git history" \
  "trufflehog|brew install trufflehog|Secret scanner with credential verification" \
  "scorecard|brew install scorecard|OpenSSF repo security scoring (requires GITHUB_TOKEN)" \
  "socket|npm i -g @socketsecurity/cli|Supply chain attack detection"; do
  tool_name="${tool_entry%%|*}"
  rest="${tool_entry#*|}"
  tool_desc="${rest#*|}"
  if has_tool "$tool_name"; then
    echo "| \`$tool_name\` | YES | $tool_desc |"
  else
    echo "| \`$tool_name\` | NO | $tool_desc |"
  fi
done
echo ""

# --- Section 1: Package Metadata ---
section "1. Package Versions"

echo "| Package | Pinned Version |"
echo "|---------|---------------|"
echo "| companies.sh | $CLI_VERSION |"
echo "| paperclipai | $SERVER_VERSION |"
echo "| @paperclipai/server | $RUNTIME_VERSION |"
echo ""

section "2. npm Registry Metadata"

for pkg in "companies.sh" "paperclipai" "@paperclipai/server"; do
  subsection "$pkg"
  # Fetch metadata; timeout after 10s
  meta=$(npm view "$pkg" --json 2>/dev/null || echo '{"error": "failed to fetch"}')
  echo '```json'
  echo "$meta" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    out = {
        'name': d.get('name'),
        'version': d.get('version'),
        'description': d.get('description'),
        'license': d.get('license'),
        'homepage': d.get('homepage'),
        'repository': d.get('repository'),
        'maintainers': d.get('maintainers'),
        'dist-tags': d.get('dist-tags'),
        'dependencies_count': len(d.get('dependencies', {})),
        'dependencies': list(d.get('dependencies', {}).keys()),
    }
    json.dump(out, sys.stdout, indent=2)
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null || echo "$meta"
  echo ""
  echo '```'
  echo ""
done

# --- Section 3: Download and unpack ---
section "3. Package Download & Integrity"

cd "$SCAN_DIR"

for pkg_spec in "companies.sh@$CLI_VERSION" "paperclipai@$SERVER_VERSION"; do
  pkg_name="${pkg_spec%%@*}"
  echo "**$pkg_spec**"
  echo ""
  echo '```'
  npm pack "$pkg_spec" 2>&1 || echo "ERROR: Failed to download $pkg_spec"
  echo '```'
  echo ""
done

# Unpack
mkdir -p companies-sh paperclipai
tar -xf companies.sh-*.tgz -C companies-sh --strip-components=1 2>/dev/null || true
tar -xf paperclipai-*.tgz -C paperclipai 2>/dev/null || true

# File counts
echo "**File counts:**"
echo ""
echo "| Package | Files | Size |"
echo "|---------|-------|------|"
echo "| companies.sh | $(find companies-sh -type f | wc -l | tr -d ' ') | $(du -sh companies-sh 2>/dev/null | cut -f1) |"
echo "| paperclipai | $(find paperclipai -type f | wc -l | tr -d ' ') | $(du -sh paperclipai 2>/dev/null | cut -f1) |"
echo ""

# --- Section 4: Dependency Tree ---
section "4. Dependency Tree"

for pkg_spec in "companies.sh@$CLI_VERSION" "paperclipai@$SERVER_VERSION"; do
  subsection "$pkg_spec"
  echo '```'
  npm view "$pkg_spec" dependencies --json 2>/dev/null || echo "{}"
  echo '```'
  echo ""
done

# --- Section 5: npm audit ---
section "5. Known Vulnerabilities (npm audit)"

# Create a temporary package.json for auditing
cat > "$SCAN_DIR/package.json" <<PKGJSON
{
  "name": "paperclip-sandbox-audit",
  "private": true,
  "dependencies": {
    "companies.sh": "$CLI_VERSION",
    "paperclipai": "$SERVER_VERSION"
  }
}
PKGJSON

echo '```'
cd "$SCAN_DIR"
npm audit --json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    vulns = d.get('vulnerabilities', {})
    if not vulns:
        print('No known vulnerabilities found.')
    else:
        print(f'Found {len(vulns)} vulnerable package(s):')
        for name, info in vulns.items():
            severity = info.get('severity', 'unknown')
            via = [v if isinstance(v, str) else v.get('title', '?') for v in info.get('via', [])]
            print(f'  - {name}: {severity} (via: {\", \".join(via)})')
except Exception as e:
    print(f'Audit parse error: {e}')
" 2>/dev/null || echo "npm audit failed or not available"
echo '```'
echo ""

# --- Section 6: Static Pattern Scan ---
section "6. Static Pattern Scan"

subsection "6.1 companies.sh"

scan_pattern "Sensitive path access (.ssh, .aws, .gnupg, keychain)" \
  '\.ssh\|\.aws\|\.gnupg\|[Kk]eychain' "$SCAN_DIR/companies-sh"

scan_pattern "eval / Function constructor" \
  'eval(\|Function(' "$SCAN_DIR/companies-sh"

scan_pattern "Child process spawning" \
  'exec\|spawn\|execSync\|spawnSync\|fork(' "$SCAN_DIR/companies-sh"

scan_pattern "Network requests (fetch, http, axios)" \
  'fetch(\|axios\|http\.request\|https\.request\|\.post(\|\.get(' "$SCAN_DIR/companies-sh"

scan_pattern "Environment variable access" \
  'process\.env' "$SCAN_DIR/companies-sh"

scan_pattern "File system writes" \
  'writeFile\|writeSync\|appendFile\|mkdirSync\|createWriteStream' "$SCAN_DIR/companies-sh"

scan_pattern "Telemetry / analytics / tracking" \
  'telemetry\|analytics\|tracking\|beacon\|ingest' "$SCAN_DIR/companies-sh"

subsection "6.2 paperclipai"

scan_pattern "Sensitive path access (.ssh, .aws, .gnupg, keychain)" \
  '\.ssh\|\.aws\|\.gnupg\|[Kk]eychain' "$SCAN_DIR/paperclipai"

scan_pattern "eval / Function constructor" \
  'eval(\|Function(' "$SCAN_DIR/paperclipai"

scan_pattern "Child process spawning" \
  'exec\|spawn\|execSync\|spawnSync\|fork(' "$SCAN_DIR/paperclipai"

scan_pattern "Network requests" \
  'fetch(\|axios\|http\.request\|https\.request' "$SCAN_DIR/paperclipai"

scan_pattern "Environment variable access" \
  'process\.env' "$SCAN_DIR/paperclipai"

scan_pattern "File system writes" \
  'writeFile\|writeSync\|appendFile\|mkdirSync\|createWriteStream' "$SCAN_DIR/paperclipai"

scan_pattern "Telemetry / analytics / tracking" \
  'telemetry\|analytics\|tracking\|beacon\|ingest' "$SCAN_DIR/paperclipai"

scan_pattern "Background/detached process creation" \
  'detached\|unref\|daemon\|background' "$SCAN_DIR/paperclipai"

scan_pattern "S3/cloud upload" \
  'S3\|putObject\|upload\|bucket' "$SCAN_DIR/paperclipai"

scan_pattern "Crypto operations" \
  'crypto\.\|createHash\|createCipher\|randomBytes' "$SCAN_DIR/paperclipai"

# ============================================================
# Section 7: OSS Security Tool Scans
# ============================================================

section "7. OSS Security Tool Results"

echo "> Tools are run when available. Install missing tools for more comprehensive results."
echo ""

# -------------------------------------------------------
# 7.1 Trivy — filesystem vulnerability scan
# -------------------------------------------------------
subsection "7.1 Trivy (Vulnerability Scanner)"

if has_tool trivy; then
  echo "**Status:** INSTALLED ($(command -v trivy))"
  echo ""
  echo "#### Filesystem scan: companies.sh"
  echo ""
  echo '```'
  trivy fs --scanners vuln,secret,misconfig --severity HIGH,CRITICAL "$SCAN_DIR/companies-sh" 2>&1 || echo "(trivy scan completed with errors)"
  echo '```'
  echo ""
  echo "#### Filesystem scan: paperclipai"
  echo ""
  echo '```'
  trivy fs --scanners vuln,secret,misconfig --severity HIGH,CRITICAL "$SCAN_DIR/paperclipai" 2>&1 || echo "(trivy scan completed with errors)"
  echo '```'
  echo ""
  if command -v docker &>/dev/null && docker image inspect paperclip-sandbox:latest &>/dev/null 2>&1; then
    echo "#### Docker image scan: paperclip-sandbox"
    echo ""
    echo '```'
    trivy image --severity HIGH,CRITICAL paperclip-sandbox:latest 2>&1 || echo "(trivy image scan completed with errors)"
    echo '```'
  else
    echo "#### Docker image scan: SKIPPED (image not built yet)"
  fi
  echo ""
else
  skip_tool "brew install trivy" "Trivy scans npm packages for known CVEs and misconfigurations."
fi

# -------------------------------------------------------
# 7.2 Grype — vulnerability scan with SBOM
# -------------------------------------------------------
subsection "7.2 Grype (Vulnerability Scanner)"

if has_tool grype; then
  echo "**Status:** INSTALLED ($(command -v grype))"
  echo ""
  echo "#### Filesystem scan: companies.sh"
  echo ""
  echo '```'
  grype dir:"$SCAN_DIR/companies-sh" --only-fixed --add-cpes-if-none 2>&1 || echo "(grype scan completed with errors)"
  echo '```'
  echo ""
  echo "#### Filesystem scan: paperclipai"
  echo ""
  echo '```'
  grype dir:"$SCAN_DIR/paperclipai" --only-fixed --add-cpes-if-none 2>&1 || echo "(grype scan completed with errors)"
  echo '```'
  echo ""
  if has_tool syft; then
    echo "#### SBOM (Software Bill of Materials)"
    echo ""
    echo '```'
    syft dir:"$SCAN_DIR/paperclipai" -o table 2>&1 | head -50
    echo '```'
    echo ""
    echo "(Full SBOM saved to $SCAN_DIR/sbom-paperclipai.json)"
    syft dir:"$SCAN_DIR/paperclipai" -o spdx-json > "$SCAN_DIR/sbom-paperclipai.json" 2>/dev/null || true
  fi
  echo ""
else
  skip_tool "brew install grype" "Grype scans filesystem and container images for known vulnerabilities, with SBOM generation via Syft."
fi

# -------------------------------------------------------
# 7.3 Semgrep — SAST (Static Application Security Testing)
# -------------------------------------------------------
subsection "7.3 Semgrep (SAST Scanner)"

if has_tool semgrep; then
  echo "**Status:** INSTALLED ($(command -v semgrep))"
  echo ""
  echo "#### companies.sh — security audit rules"
  echo ""
  echo '```'
  semgrep scan --config auto --config "p/javascript" --config "p/nodejs" \
    --severity ERROR --severity WARNING \
    --no-git-ignore --quiet \
    "$SCAN_DIR/companies-sh" 2>&1 || echo "(semgrep scan completed with errors)"
  echo '```'
  echo ""
  echo "#### paperclipai — security audit rules"
  echo ""
  echo '```'
  semgrep scan --config auto --config "p/javascript" --config "p/nodejs" \
    --severity ERROR --severity WARNING \
    --no-git-ignore --quiet \
    "$SCAN_DIR/paperclipai" 2>&1 || echo "(semgrep scan completed with errors)"
  echo '```'
  echo ""
  echo "#### Supply chain risk patterns"
  echo ""
  echo '```'
  semgrep scan --config "p/supply-chain" \
    --no-git-ignore --quiet \
    "$SCAN_DIR/paperclipai" 2>&1 || echo "(no supply-chain rules matched or scan completed with errors)"
  echo '```'
  echo ""
else
  skip_tool "brew install semgrep" "Semgrep performs pattern-based static analysis to find security issues, code injection, and dangerous API usage."
fi

# -------------------------------------------------------
# 7.4 Gitleaks — secret scanning
# -------------------------------------------------------
subsection "7.4 Gitleaks (Secret Scanner)"

if has_tool gitleaks; then
  echo "**Status:** INSTALLED ($(command -v gitleaks))"
  echo ""
  echo "#### Scanning downloaded packages for secrets"
  echo ""
  echo '```'
  gitleaks detect --source "$SCAN_DIR/companies-sh" --no-git --verbose 2>&1 || true
  echo ""
  gitleaks detect --source "$SCAN_DIR/paperclipai" --no-git --verbose 2>&1 || true
  echo '```'
  echo ""
  UPSTREAM_DIR="$SCAN_DIR/paperclip-upstream"
  if [ -d "$UPSTREAM_DIR" ]; then
    echo "#### Scanning upstream git history"
    echo ""
    echo '```'
    gitleaks detect --source "$UPSTREAM_DIR" --verbose 2>&1 || true
    echo '```'
  else
    echo "#### Upstream git history: SKIPPED"
    echo ""
    echo "Clone the upstream repo to scan git history:"
    echo "\`git clone --depth=50 https://github.com/paperclipai/paperclip.git $UPSTREAM_DIR\`"
  fi
  echo ""
else
  skip_tool "brew install gitleaks" "Gitleaks scans for hardcoded secrets, API keys, and credentials in source code and git history."
fi

# -------------------------------------------------------
# 7.5 TruffleHog — secret scanning with verification
# -------------------------------------------------------
subsection "7.5 TruffleHog (Secret Scanner with Verification)"

if has_tool trufflehog; then
  echo "**Status:** INSTALLED ($(command -v trufflehog))"
  echo ""
  echo "#### Scanning downloaded packages"
  echo ""
  echo '```'
  trufflehog filesystem --directory "$SCAN_DIR/companies-sh" --no-update 2>&1 || true
  echo ""
  trufflehog filesystem --directory "$SCAN_DIR/paperclipai" --no-update 2>&1 || true
  echo '```'
  echo ""
  echo "#### Scanning upstream GitHub repo"
  echo ""
  echo '```'
  trufflehog github --repo https://github.com/paperclipai/paperclip --no-update 2>&1 || true
  echo '```'
  echo ""
else
  skip_tool "brew install trufflehog" "TruffleHog scans for secrets and verifies whether discovered credentials are still active."
fi

# -------------------------------------------------------
# 7.6 OpenSSF Scorecard — repo security posture
# -------------------------------------------------------
subsection "7.6 OpenSSF Scorecard (Repo Security Posture)"

if has_tool scorecard && [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "**Status:** INSTALLED ($(command -v scorecard))"
  echo ""
  echo "#### github.com/paperclipai/paperclip"
  echo ""
  echo '```'
  scorecard --repo=github.com/paperclipai/paperclip --format=default 2>&1 || echo "(scorecard completed with errors)"
  echo '```'
  echo ""
  echo "#### Detailed check breakdown"
  echo ""
  echo '```'
  scorecard --repo=github.com/paperclipai/paperclip \
    --checks=Binary-Artifacts,Branch-Protection,Code-Review,Dangerous-Workflow,Dependency-Update-Tool,Maintained,Pinned-Dependencies,SAST,Security-Policy,Signed-Releases,Token-Permissions,Vulnerabilities \
    --format=default 2>&1 || echo "(detailed scorecard completed with errors)"
  echo '```'
  echo ""
elif has_tool scorecard; then
  echo "**Status:** SKIPPED — \`GITHUB_TOKEN\` not set (required to avoid rate limiting)"
  echo ""
  echo "Run with: \`GITHUB_TOKEN=ghp_... ./security/analyze.sh\`"
  echo ""
else
  skip_tool "brew install scorecard" "OpenSSF Scorecard evaluates GitHub repos on security practices: branch protection, signed releases, CI, dependency management, and more."
fi

# -------------------------------------------------------
# 7.7 Socket CLI — supply chain attack detection
# -------------------------------------------------------
subsection "7.7 Socket CLI (Supply Chain Attack Detection)"

if has_tool socket; then
  echo "**Status:** INSTALLED ($(command -v socket))"
  echo ""
  echo "#### Scanning companies.sh"
  echo ""
  echo '```'
  socket npm info "companies.sh@$CLI_VERSION" 2>&1 || echo "(socket scan completed with errors)"
  echo '```'
  echo ""
  echo "#### Scanning paperclipai"
  echo ""
  echo '```'
  socket npm info "paperclipai@$SERVER_VERSION" 2>&1 || echo "(socket scan completed with errors)"
  echo '```'
  echo ""
else
  skip_tool "npm install -g @socketsecurity/cli" "Socket detects supply chain attacks: install scripts, obfuscated code, network access, shell exec in dependencies, typosquatting, and more."
fi

# --- Section 8: Version diff (if previous report exists) ---
section "8. Version Changes"

PREV_REPORT="$REPO_DIR/security/SECURITY-ANALYSIS.md"
if [ -f "$PREV_REPORT" ]; then
  prev_cli=$(grep -o 'companies.sh v[0-9.]*' "$PREV_REPORT" | head -1 | sed 's/companies.sh v//')
  prev_srv=$(grep -o 'paperclipai v[0-9.]*' "$PREV_REPORT" | head -1 | sed 's/paperclipai v//')
  echo "Previous analysis versions: companies.sh=$prev_cli, paperclipai=$prev_srv"
  echo "Current versions: companies.sh=$CLI_VERSION, paperclipai=$SERVER_VERSION"
  echo ""
  if [ "$prev_cli" = "$CLI_VERSION" ] && [ "$prev_srv" = "$SERVER_VERSION" ]; then
    echo "**No version change since last analysis.**"
  else
    echo "**Version change detected — full re-analysis recommended.**"
  fi
else
  echo "No previous analysis found. This is the first analysis."
fi
echo ""

# --- Section 9: Integrity Verification ---
section "9. Integrity Hashes"

echo "| Package | SHA-512 |"
echo "|---------|---------|"
cd "$SCAN_DIR"
for tgz in *.tgz; do
  hash=$(shasum -a 512 "$tgz" | cut -d' ' -f1 | xxd -r -p | base64 2>/dev/null || shasum -a 512 "$tgz" | cut -d' ' -f1)
  echo "| $tgz | \`sha512-${hash}\` |"
done
echo ""

# --- Cleanup note ---
section "10. Artifacts"

echo "Scan artifacts are in: $SCAN_DIR"
echo "Clean up with: \`rm -rf $SCAN_DIR\`"
echo ""
echo "---"
echo "*Evidence gathered automatically by security/analyze.sh*"
