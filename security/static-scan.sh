#!/usr/bin/env bash
set -euo pipefail

# static-scan.sh — Static analysis of npm packages before running them
# Usage: ./security/static-scan.sh
# Downloads and unpacks companies.sh + paperclipai without executing them,
# then runs OSS security tools and greps for dangerous patterns.
#
# This is Gate 0 — zero execution risk. Only downloads, unpacks, and scans.
#
# OSS tools used (optional — skipped if not installed):
#   - Trivy:     vulnerability + secret + misconfig scanner (brew install trivy)
#   - Semgrep:   pattern-based SAST scanner (brew install semgrep)
#   - Gitleaks:  secret scanner (brew install gitleaks)
#   - Socket CLI: supply chain attack detection (npm install -g @socketsecurity/cli)

SCAN_DIR="/tmp/paperclip-sandbox-static-scan"
rm -rf "$SCAN_DIR"
mkdir -p "$SCAN_DIR"
cd "$SCAN_DIR"

# --- Helpers ---
has_tool() { command -v "$1" &>/dev/null; }

scan_pattern() {
  local label="$1"
  local pattern="$2"
  local dir="$3"
  echo "--- $label ---"
  local results
  results=$(grep -rn "$pattern" "$dir" --include="*.js" --include="*.ts" --include="*.mjs" 2>/dev/null | grep -v "node_modules" | head -20) || true
  if [ -n "$results" ]; then
    echo "$results"
  else
    echo "(none found)"
  fi
  echo ""
}

echo "=== Static Security Scan ==="
echo "Working directory: $SCAN_DIR"
echo ""

# --- Tool availability ---
echo "--- Security Tool Status ---"
for tool in trivy semgrep gitleaks socket; do
  if has_tool "$tool"; then
    echo "  [INSTALLED] $tool"
  else
    echo "  [MISSING]   $tool"
  fi
done
echo ""
echo "Install missing tools for more comprehensive scanning."
echo "  brew install trivy semgrep gitleaks"
echo "  npm install -g @socketsecurity/cli"
echo ""

# --- Download packages without executing ---
echo "--- Downloading packages (no execution) ---"
npm pack companies.sh 2>/dev/null || { echo "ERROR: Failed to download companies.sh"; exit 1; }
npm pack paperclipai 2>/dev/null || { echo "ERROR: Failed to download paperclipai"; exit 1; }

mkdir -p companies-sh paperclipai
tar -xf companies.sh-*.tgz -C companies-sh --strip-components=1
tar -xf paperclipai-*.tgz -C paperclipai 2>/dev/null || true

echo "Downloaded and unpacked."
echo ""

# ============================================================
# OSS Tool Scans (run first — these provide the best signal)
# ============================================================

# --- Trivy: vulnerability + secret + misconfig scan ---
if has_tool trivy; then
  echo ""
  echo "========================================="
  echo "  TRIVY: Vulnerability & Secret Scan"
  echo "========================================="
  echo ""
  echo "--- companies.sh ---"
  trivy fs --scanners vuln,secret,misconfig --severity HIGH,CRITICAL companies-sh 2>&1 || true
  echo ""
  echo "--- paperclipai ---"
  trivy fs --scanners vuln,secret,misconfig --severity HIGH,CRITICAL paperclipai 2>&1 || true
  echo ""
fi

# --- Semgrep: SAST scan ---
if has_tool semgrep; then
  echo ""
  echo "========================================="
  echo "  SEMGREP: Static Application Security"
  echo "========================================="
  echo ""
  echo "--- companies.sh ---"
  semgrep scan --config auto --config "p/javascript" --config "p/nodejs" \
    --severity ERROR --severity WARNING \
    --no-git-ignore --quiet \
    companies-sh 2>&1 || true
  echo ""
  echo "--- paperclipai ---"
  semgrep scan --config auto --config "p/javascript" --config "p/nodejs" \
    --severity ERROR --severity WARNING \
    --no-git-ignore --quiet \
    paperclipai 2>&1 || true
  echo ""
