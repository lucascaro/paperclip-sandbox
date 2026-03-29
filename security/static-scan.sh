#!/usr/bin/env bash
set -euo pipefail

# static-scan.sh — Static analysis of npm packages before running them
# Usage: ./security/static-scan.sh
# Downloads and unpacks companies.sh + paperclipai without executing them,
# then greps for dangerous patterns.

SCAN_DIR="/tmp/paperclip-sandbox-static-scan"
rm -rf "$SCAN_DIR"
mkdir -p "$SCAN_DIR"
cd "$SCAN_DIR"

echo "=== Static Security Scan ==="
echo "Working directory: $SCAN_DIR"
echo ""

# --- Download packages without executing ---
echo "--- Downloading packages (no execution) ---"
npm pack companies.sh 2>/dev/null || { echo "ERROR: Failed to download companies.sh"; exit 1; }
npm pack paperclipai 2>/dev/null || { echo "ERROR: Failed to download paperclipai"; exit 1; }

mkdir -p companies-sh paperclipai
tar -xf companies.sh-*.tgz -C companies-sh --strip-components=1
tar -xf paperclipai-*.tgz -C paperclipai --strip-components=1

echo "Downloaded and unpacked."
echo ""

# --- Scan functions ---
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

echo ""
echo "========================================="
echo "  SCANNING: companies.sh"
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
echo "  SCANNING: paperclipai"
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
echo ""
echo "Scan artifacts are in: $SCAN_DIR"
echo "Clean up with: rm -rf $SCAN_DIR"
