#!/usr/bin/env bash
set -euo pipefail

echo "=== Paperclip Sandbox ==="
echo "  PAPERCLIP_HOME: $PAPERCLIP_HOME"
echo "  PAPERCLIP_PORT: ${PAPERCLIP_PORT:-3100}"
echo "  DO_NOT_TRACK:   ${DO_NOT_TRACK:-0}"
echo "  Telemetry:      $([ "${DO_NOT_TRACK:-0}" = "1" ] && echo "DISABLED" || echo "enabled")"
echo ""

# Verify installed versions match expected pinned versions
echo "--- Version Verification ---"
INSTALLED_COMPANIES=$(npx companies.sh --version 2>/dev/null || echo "unknown")
INSTALLED_PAPERCLIP=$(npm ls paperclipai --depth=0 2>/dev/null | grep paperclipai | sed 's/.*@//' || echo "unknown")
echo "  companies.sh:  $INSTALLED_COMPANIES"
echo "  paperclipai:   $INSTALLED_PAPERCLIP"
echo "---"
echo ""

# Auto-onboard if not already configured
if [ ! -f "$PAPERCLIP_HOME/instances/${PAPERCLIP_INSTANCE_ID:-default}/config.json" ]; then
  echo "First run detected — running onboard..."
  npx paperclipai onboard --yes
  echo ""
fi

# Network isolation check
echo "--- Network Isolation Check ---"
if curl -sf --noproxy '*' --connect-timeout 3 --max-time 5 http://1.1.1.1 >/dev/null 2>&1; then
  echo "  WARN: Container can reach external IPs directly (open mode or no sandbox)"
else
  echo "  PASS: Direct external IP access blocked"
fi
echo "---"
echo ""

# Health check
echo "Running diagnostics..."
npx paperclipai doctor || true
echo ""

# Start server
echo "Starting Paperclip server on port ${PAPERCLIP_PORT:-3100}..."
exec npx paperclipai run