fi

# --- Gitleaks: secret scanning ---
if has_tool gitleaks; then
  echo ""
  echo "========================================="
  echo "  GITLEAKS: Secret Detection"
  echo "========================================="
  echo ""
  echo "--- companies.sh ---"
  gitleaks detect --source companies-sh --no-git --verbose 2>&1 || true
  echo ""
  echo "--- paperclipai ---"
  gitleaks detect --source paperclipai --no-git --verbose 2>&1 || true
  echo ""
fi

# --- Socket CLI: supply chain attack detection ---
if has_tool socket; then
  echo ""
  echo "========================================="
  echo "  SOCKET: Supply Chain Attack Detection"
  echo "========================================="
  echo ""
  echo "--- companies.sh ---"
  socket npm info companies.sh 2>&1 || true
  echo ""
  echo "--- paperclipai ---"
  socket npm info paperclipai 2>&1 || true
  echo ""
fi

# ============================================================
# Manual Pattern Scanning (fallback / complement to tools)
# ============================================================

echo ""
echo "========================================="
echo "  SCANNING: companies.sh (grep patterns)"
echo "========================================="
echo ""

scan_pattern "Sensitive path access (.ssh, .aws, .gnupg, keychain)" \
  '\.ssh\|\.aws\|\.gnupg\|[Kk]eychain' companies-sh

scan_pattern "eval / Function constructor" \
  'eval(\|Function(' companies-sh

scan_pattern "Child process spawning" \
  'exec\|spawn\|execSync\|spawnSync\|fork(' companies-sh

scan_pattern "Network requests (fetch, http, axios)" \
  'fetch(\|axios\|http\.request\|https\.request\|\.post(\|\.get(' companies-sh

scan_pattern "Environment variable access" \
  'process\.env' companies-sh

scan_pattern "File system writes outside cwd" \
  'writeFile\|writeSync\|appendFile\|mkdirSync\|createWriteStream' companies-sh

scan_pattern "Telemetry / analytics / tracking" \
  'telemetry\|analytics\|tracking\|beacon\|ingest' companies-sh

echo ""
echo "========================================="
echo "  SCANNING: paperclipai (grep patterns)"
echo "========================================="
echo ""

scan_pattern "Sensitive path access (.ssh, .aws, .gnupg, keychain)" \
  '\.ssh\|\.aws\|\.gnupg\|[Kk]eychain' paperclipai

scan_pattern "eval / Function constructor" \
  'eval(\|Function(' paperclipai

scan_pattern "Child process spawning" \
  'exec\|spawn\|execSync\|spawnSync\|fork(' paperclipai

scan_pattern "Network requests" \
  'fetch(\|axios\|http\.request\|https\.request' paperclipai

scan_pattern "Environment variable access" \
  'process\.env' paperclipai

scan_pattern "File system writes outside cwd" \
  'writeFile\|writeSync\|appendFile\|mkdirSync\|createWriteStream' paperclipai

scan_pattern "Telemetry / analytics / tracking" \
  'telemetry\|analytics\|tracking\|beacon\|ingest' paperclipai

scan_pattern "Background/detached process creation" \
  'detached\|unref\|daemon\|background' paperclipai

scan_pattern "S3/cloud upload" \
  'S3\|putObject\|upload\|bucket' paperclipai

echo ""
echo "=== Scan Complete ==="
echo "Review the output above. Look for:"
echo "  - Reads of sensitive paths (.ssh, .aws, keychains)"
echo "  - eval() or Function() with dynamic input"
echo "  - Network calls to unknown endpoints"
echo "  - Detached background processes"
echo "  - S3 uploads or cloud exfiltration"
echo "  - HIGH/CRITICAL vulnerabilities from Trivy"
echo "  - Semgrep security findings"
echo "  - Leaked secrets from Gitleaks"
echo "  - Supply chain alerts from Socket"
echo ""
echo "Scan artifacts are in: $SCAN_DIR"
echo "Clean up with: rm -rf $SCAN_DIR"
