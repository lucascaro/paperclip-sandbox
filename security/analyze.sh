#!/usr/bin/env bash
set -euo pipefail

# analyze.sh — Gather security evidence for paperclipai/companies.sh packages
# Usage: ./security/analyze.sh [--versions-file VERSIONS.md]
#
# Outputs a structured evidence bundle (Markdown) to stdout.
# Pipe to a file or feed directly to the analysis prompt template.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSIONS_FILE="${1:-$REPO_DIR/VERSIONS.md}"
SCAN_DIR="/tmp/paperclip-sandbox-security-analysis"

# --- Parse pinned versions from VERSIONS.md ---
parse_version() {
  local pkg="$1"
  grep "| \`$pkg\`" "$VERSIONS_FILE" | sed 's/.*| `\([^`]*\)` .*/\1/' | head -1
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

# ============================================================
# BEGIN OUTPUT
# ============================================================

cat <<EOF
# Security Analysis Evidence Bundle

- Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
- Generator: security/analyze.sh
- Versions file: $VERSIONS_FILE

EOF

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
tar -xf paperclipai-*.tgz -C paperclipai --strip-components=1 2>/dev/null || true

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

# --- Section 7: Version diff (if previous report exists) ---
section "7. Version Changes"

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

# --- Section 8: Integrity Verification ---
section "8. Integrity Hashes"

echo "| Package | SHA-512 |"
echo "|---------|---------|"
cd "$SCAN_DIR"
for tgz in *.tgz; do
  hash=$(shasum -a 512 "$tgz" | cut -d' ' -f1 | xxd -r -p | base64 2>/dev/null || shasum -a 512 "$tgz" | cut -d' ' -f1)
  echo "| $tgz | \`sha512-${hash}\` |"
done
echo ""

# --- Cleanup note ---
section "9. Artifacts"

echo "Scan artifacts are in: $SCAN_DIR"
echo "Clean up with: \`rm -rf $SCAN_DIR\`"
echo ""
echo "---"
echo "*Evidence gathered automatically by security/analyze.sh*"
