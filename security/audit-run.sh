#!/usr/bin/env bash
set -euo pipefail

# audit-run.sh — Post-run audit for paperclip-sandbox
# Usage: ./security/audit-run.sh /tmp/paperclip-sandbox-marker-TIMESTAMP

MARKER="${1:-}"

if [ -z "$MARKER" ] || [ ! -f "$MARKER" ]; then
  echo "Usage: $0 /tmp/paperclip-sandbox-marker-TIMESTAMP"
  echo "  (The marker path is printed by scripts/start.sh)"
  exit 1
fi

echo "=== Post-Run Security Audit ==="
echo "Marker: $MARKER ($(stat -f '%Sm' "$MARKER"))"
echo ""

# 1. Check for files modified outside project dir since the run
echo "--- Files modified in home dir since run (excluding caches/trash) ---"
MODIFIED=$(find "$HOME" -newer "$MARKER" -type f 2>/dev/null \
  | grep -v "paperclip-sandbox" \
  | grep -v "Library/Caches" \
  | grep -v "Library/Saved Application State" \
  | grep -v "Library/Preferences" \
  | grep -v ".Trash" \
  | grep -v ".DS_Store" \
  | grep -v "Library/Application Support/Code" \
  | grep -v "Library/Group Containers" \
  | head -30) || true

if [ -n "$MODIFIED" ]; then
  echo "WARNING: Files modified outside project directory:"
  echo "$MODIFIED"
else
  echo "PASS: No unexpected file modifications detected."
fi
echo ""

# 2. Check for new LaunchAgents (persistence mechanism)
echo "--- New LaunchAgents ---"
NEW_AGENTS=$(find "$HOME/Library/LaunchAgents" -newer "$MARKER" -type f 2>/dev/null | head -10) || true
if [ -n "$NEW_AGENTS" ]; then
  echo "WARNING: New LaunchAgents installed:"
  echo "$NEW_AGENTS"
else
  echo "PASS: No new LaunchAgents."
fi
echo ""

# 3. Check for unexpected background processes
echo "--- Suspicious background processes ---"
SUSPICIOUS=$(ps aux 2>/dev/null \
  | grep -iE "paperclip|companies|embedded-postgres" \
  | grep -v grep \
  | head -10) || true

if [ -n "$SUSPICIOUS" ]; then
  echo "WARNING: Related processes still running:"
  echo "$SUSPICIOUS"
else
  echo "PASS: No related background processes found."
fi
echo ""

# 4. Check for listening ports
echo "--- Listening ports (node/postgres) ---"
PORTS=$(lsof -i -P -n 2>/dev/null \
  | grep -iE "node|postgres" \
  | grep LISTEN \
  | head -10) || true

if [ -n "$PORTS" ]; then
  echo "WARNING: Node/Postgres processes listening:"
  echo "$PORTS"
else
  echo "PASS: No node/postgres listeners found."
fi
echo ""

# 5. Check for telemetry files
echo "--- Telemetry artifacts ---"
if [ -f "$HOME/.config/companies.sh/telemetry.json" ]; then
  echo "WARNING: Telemetry file exists at ~/.config/companies.sh/telemetry.json"
  cat "$HOME/.config/companies.sh/telemetry.json"
else
  echo "PASS: No telemetry file found."
fi
echo ""

# 6. Check Docker containers still running
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  echo "--- Docker containers ---"
  RUNNING=$(docker ps --filter "name=paperclip-sandbox" --format "{{.ID}} {{.Status}}" 2>/dev/null) || true
  if [ -n "$RUNNING" ]; then
    echo "WARNING: Sandbox containers still running:"
    echo "$RUNNING"
  else
    echo "PASS: No sandbox containers running."
  fi
else
  echo "SKIP: Docker not available for container check."
fi
echo ""

echo "=== Audit Complete ==="
