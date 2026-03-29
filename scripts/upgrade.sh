#!/usr/bin/env bash
set -euo pipefail

# upgrade.sh — Guided upgrade flow for paperclipai packages.
# Walks through the trust gates before applying a version bump.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Paperclip Sandbox — Upgrade Flow ==="
echo ""

# Show current vs. latest
"$SCRIPT_DIR/check-versions.sh"
echo ""

# Prompt for new versions
read -p "New companies.sh version (or Enter to skip): " NEW_COMPANIES
read -p "New paperclipai version (or Enter to skip): " NEW_PAPERCLIP

if [ -z "$NEW_COMPANIES" ] && [ -z "$NEW_PAPERCLIP" ]; then
  echo "No versions specified. Exiting."
  exit 0
fi

echo ""
echo "=== Step 1: Backup current data ==="
"$SCRIPT_DIR/backup.sh"

echo ""
echo "=== Step 2: Static scan of new versions (Gate 0) ==="
echo "Running static scan..."
"$PROJECT_DIR/security/static-scan.sh"

echo ""
echo "Review the scan output above."
read -p "Does the scan look clean? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Upgrade aborted. No changes made."
  exit 1
fi

echo ""
echo "=== Step 3: Update pinned versions ==="

if [ -n "$NEW_COMPANIES" ]; then
  echo "Updating Dockerfile: companies.sh → $NEW_COMPANIES"
  sed -i '' "s/ARG COMPANIES_SH_VERSION=.*/ARG COMPANIES_SH_VERSION=$NEW_COMPANIES/" "$PROJECT_DIR/docker/Dockerfile"
fi

if [ -n "$NEW_PAPERCLIP" ]; then
  echo "Updating Dockerfile: paperclipai → $NEW_PAPERCLIP"
  sed -i '' "s/ARG PAPERCLIPAI_VERSION=.*/ARG PAPERCLIPAI_VERSION=$NEW_PAPERCLIP/" "$PROJECT_DIR/docker/Dockerfile"
fi

echo ""
echo "=== Step 4: Rebuild container ==="
echo "Stop existing container..."
"$SCRIPT_DIR/stop.sh" 2>/dev/null || true

echo ""
echo "=== Step 5: Gate 1 — Isolated run (no network) ==="
echo "Starting in isolated mode..."
echo "Press Ctrl+C once you've reviewed the logs, then continue."
echo ""
"$SCRIPT_DIR/start.sh" --isolated || true

echo ""
read -p "Did Gate 1 pass? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Upgrade aborted. Revert Dockerfile changes manually."
  exit 1
fi

echo ""
echo "=== Step 6: Gate 2 — Proxy run (mitmproxy) ==="
read -p "Run Gate 2 with mitmproxy? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  "$SCRIPT_DIR/start.sh" --proxy || true
  echo ""
  read -p "Did Gate 2 pass? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Upgrade aborted. Revert Dockerfile changes manually."
    exit 1
  fi
fi

echo ""
echo "=== Step 7: Update VERSIONS.md ==="
echo ""
echo "Please update VERSIONS.md with:"
echo "  - New version numbers"
echo "  - New integrity hashes (run: npm view <pkg>@<version> dist.integrity)"
echo "  - Today's date as analysis date"
echo ""
echo "Also update the PINNED_* variables in scripts/check-versions.sh"
echo ""
echo "=== Upgrade flow complete ==="
echo ""
echo "Next steps:"
echo "  1. Update VERSIONS.md and scripts/check-versions.sh"
echo "  2. Regenerate reports: node security/generate-report.js && node security/generate-getting-started.js"
echo "  3. Commit all changes"
echo "  4. Start normally: ./scripts/start.sh"
